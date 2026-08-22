import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { spawn } from 'child_process';
import { promises as fs } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { randomUUID } from 'crypto';

const ALLOWED_HOSTS = new Set([
  'instagram.com',
  'www.instagram.com',
  'm.instagram.com',
  'tiktok.com',
  'www.tiktok.com',
  'm.tiktok.com',
  'vm.tiktok.com',
  'vt.tiktok.com',
]);

const SHORT_LINK_HOSTS = new Set(['vm.tiktok.com', 'vt.tiktok.com']);

export type VideoResolverErrorCode =
  | 'unsupported_url'
  | 'login_required'
  | 'private_video'
  | 'video_unavailable'
  | 'too_large'
  | 'timeout'
  | 'unknown';

export class VideoResolverError extends Error {
  constructor(
    public readonly code: VideoResolverErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'VideoResolverError';
  }
}

export interface DownloadedVideo {
  tmpPath: string;
  ext: string;
  contentType: string;
  sizeBytes?: number;
  title?: string;
  description?: string;
  uploader?: string;
  thumbnail?: string;
}

export interface DownloadedImage {
  tmpPath: string;
  contentType: string;
  sizeBytes?: number;
}

export interface DownloadedImages {
  images: DownloadedImage[];
  title?: string;
  description?: string;
  uploader?: string;
  thumbnail?: string;
}

// Defensive caps for photo carousels: TikTok allows up to 35 images per
// post; anything past 20 adds little signal for pin extraction, and the
// byte cap bounds tmp-disk + Gemini payload size.
const MAX_CAROUSEL_IMAGES = 20;
const MAX_CAROUSEL_TOTAL_BYTES = 50 * 1024 * 1024;

// TikTok's CDN 403s bare fetches; a browser UA *plus* a tiktok.com Referer
// is the known-working combination for the signed image URLs.
const IMAGE_FETCH_HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36',
  Referer: 'https://www.tiktok.com/',
};

@Injectable()
export class VideoResolverService {
  private readonly logger = new Logger(VideoResolverService.name);

  constructor(private readonly config: ConfigService) {}

  // Canonicalize an IG/TikTok URL so cache lookups collapse equivalent variants
  // (short links, www/m subdomains, /p/ vs /reel/, tracking params).
  async canonicalizeSourceUrl(raw: string): Promise<string> {
    let parsed: URL;
    try {
      parsed = new URL(raw.trim());
    } catch {
      throw new VideoResolverError('unsupported_url', 'URL is not parseable');
    }
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      throw new VideoResolverError(
        'unsupported_url',
        'Only http/https URLs are supported',
      );
    }
    let host = parsed.host.toLowerCase();
    if (!ALLOWED_HOSTS.has(host)) {
      throw new VideoResolverError(
        'unsupported_url',
        `Host ${host} is not supported. Paste a public Instagram or TikTok link.`,
      );
    }

    // Resolve TikTok short links to their canonical /@user/video/<id> form.
    if (SHORT_LINK_HOSTS.has(host)) {
      try {
        const resolved = await this.resolveRedirect(parsed.toString());
        parsed = new URL(resolved);
        host = parsed.host.toLowerCase();
      } catch (err) {
        this.logger.warn(
          `Failed to resolve short link ${raw}: ${(err as Error).message}`,
        );
        // Fall through with the short-link host; the cache key will still be
        // stable for the same short link.
      }
    }

    // Normalize host aliases.
    if (host === 'm.tiktok.com') host = 'www.tiktok.com';
    if (host === 'm.instagram.com' || host === 'instagram.com') {
      host = 'www.instagram.com';
    }

    // Normalize Instagram path: /p/<id> and /reels/<id> → /reel/<id>.
    let path = parsed.pathname.replace(/\/+$/, '');
    if (host === 'www.instagram.com') {
      path = path.replace(/^\/reels\//, '/reel/').replace(/^\/p\//, '/reel/');
    }

    return `https://${host}${path}`;
  }

  // TikTok photo (image carousel) posts live at /@user/photo/<id>. yt-dlp
  // does not support them (wontfix upstream), so they route to gallery-dl.
  // Expects a canonicalized URL: short links have already been resolved, so
  // a photo post behind vm/vt.tiktok.com is detected too (unless redirect
  // resolution failed, in which case the video path fails with
  // unsupported_url — accepted degradation, credit is refunded).
  isTikTokPhotoUrl(canonicalUrl: string): boolean {
    try {
      const u = new URL(canonicalUrl);
      return (
        (u.hostname === 'tiktok.com' || u.hostname.endsWith('.tiktok.com')) &&
        /^\/@[^/]+\/photo\//.test(u.pathname)
      );
    } catch {
      return false;
    }
  }

  // Number of full yt-dlp invocations to attempt before giving up, and the
  // base backoff between them. TikTok/Instagram intermittently serve anti-bot
  // challenge pages (surfacing as "Unexpected response from webpage request" /
  // "Unable to extract universal data for rehydration"), which yt-dlp's own
  // --extractor-retries doesn't always recover from. Re-spawning the whole
  // process a couple of times clears the transient failures that would
  // otherwise hard-fail a scan (and trigger a scan-credit refund).
  private static readonly MAX_DOWNLOAD_ATTEMPTS = 3;
  private static readonly RETRY_BASE_DELAY_MS = 1000;

  // Download with yt-dlp, retrying transient failures with exponential backoff.
  // Honors AbortSignal so an SSE disconnect short-circuits both the in-flight
  // process and any pending retry wait.
  async download(
    canonicalUrl: string,
    signal?: AbortSignal,
  ): Promise<DownloadedVideo> {
    return this.withRetries(
      'yt-dlp',
      () => this.spawnDownload(canonicalUrl, signal),
      signal,
    );
  }

  // Download a TikTok photo carousel's images via gallery-dl. Same retry
  // semantics as `download` — gallery-dl's TikTok JS-challenge solver
  // intermittently 403s and retrying typically succeeds.
  async downloadImages(
    canonicalUrl: string,
    signal?: AbortSignal,
  ): Promise<DownloadedImages> {
    return this.withRetries(
      'gallery-dl',
      () => this.spawnGalleryDl(canonicalUrl, signal),
      signal,
    );
  }

  // Shared retry loop with exponential backoff. Only transient `unknown`
  // errors are retried; permanent failures and aborts throw immediately.
  private async withRetries<T>(
    label: string,
    attemptFn: () => Promise<T>,
    signal?: AbortSignal,
  ): Promise<T> {
    const maxAttempts = VideoResolverService.MAX_DOWNLOAD_ATTEMPTS;
    let lastError: VideoResolverError | undefined;
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await attemptFn();
      } catch (err) {
        if (!(err instanceof VideoResolverError)) throw err;
        lastError = err;
        // Permanent failures (private/unavailable/unsupported/too large) and
        // aborts must not be retried — only transient `unknown` errors are.
        if (
          attempt >= maxAttempts ||
          signal?.aborted ||
          !this.isRetryable(err.code)
        ) {
          throw err;
        }
        const delayMs =
          VideoResolverService.RETRY_BASE_DELAY_MS * 2 ** (attempt - 1);
        this.logger.warn(
          `${label} attempt ${attempt}/${maxAttempts} failed (${err.code}), retrying in ${delayMs}ms: ${err.message}`,
        );
        await this.delay(delayMs, signal);
      }
    }
    // Unreachable in practice — the loop either returns or throws — but keeps
    // the type checker happy and guards against an empty-loop edge case.
    throw lastError ?? new VideoResolverError('unknown', 'Download failed');
  }

  // Transient extractor/anti-bot failures map to `unknown`; everything else is
  // a definitive answer about the video and re-running won't change it.
  private isRetryable(code: VideoResolverErrorCode): boolean {
    return code === 'unknown';
  }

  // setTimeout that rejects early if the AbortSignal fires, so a disconnected
  // SSE client doesn't keep us sleeping between retries.
  private delay(ms: number, signal?: AbortSignal): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      if (signal?.aborted) {
        reject(new VideoResolverError('timeout', 'Download aborted'));
        return;
      }
      const onAbort = () => {
        clearTimeout(timer);
        reject(new VideoResolverError('timeout', 'Download aborted'));
      };
      const timer = setTimeout(() => {
        signal?.removeEventListener('abort', onAbort);
        resolve();
      }, ms);
      signal?.addEventListener('abort', onAbort, { once: true });
    });
  }

  // A single yt-dlp invocation. Honors AbortSignal so an SSE disconnect can
  // kill the spawned process and clean up the partial /tmp file.
  private spawnDownload(
    canonicalUrl: string,
    signal?: AbortSignal,
  ): Promise<DownloadedVideo> {
    const ytDlpPath = this.config.get<string>('YT_DLP_PATH') ?? 'yt-dlp';
    const id = randomUUID();
    const outputTemplate = join(tmpdir(), `pin-${id}.%(ext)s`);

    const args = [
      '--no-playlist',
      '-f',
      // Prefer ≤720p mp4 to shrink the file 2-4x: Gemini reads on-screen
      // text fine at 720p, and a smaller file speeds up both the download
      // here AND the downstream inline/Files-API path. Fallback chain keeps
      // current behavior when 720p mp4 isn't available.
      'best[height<=720][ext=mp4]/best[height<=720]/best[ext=mp4]/best',
      '-o',
      outputTemplate,
      '--max-filesize',
      '200M',
      '--socket-timeout',
      '15',
      // yt-dlp's own retries for network blips and extractor hiccups within a
      // single invocation; the app-level retry above re-spawns the process for
      // failures these don't catch (e.g. anti-bot rehydration errors).
      '--retries',
      '3',
      '--extractor-retries',
      '3',
      '--no-warnings',
      '--no-progress',
      '--print',
      'before_dl:META_JSON:%(.{title,description,uploader,thumbnail})j',
      '--print',
      'after_move:FILEPATH:%(filepath)s',
      // `--` terminates flag parsing so the URL is unambiguously a positional
      // argument even if a future canonicalized path begins with `--`.
      '--',
      canonicalUrl,
    ];

    return new Promise<DownloadedVideo>((resolve, reject) => {
      const proc = spawn(ytDlpPath, args, {
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      let stdout = '';
      let stderr = '';
      let settled = false;

      const onAbort = () => {
        if (!settled) {
          settled = true;
          proc.kill('SIGTERM');
          reject(new VideoResolverError('timeout', 'Download aborted'));
        }
      };
      signal?.addEventListener('abort', onAbort, { once: true });

      proc.stdout.on('data', (chunk) => {
        stdout += chunk.toString();
      });
      proc.stderr.on('data', (chunk) => {
        stderr += chunk.toString();
      });
      proc.on('error', (err) => {
        if (settled) return;
        settled = true;
        signal?.removeEventListener('abort', onAbort);
        reject(
          new VideoResolverError(
            'unknown',
            `Failed to spawn yt-dlp: ${err.message}`,
          ),
        );
      });
      proc.on('close', (exitCode) => {
        if (settled) return;
        settled = true;
        signal?.removeEventListener('abort', onAbort);
        if (exitCode !== 0) {
          const code = this.mapStderrToCode(stderr);
          reject(
            new VideoResolverError(
              code,
              this.humanMessage(code, stderr.trim()),
            ),
          );
          return;
        }
        const lines = stdout
          .split(/\r?\n/)
          .map((l) => l.trim())
          .filter(Boolean);
        const filePathLine = lines.find((l) => l.startsWith('FILEPATH:'));
        const metaLine = lines.find((l) => l.startsWith('META_JSON:'));
        const filePath = filePathLine
          ? filePathLine.slice('FILEPATH:'.length).trim()
          : undefined;
        if (!filePath) {
          reject(
            new VideoResolverError(
              'unknown',
              'yt-dlp completed but no output path was reported',
            ),
          );
          return;
        }
        const ext = filePath.split('.').pop()?.toLowerCase() ?? 'mp4';
        let title: string | undefined;
        let description: string | undefined;
        let uploader: string | undefined;
        let thumbnail: string | undefined;
        if (metaLine) {
          try {
            const parsed = JSON.parse(metaLine.slice('META_JSON:'.length)) as {
              title?: string | null;
              description?: string | null;
              uploader?: string | null;
              thumbnail?: string | string[] | null;
            };
            title = parsed.title?.trim() || undefined;
            description = parsed.description?.trim() || undefined;
            uploader = parsed.uploader?.trim() || undefined;
            // yt-dlp's `thumbnail` is normally a scalar URL, but some
            // extractor paths leave it as an array (highest-res last).
            const rawThumb = parsed.thumbnail;
            thumbnail =
              typeof rawThumb === 'string'
                ? rawThumb.trim() || undefined
                : Array.isArray(rawThumb)
                  ? (
                      rawThumb[rawThumb.length - 1] as string | undefined
                    )?.trim() || undefined
                  : undefined;
          } catch {
            // best-effort metadata; ignore parse errors
          }
        }
        // Stat the file so downstream can decide inline vs Files API without
        // re-reading. Best-effort — missing size just forces Files API path.
        fs.stat(filePath)
          .then((stat) => {
            resolve({
              tmpPath: filePath,
              ext,
              contentType: this.contentTypeForExt(ext),
              sizeBytes: stat.size,
              title,
              description,
              uploader,
              thumbnail,
            });
          })
          .catch(() => {
            resolve({
              tmpPath: filePath,
              ext,
              contentType: this.contentTypeForExt(ext),
              title,
              description,
              uploader,
              thumbnail,
            });
          });
      });
    });
  }

  // A single gallery-dl attempt: `-j` prints metadata + signed CDN image
  // URLs without writing files; we then fetch each image ourselves so tmp
  // handling matches the yt-dlp path. Signed URLs expire, so images are
  // fetched immediately after extraction.
  private async spawnGalleryDl(
    canonicalUrl: string,
    signal?: AbortSignal,
  ): Promise<DownloadedImages> {
    const { stdout, stderr } = await this.runGalleryDlJson(
      canonicalUrl,
      signal,
    );

    // `-j` output is gallery-dl's internal message-tuple format:
    //   [2, postMeta] — directory/post metadata
    //   [3, imageUrl, imageMeta] — one per file
    // It's long-stable but not a documented contract — parse defensively and
    // skip anything unrecognized.
    let entries: unknown;
    try {
      entries = JSON.parse(stdout);
    } catch {
      throw new VideoResolverError(
        'unknown',
        'gallery-dl returned unparseable output',
      );
    }
    if (!Array.isArray(entries)) {
      throw new VideoResolverError(
        'unknown',
        'gallery-dl returned unexpected output shape',
      );
    }

    let title: string | undefined;
    let description: string | undefined;
    let uploader: string | undefined;
    const imageUrls: string[] = [];
    for (const entry of entries) {
      if (!Array.isArray(entry) || typeof entry[0] !== 'number') continue;
      if (entry[0] === 2 && typeof entry[1] === 'object' && entry[1] !== null) {
        const meta = entry[1] as {
          title?: unknown;
          desc?: unknown;
          author?: { nickname?: unknown; uniqueId?: unknown } | null;
        };
        const str = (v: unknown) =>
          typeof v === 'string' && v.trim() ? v.trim() : undefined;
        description = str(meta.desc) ?? description;
        title = str(meta.title) ?? title ?? description;
        uploader =
          str(meta.author?.nickname) ?? str(meta.author?.uniqueId) ?? uploader;
      } else if (entry[0] === 3 && typeof entry[1] === 'string') {
        // Photo posts also carry their background-audio track as a file
        // entry (extension mp3/m4a) — feeding that to Gemini as an "image"
        // 400s the whole request. Keep only image-extension entries.
        const fileMeta = entry[2] as { extension?: unknown } | undefined;
        const ext =
          typeof fileMeta?.extension === 'string'
            ? fileMeta.extension.toLowerCase()
            : undefined;
        if (ext && !this.contentTypeForExt(ext).startsWith('image/')) {
          continue;
        }
        imageUrls.push(entry[1]);
      }
    }

    if (imageUrls.length === 0) {
      // gallery-dl exits 0 even when extraction fails (e.g. the intermittent
      // TikTok 403 JS-challenge rejection) — the failure only shows on
      // stderr. Map it so 403s stay retryable instead of surfacing as a
      // definitive "no images".
      if (/\[error\]/i.test(stderr)) {
        const code = this.mapGalleryDlStderrToCode(stderr);
        throw new VideoResolverError(code, this.humanMessage(code, stderr));
      }
      throw new VideoResolverError(
        'video_unavailable',
        'No images found in this post',
      );
    }

    const capped = imageUrls.slice(0, MAX_CAROUSEL_IMAGES);
    if (capped.length < imageUrls.length) {
      this.logger.warn(
        `carousel has ${imageUrls.length} images; analyzing first ${capped.length}`,
      );
    }

    // Fetch every image, cleaning up already-written tmp files on any
    // failure so the retry loop doesn't leak partial sets.
    const images: DownloadedImage[] = [];
    let totalBytes = 0;
    try {
      for (const [i, url] of capped.entries()) {
        if (signal?.aborted) {
          throw new VideoResolverError('timeout', 'Download aborted');
        }
        const fetched = await this.fetchImage(url, i, signal);
        if (!fetched) continue; // non-image payload (e.g. audio) — skip
        images.push(fetched);
        totalBytes += fetched.sizeBytes ?? 0;
        if (totalBytes > MAX_CAROUSEL_TOTAL_BYTES) {
          throw new VideoResolverError(
            'too_large',
            'This post is too large to analyze.',
          );
        }
      }
    } catch (err) {
      await Promise.all(images.map((img) => this.cleanup(img.tmpPath)));
      throw err;
    }

    if (images.length === 0) {
      throw new VideoResolverError(
        'video_unavailable',
        'No images found in this post',
      );
    }

    return { images, title, description, uploader, thumbnail: capped[0] };
  }

  // Spawn `gallery-dl -j -- <url>` and return its stdout + stderr. stderr is
  // needed even on exit 0: gallery-dl reports per-post extraction failures
  // there without a non-zero exit code. Honors AbortSignal by killing the
  // child, mirroring the yt-dlp spawn.
  private runGalleryDlJson(
    canonicalUrl: string,
    signal?: AbortSignal,
  ): Promise<{ stdout: string; stderr: string }> {
    const galleryDlPath =
      this.config.get<string>('GALLERY_DL_PATH') ?? 'gallery-dl';
    return new Promise<{ stdout: string; stderr: string }>(
      (resolve, reject) => {
        const proc = spawn(galleryDlPath, ['-j', '--', canonicalUrl], {
          stdio: ['ignore', 'pipe', 'pipe'],
        });
        let stdout = '';
        let stderr = '';
        let settled = false;

        const onAbort = () => {
          if (!settled) {
            settled = true;
            proc.kill('SIGTERM');
            reject(new VideoResolverError('timeout', 'Download aborted'));
          }
        };
        signal?.addEventListener('abort', onAbort, { once: true });

        proc.stdout.on('data', (chunk) => {
          stdout += chunk.toString();
        });
        proc.stderr.on('data', (chunk) => {
          stderr += chunk.toString();
        });
        proc.on('error', (err) => {
          if (settled) return;
          settled = true;
          signal?.removeEventListener('abort', onAbort);
          reject(
            new VideoResolverError(
              'unknown',
              `Failed to spawn gallery-dl: ${err.message}`,
            ),
          );
        });
        proc.on('close', (exitCode) => {
          if (settled) return;
          settled = true;
          signal?.removeEventListener('abort', onAbort);
          if (exitCode !== 0) {
            const code = this.mapGalleryDlStderrToCode(stderr);
            reject(
              new VideoResolverError(
                code,
                this.humanMessage(code, stderr.trim()),
              ),
            );
            return;
          }
          resolve({ stdout, stderr });
        });
      },
    );
  }

  // Fetch one signed CDN image URL into tmpdir. Content type comes from the
  // response header when it's an image/*, else from the URL's extension.
  // Returns null when the payload turns out not to be an image at all
  // (defense in depth against non-image file entries slipping past the
  // extension filter — Gemini 400s the whole request on a bad "image").
  private async fetchImage(
    url: string,
    index: number,
    signal?: AbortSignal,
  ): Promise<DownloadedImage | null> {
    let res: Response;
    try {
      res = await fetch(url, { headers: IMAGE_FETCH_HEADERS, signal });
    } catch (err) {
      if (signal?.aborted) {
        throw new VideoResolverError('timeout', 'Download aborted');
      }
      throw new VideoResolverError(
        'unknown',
        `Image fetch failed: ${(err as Error).message}`,
      );
    }
    if (!res.ok) {
      // Signed-URL rejections (403) are transient bot-detection noise —
      // keep them retryable via `unknown`.
      throw new VideoResolverError(
        'unknown',
        `Image fetch returned HTTP ${res.status}`,
      );
    }
    const bytes = Buffer.from(await res.arrayBuffer());
    const headerType = res.headers.get('content-type')?.split(';')[0].trim();
    const urlExt = new URL(url).pathname
      .split('.')
      .pop()
      ?.toLowerCase()
      ?.replace(/[^a-z0-9]/g, '');
    const fromExt = this.contentTypeForExt(urlExt ?? '');
    let contentType: string;
    if (headerType?.startsWith('image/')) {
      contentType = headerType;
    } else if (fromExt.startsWith('image/')) {
      contentType = fromExt;
    } else if (headerType && !headerType.startsWith('image/')) {
      // Definitively not an image (e.g. the post's audio track).
      this.logger.warn(`skipping non-image carousel entry (${headerType})`);
      return null;
    } else {
      contentType = 'image/jpeg'; // TikTok carousels are JPEG in practice
    }
    const ext = contentType.split('/').pop() ?? 'jpeg';
    const tmpPath = join(tmpdir(), `pin-${randomUUID()}-${index}.${ext}`);
    await fs.writeFile(tmpPath, bytes);
    return { tmpPath, contentType, sizeBytes: bytes.length };
  }

  private mapGalleryDlStderrToCode(stderr: string): VideoResolverErrorCode {
    const s = stderr.toLowerCase();
    if (s.includes('unsupported url') || s.includes('no suitable extractor')) {
      return 'unsupported_url';
    }
    if (s.includes('login') || s.includes('cookies')) return 'login_required';
    if (s.includes('404') || s.includes('not available')) {
      return 'video_unavailable';
    }
    // 403 / "Failed to extract post" are the intermittent JS-challenge
    // failures — retryable.
    return 'unknown';
  }

  async cleanup(tmpPath: string): Promise<void> {
    try {
      await fs.unlink(tmpPath);
    } catch {
      // best-effort
    }
  }

  private async resolveRedirect(url: string): Promise<string> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    try {
      const res = await fetch(url, {
        method: 'HEAD',
        redirect: 'follow',
        signal: controller.signal,
      });
      return res.url || url;
    } finally {
      clearTimeout(timeout);
    }
  }

  private mapStderrToCode(stderr: string): VideoResolverErrorCode {
    const s = stderr.toLowerCase();
    if (s.includes('unsupported url')) return 'unsupported_url';
    if (s.includes('login required') || s.includes('cookies'))
      return 'login_required';
    if (s.includes('private video') || s.includes('this post is private'))
      return 'private_video';
    if (
      s.includes('video unavailable') ||
      s.includes('http error 404') ||
      s.includes('this video is no longer available')
    ) {
      return 'video_unavailable';
    }
    if (s.includes('file is larger than') || s.includes('exceeds the')) {
      return 'too_large';
    }
    return 'unknown';
  }

  private humanMessage(
    code: VideoResolverErrorCode,
    stderrTail: string,
  ): string {
    switch (code) {
      case 'unsupported_url':
        return 'This link is not supported. Paste a public Instagram Reel or TikTok URL.';
      case 'login_required':
        return 'This post requires a login. Only public posts are supported.';
      case 'private_video':
        return 'This post is private and cannot be analyzed.';
      case 'video_unavailable':
        return 'This post is no longer available.';
      case 'too_large':
        return 'This post is too large to analyze.';
      case 'timeout':
        return 'Resolving the post took too long.';
      default:
        return `Could not download post: ${stderrTail.slice(0, 200)}`;
    }
  }

  private contentTypeForExt(ext: string): string {
    switch (ext) {
      case 'mp4':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      case 'mov':
        return 'video/quicktime';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        return 'application/octet-stream';
    }
  }
}
