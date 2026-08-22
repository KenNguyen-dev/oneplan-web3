import {
  BadGatewayException,
  Injectable,
  Logger,
  UnprocessableEntityException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Storage } from '@google-cloud/storage';
import { GoogleAuth } from 'google-auth-library';
import { promises as fs } from 'fs';
import { randomUUID } from 'crypto';

const ANALYZE_TIMEOUT_MS = 8 * 60_000;

// Videos at or below this raw byte size are sent inline in the
// streamGenerateContent request body, skipping the GCS round-trip. Vertex
// AI's request-body limit is 20MB; 15MB raw → ~20MB base64 leaves room for
// the prompt + schema. Above this, we upload to GCS and reference via
// `gs://` URI.
const INLINE_MAX_BYTES = 15 * 1024 * 1024;

export type AnalyzePhase = 'uploading' | 'processing' | 'analyzing';

const SYSTEM_PROMPT = `You are a travel pin extractor for a social-video → trip-board app. Watch the video and extract ONLY named, searchable venues — places a user could later find on Google Maps or Apple Maps.

What to INCLUDE:
- Specific named restaurants, cafés, bars, hotels, shops, markets, viewpoints, landmarks, museums, tours.
- Read on-screen text overlays carefully — TikTok/Reels videos almost always show the venue name in Vietnamese/local-language captions, address signs, storefront signs, or pinned text. Quote the name VERBATIM from those overlays. Do not paraphrase or translate it.
- If the video has voiceover or subtitles that name the spot, prefer that exact spelling.
- Diacritics matter — preserve Vietnamese tone marks exactly (e.g. "Bánh mì xíu mại Cô Tuyết", not "Banh mi xiu mai Co Tuyet").

What to EXCLUDE — do NOT emit pins for any of these:
- Generic scenery or transport: "Beach", "Highway", "Train", "Airport", "Hotel Room", "Street", "Park" without a proper name.
- Abstract categories: "Chinatown", "City Center", "Downtown" — only include if the video shows a specific named landmark inside.
- Activities or moments ("Sunset View", "Lunch", "Coffee Break").
- Cities or countries by themselves. Use the "city" / "country" fields for those instead.

Field rules:
- "name" is REQUIRED. The exact venue name as shown in the video, with diacritics. If you cannot find a specific name, drop the pin entirely.
- "city" is the city/town (e.g. "Da Lat"). "country" is the country (e.g. "Vietnam"). These let downstream code reconcile against Maps APIs.
- "category" must be one of the values in the response schema. Use "airport" for named airports.
- "notes" is one short sentence describing what the user sees/does at this spot in the video.
- "sourceTimestampSec" is the second-mark where the venue first appears.
- "dayNumber" is the itinerary day this venue belongs to, ONLY when the video explicitly labels days ("Day 1", "ngày 2", "D3"). 1-based integer. Omit when the video has no explicit day structure — never guess.
- "timeOfDayText" is a short verbatim time mention for WHEN THE CREATOR VISITS this venue, from narration/overlays ("9am", "sáng", "morning", "after lunch", "5:30pm"). A single point in time, never a range. Do NOT use the venue's opening hours ("7:00-17:00", "open 9am-5pm") — omit instead. Omit when no visit time is mentioned — never infer one.

Quality over quantity. If a video shows 20 random shots but only 6 named venues, return 6 pins.`;

// Variant of SYSTEM_PROMPT for TikTok photo-carousel posts: the input is an
// ordered set of still images instead of a video, and sourceTimestampSec is
// repurposed as the 0-based image index (keeps the response schema, DTOs,
// cache payload, and the iOS contract untouched).
const PHOTO_SYSTEM_PROMPT = `You are a travel pin extractor for a social-post → trip-board app. You are given the images of a TikTok photo-carousel travel post, in their original order. Examine every image and extract ONLY named, searchable venues — places a user could later find on Google Maps or Apple Maps.

What to INCLUDE:
- Specific named restaurants, cafés, bars, hotels, shops, markets, viewpoints, landmarks, museums, tours.
- Read on-screen text overlays carefully — these posts almost always show the venue name in Vietnamese/local-language captions, address signs, storefront signs, or pinned text. Quote the name VERBATIM from those overlays. Do not paraphrase or translate it.
- Diacritics matter — preserve Vietnamese tone marks exactly (e.g. "Bánh mì xíu mại Cô Tuyết", not "Banh mi xiu mai Co Tuyet").

What to EXCLUDE — do NOT emit pins for any of these:
- Generic scenery or transport: "Beach", "Highway", "Train", "Airport", "Hotel Room", "Street", "Park" without a proper name.
- Abstract categories: "Chinatown", "City Center", "Downtown" — only include if an image shows a specific named landmark inside.
- Activities or moments ("Sunset View", "Lunch", "Coffee Break").
- Cities or countries by themselves. Use the "city" / "country" fields for those instead.

Field rules:
- "name" is REQUIRED. The exact venue name as shown in the images, with diacritics. If you cannot find a specific name, drop the pin entirely.
- "city" is the city/town (e.g. "Da Lat"). "country" is the country (e.g. "Vietnam"). These let downstream code reconcile against Maps APIs.
- "category" must be one of the values in the response schema. Use "airport" for named airports.
- "notes" is one short sentence describing what the user sees/does at this spot.
- "sourceTimestampSec" is the 0-based index of the image where the venue first appears (first image → 0).
- "dayNumber" is the itinerary day this venue belongs to, ONLY when the post explicitly labels days ("Day 1", "ngày 2", "D3"). 1-based integer. Omit when the post has no explicit day structure — never guess.
- "timeOfDayText" is a short verbatim time mention for WHEN THE CREATOR VISITS this venue, from captions/overlays ("9am", "sáng", "morning", "after lunch", "5:30pm"). A single point in time, never a range. Do NOT use the venue's opening hours ("7:00-17:00", "open 9am-5pm") — omit instead. Omit when no visit time is mentioned — never infer one.

Quality over quantity. If a post shows 20 random shots but only 6 named venues, return 6 pins.`;

// Gemini wants UPPERCASE string types in response schemas.
const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    locations: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        required: ['name'],
        properties: {
          name: { type: 'STRING' },
          city: { type: 'STRING' },
          country: { type: 'STRING' },
          category: {
            type: 'STRING',
            enum: [
              'restaurant',
              'cafe',
              'bar',
              'hotel',
              'shop',
              'viewpoint',
              'landmark',
              'park',
              'beach',
              'museum',
              'airport',
              'cinema',
              'grocery',
              'gym',
              'medical',
              'spa',
              'other',
            ],
          },
          notes: { type: 'STRING' },
          sourceTimestampSec: { type: 'NUMBER' },
          dayNumber: { type: 'NUMBER' },
          timeOfDayText: { type: 'STRING' },
        },
      },
    },
  },
};

// Default safety thresholds occasionally block harmless travel-vlog content;
// loosen to BLOCK_ONLY_HIGH for all four categories.
const SAFETY_SETTINGS = [
  { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_ONLY_HIGH' },
  { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'BLOCK_ONLY_HIGH' },
  { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'BLOCK_ONLY_HIGH' },
  { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'BLOCK_ONLY_HIGH' },
];

// Thrown on non-2xx Vertex responses. Extends BadGatewayException so callers
// that don't handle it keep the pre-existing 502 behaviour; `vertexStatus`
// carries the upstream HTTP status for callers that implement model
// fallbacks (404 model not available, 429 quota).
export class GeminiRequestError extends BadGatewayException {
  constructor(
    readonly vertexStatus: number,
    detail: string,
  ) {
    super(`Gemini request failed (${vertexStatus}): ${detail}`);
  }
}

export interface ExtractedPin {
  name: string;
  address?: string;
  city?: string;
  country?: string;
  category?: string;
  latitude?: number;
  longitude?: number;
  notes?: string;
  sourceTimestampSec?: number;
  dayNumber?: number;
  timeOfDayText?: string;
}

interface GCSResource {
  objectKey: string;
  gcsUri: string;
}

// Config needed for any Vertex generateContent call. The receipt-scan and
// board-description paths use only this — they never stage to GCS, so they
// must NOT require GCS_GEMINI_BUCKET.
interface VertexGenConfig {
  projectId: string;
  location: string;
  modelId: string;
  debug: boolean;
}

// Adds the GCS staging bucket required by the video (analyzeStream) path.
interface VertexConfig extends VertexGenConfig {
  bucket: string;
}

@Injectable()
export class GeminiService {
  private readonly logger = new Logger(GeminiService.name);
  private auth?: GoogleAuth;
  private storage?: Storage;

  constructor(private readonly config: ConfigService) {}

  async *analyzeStream(
    localPath: string,
    contentType: string,
    signal: AbortSignal,
    onPhase?: (phase: AnalyzePhase) => void | Promise<void>,
  ): AsyncGenerator<ExtractedPin> {
    const cfg = this.requireConfig();

    // Read once up-front so we can decide inline vs GCS without a second
    // fs.readFile on the upload path.
    const bytes = await fs.readFile(localPath);
    const useInline = bytes.length <= INLINE_MAX_BYTES;

    // GCS path tracks an uploaded object for explicit cleanup. The inline
    // path leaves this undefined and the finally below skips delete.
    let gcsResource: GCSResource | undefined;
    let videoPart: object;

    try {
      if (useInline) {
        // Inline path — no GCS round-trip at all.
        // IMPORTANT: Vertex's REST API is camelCase (`inlineData` / `mimeType`).
        // Wrong casing 400s silently and yields 0 pins.
        this.logger.log(
          `inline path (${bytes.length} bytes ≤ ${INLINE_MAX_BYTES})`,
        );
        videoPart = {
          inlineData: {
            mimeType: contentType,
            data: bytes.toString('base64'),
          },
        };
      } else {
        this.logger.log(
          `gcs path (${bytes.length} bytes > ${INLINE_MAX_BYTES})`,
        );
        onPhase?.('uploading');
        gcsResource = await this.uploadToGCS(
          cfg.bucket,
          bytes,
          contentType,
          signal,
        );
        this.logger.log(`uploaded ${gcsResource.gcsUri}`);

        // GCS is read-consistent immediately; no polling required.
        onPhase?.('processing');

        videoPart = {
          fileData: {
            fileUri: gcsResource.gcsUri,
            mimeType: contentType,
          },
        };
      }

      onPhase?.('analyzing');
      yield* this.streamPins(
        cfg,
        [videoPart, { text: SYSTEM_PROMPT }],
        useInline ? 'inline' : 'gcs',
        signal,
      );
    } finally {
      // Fire-and-forget the cleanup DELETE. Awaiting it here can stall the
      // generator's close for several seconds when the bucket's delete is
      // slow. The bucket lifecycle rule (delete-after-1-day) is the safety
      // net if this fails.
      if (gcsResource) {
        const { objectKey } = gcsResource;
        const bucket = cfg.bucket;
        void this.deleteFromGCS(bucket, objectKey).catch((err) =>
          this.logger.warn(
            `Failed to delete gs://${bucket}/${objectKey}: ${(err as Error).message}`,
          ),
        );
      }
    }
  }

  // Photo-carousel variant of analyzeStream: N ordered image parts, one
  // request. Inline when the summed raw bytes fit the budget; otherwise each
  // image is staged to GCS and referenced by URI (cleaned up in finally).
  async *analyzeImagesStream(
    images: { localPath: string; contentType: string }[],
    signal: AbortSignal,
    onPhase?: (phase: AnalyzePhase) => void | Promise<void>,
  ): AsyncGenerator<ExtractedPin> {
    const cfg = this.requireConfig();

    const buffers = await Promise.all(
      images.map((img) => fs.readFile(img.localPath)),
    );
    const totalBytes = buffers.reduce((sum, b) => sum + b.length, 0);
    // Same 15MB raw budget as the video path: ~20MB after base64, which is
    // Vertex's request-body ceiling once the prompt + schema are added.
    const useInline = totalBytes <= INLINE_MAX_BYTES;

    const gcsResources: GCSResource[] = [];
    try {
      let mediaParts: object[];
      if (useInline) {
        this.logger.log(
          `inline path (${images.length} images, ${totalBytes} bytes ≤ ${INLINE_MAX_BYTES})`,
        );
        mediaParts = buffers.map((bytes, i) => ({
          inlineData: {
            mimeType: images[i].contentType,
            data: bytes.toString('base64'),
          },
        }));
      } else {
        this.logger.log(
          `gcs path (${images.length} images, ${totalBytes} bytes > ${INLINE_MAX_BYTES})`,
        );
        onPhase?.('uploading');
        mediaParts = [];
        for (const [i, bytes] of buffers.entries()) {
          const resource = await this.uploadToGCS(
            cfg.bucket,
            bytes,
            images[i].contentType,
            signal,
          );
          gcsResources.push(resource);
          mediaParts.push({
            fileData: {
              fileUri: resource.gcsUri,
              mimeType: images[i].contentType,
            },
          });
        }
        onPhase?.('processing');
      }

      onPhase?.('analyzing');
      yield* this.streamPins(
        cfg,
        [...mediaParts, { text: PHOTO_SYSTEM_PROMPT }],
        useInline ? 'inline' : 'gcs',
        signal,
      );
    } finally {
      for (const { objectKey } of gcsResources) {
        const bucket = cfg.bucket;
        void this.deleteFromGCS(bucket, objectKey).catch((err) =>
          this.logger.warn(
            `Failed to delete gs://${bucket}/${objectKey}: ${(err as Error).message}`,
          ),
        );
      }
    }
  }

  // Shared streaming core: POST streamGenerateContent with the given parts
  // and yield pins as the SSE response arrives.
  private async *streamPins(
    cfg: VertexGenConfig,
    parts: object[],
    via: 'inline' | 'gcs',
    signal: AbortSignal,
  ): AsyncGenerator<ExtractedPin> {
    // Compose+timeout AbortController for the streaming call.
    const composed = new AbortController();
    const onAbort = () => composed.abort();
    signal.addEventListener('abort', onAbort, { once: true });
    const timeoutId = setTimeout(() => composed.abort(), ANALYZE_TIMEOUT_MS);

    const url = this.vertexUrl(cfg, 'streamGenerateContent');
    this.logger.log(`POST ${url} via=${via}`);

    const token = await this.accessToken();

    let response: Response;
    try {
      response = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          contents: [
            {
              // Vertex requires an explicit role on every contents entry
              // ("user" | "model"); AI Studio accepted its absence.
              role: 'user',
              parts,
            },
          ],
          generationConfig: {
            response_mime_type: 'application/json',
            response_schema: RESPONSE_SCHEMA,
            temperature: 0,
          },
          safetySettings: SAFETY_SETTINGS,
        }),
        signal: composed.signal,
      });
    } finally {
      clearTimeout(timeoutId);
      signal.removeEventListener('abort', onAbort);
    }

    this.logger.log(
      `Vertex response status=${response.status} content-type=${response.headers.get('content-type')}`,
    );

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      this.logger.error(
        `Vertex stream ${response.status}: ${body.slice(0, 2000)}`,
      );
      throw new BadGatewayException(
        `Gemini analyze failed (${response.status}): ${body.slice(0, 500)}`,
      );
    }
    if (!response.body) {
      throw new BadGatewayException('Vertex returned an empty response');
    }

    let textBuffer = '';
    let totalChunks = 0;
    const emitted = new Set<string>();

    const decoder = new TextDecoder();
    const reader = response.body.getReader();

    // Yield results out of the parser as we go.
    try {
      let lineBuffer = '';
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        totalChunks++;
        lineBuffer += decoder.decode(value, { stream: true });

        // Process complete SSE lines. Each event is `data: <json>\n\n`.
        let nlIdx: number;
        while ((nlIdx = lineBuffer.indexOf('\n')) !== -1) {
          const rawLine = lineBuffer.slice(0, nlIdx);
          lineBuffer = lineBuffer.slice(nlIdx + 1);
          const line = rawLine.trim();
          if (!line) continue;
          if (!line.startsWith('data:')) continue;
          const dataPayload = line.slice(5).trim();
          if (!dataPayload || dataPayload === '[DONE]') continue;
          if (cfg.debug) {
            this.logger.debug(
              `Vertex chunk #${totalChunks}: ${dataPayload.slice(0, 300)}`,
            );
          }
          const extracted = this.extractTextFromChunk(dataPayload);
          if (!extracted) continue;
          textBuffer += extracted;
          if (cfg.debug) {
            this.logger.debug(`extracted: ${extracted.slice(0, 300)}`);
          }
          for (const pin of this.harvestPins(textBuffer)) {
            const key = `${pin.name}|${pin.sourceTimestampSec ?? ''}`;
            if (emitted.has(key)) continue;
            emitted.add(key);
            yield pin;
          }
        }
      }
    } finally {
      reader.releaseLock();
    }

    this.logger.log(
      `Vertex stream complete chunks=${totalChunks} bufferLen=${textBuffer.length} emitted=${emitted.size}`,
    );
    if (emitted.size === 0 && textBuffer.length > 0) {
      this.logger.warn(
        `Vertex returned text but parser extracted 0 pins. First 800 chars: ${textBuffer.slice(0, 800)}`,
      );
    }

    // Final pass for any trailing pins.
    for (const pin of this.harvestPins(textBuffer)) {
      const key = `${pin.name}|${pin.sourceTimestampSec ?? ''}`;
      if (emitted.has(key)) continue;
      emitted.add(key);
      yield pin;
    }
  }

  // ── Google Cloud Storage ────────────────────────────────────────────────

  private async uploadToGCS(
    bucketName: string,
    bytes: Buffer,
    contentType: string,
    signal: AbortSignal,
  ): Promise<GCSResource> {
    if (signal.aborted) {
      throw new BadGatewayException('Cancelled before GCS upload');
    }
    const ext = this.extensionForContentType(contentType);
    const objectKey = `pin-extractions/${randomUUID()}${ext}`;
    const storage = this.storageClient();
    const file = storage.bucket(bucketName).file(objectKey);
    try {
      await file.save(bytes, {
        contentType,
        resumable: false,
      });
    } catch (err) {
      throw new BadGatewayException(
        `GCS upload to gs://${bucketName}/${objectKey} failed: ${(err as Error).message}`,
      );
    }
    return {
      objectKey,
      gcsUri: `gs://${bucketName}/${objectKey}`,
    };
  }

  private async deleteFromGCS(
    bucketName: string,
    objectKey: string,
  ): Promise<void> {
    const storage = this.storageClient();
    await storage
      .bucket(bucketName)
      .file(objectKey)
      .delete({ ignoreNotFound: true });
  }

  private extensionForContentType(contentType: string): string {
    const ct = contentType.toLowerCase();
    if (ct.includes('mp4')) return '.mp4';
    if (ct.includes('quicktime') || ct.includes('mov')) return '.mov';
    if (ct.includes('webm')) return '.webm';
    if (ct.includes('matroska') || ct.includes('mkv')) return '.mkv';
    if (ct.includes('jpeg') || ct.includes('jpg')) return '.jpg';
    if (ct.includes('png')) return '.png';
    if (ct.includes('webp')) return '.webp';
    if (ct.includes('heic')) return '.heic';
    if (ct.includes('heif')) return '.heif';
    return '';
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  // Bucket-free config for generateContent (image/text) calls.
  private requireGenConfig(): VertexGenConfig {
    const projectId = (
      this.config.get<string>('GOOGLE_CLOUD_PROJECT') ?? ''
    ).trim();
    // Default `global` — Gemini 2.5 is only served from the global endpoint.
    const location = (
      this.config.get<string>('GOOGLE_CLOUD_LOCATION') ?? 'global'
    ).trim();
    const modelId = (
      this.config.get<string>('GEMINI_MODEL_ID') ?? 'gemini-2.5-flash'
    ).trim();
    const debug = this.config.get<string>('GEMINI_DEBUG') === 'true';

    if (!projectId) {
      throw new BadGatewayException(
        'Vertex AI is not configured. Set GOOGLE_CLOUD_PROJECT in the server env.',
      );
    }
    return { projectId, location, modelId, debug };
  }

  // Full config including the GCS staging bucket — only the video
  // (analyzeStream) path needs the bucket.
  private requireConfig(): VertexConfig {
    const gen = this.requireGenConfig();
    const bucket = (this.config.get<string>('GCS_GEMINI_BUCKET') ?? '').trim();
    if (!bucket) {
      throw new BadGatewayException(
        'Vertex AI staging bucket is not configured. Set GCS_GEMINI_BUCKET in the server env.',
      );
    }
    return { ...gen, bucket };
  }

  // Build the Vertex AI REST URL. The `global` vs regional host rule below
  // is load-bearing: Gemini 2.5 models are served ONLY from the `global`
  // location on Vertex AI — regional hosts (e.g. asia-southeast1-aiplatform
  // ...) return NOT_FOUND for them. The global endpoint also has a larger,
  // load-balanced quota pool, which is exactly what fixes the 503s. For
  // `global`, the host has no region prefix. We still allow a real region in
  // case a future older model needs a regional endpoint.
  private vertexUrl(
    cfg: VertexGenConfig,
    method: 'streamGenerateContent' | 'generateContent',
  ): string {
    const host =
      cfg.location === 'global'
        ? 'aiplatform.googleapis.com'
        : `${cfg.location}-aiplatform.googleapis.com`;
    const url = `https://${host}/v1/projects/${cfg.projectId}/locations/${cfg.location}/publishers/google/models/${cfg.modelId}:${method}`;
    return method === 'streamGenerateContent' ? `${url}?alt=sse` : url;
  }

  // Non-streaming Vertex `:generateContent` call returning the concatenated
  // model text. Used by the image→JSON and text generators below. The caller
  // owns the timeout via `signal` (we just compose-and-forward the abort).
  private async generateContentText(
    body: object,
    signal: AbortSignal,
    modelId?: string,
  ): Promise<string> {
    const baseCfg = this.requireGenConfig();
    const cfg = modelId ? { ...baseCfg, modelId } : baseCfg;
    const composed = new AbortController();
    const onAbort = () => composed.abort();
    signal.addEventListener('abort', onAbort, { once: true });
    const url = this.vertexUrl(cfg, 'generateContent');

    let response: Response;
    try {
      const token = await this.accessToken();
      response = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
        signal: composed.signal,
      });
    } finally {
      signal.removeEventListener('abort', onAbort);
    }

    if (!response.ok) {
      const errBody = await response.text().catch(() => '');
      this.logger.error(
        `Vertex generateContent ${response.status}: ${errBody.slice(0, 2000)}`,
      );
      throw new GeminiRequestError(response.status, errBody.slice(0, 500));
    }

    const data: unknown = await response.json();
    const text = this.extractTextFromChunk(JSON.stringify(data));
    if (!text) {
      throw new BadGatewayException('Vertex returned no text');
    }
    return text;
  }

  // Image → strict-JSON. `responseSchema` is a Gemini response schema
  // (UPPERCASE types). Throws UnprocessableEntityException if the model
  // returns text that is not valid JSON.
  async generateJson<T>(opts: {
    imageBytes: Buffer;
    mimeType: string;
    prompt: string;
    responseSchema: object;
    signal: AbortSignal;
  }): Promise<T> {
    const text = await this.generateContentText(
      {
        contents: [
          {
            role: 'user',
            parts: [
              {
                inlineData: {
                  mimeType: opts.mimeType,
                  data: opts.imageBytes.toString('base64'),
                },
              },
              { text: opts.prompt },
            ],
          },
        ],
        generationConfig: {
          response_mime_type: 'application/json',
          response_schema: opts.responseSchema,
          temperature: 0,
        },
        safetySettings: SAFETY_SETTINGS,
      },
      opts.signal,
    );

    try {
      return JSON.parse(text) as T;
    } catch {
      throw new UnprocessableEntityException(
        'Could not extract items from receipt',
      );
    }
  }

  // Several images + one prompt → strict-JSON. Used to review a whole set of
  // candidate photos in a single call (cheaper and more consistent than one
  // call per image, because the model can compare them against each other).
  // Images are sent in order; the prompt refers to them by index.
  async generateJsonFromImages<T>(opts: {
    images: { buffer: Buffer; mimeType: string }[];
    prompt: string;
    responseSchema: object;
    signal: AbortSignal;
    modelId?: string;
  }): Promise<T> {
    const text = await this.generateContentText(
      {
        contents: [
          {
            role: 'user',
            parts: [
              ...opts.images.map((img) => ({
                inlineData: {
                  mimeType: img.mimeType,
                  data: img.buffer.toString('base64'),
                },
              })),
              { text: opts.prompt },
            ],
          },
        ],
        generationConfig: {
          response_mime_type: 'application/json',
          response_schema: opts.responseSchema,
          temperature: 0,
        },
        safetySettings: SAFETY_SETTINGS,
      },
      opts.signal,
      opts.modelId,
    );

    try {
      return JSON.parse(text) as T;
    } catch {
      throw new UnprocessableEntityException(
        'Gemini did not return valid JSON',
      );
    }
  }

  // Text → strict-JSON. Same controlled-generation path as `generateJson` but
  // with a text-only prompt (no inlineData). `responseSchema` is a Gemini
  // response schema (UPPERCASE types). `temperature` defaults to 0 but callers
  // generating creative copy can raise it. `thinkingBudget: 0` disables the
  // 2.5-flash thinking phase (lower latency + more deterministic) for
  // mechanical tasks; omit it to keep the model's default thinking behaviour.
  // `modelId` overrides GEMINI_MODEL_ID for callers that need a stronger
  // model than the configured default (e.g. trip-generator). Throws
  // UnprocessableEntityException if the model returns text that is not
  // valid JSON.
  async generateJsonFromText<T>(opts: {
    prompt: string;
    responseSchema: object;
    signal: AbortSignal;
    temperature?: number;
    thinkingBudget?: number;
    modelId?: string;
    maxOutputTokens?: number;
  }): Promise<T> {
    const text = await this.generateContentText(
      {
        contents: [{ role: 'user', parts: [{ text: opts.prompt }] }],
        generationConfig: {
          response_mime_type: 'application/json',
          response_schema: opts.responseSchema,
          temperature: opts.temperature ?? 0,
          ...(opts.maxOutputTokens !== undefined
            ? { maxOutputTokens: opts.maxOutputTokens }
            : {}),
          ...(opts.thinkingBudget !== undefined
            ? { thinkingConfig: { thinkingBudget: opts.thinkingBudget } }
            : {}),
        },
        safetySettings: SAFETY_SETTINGS,
      },
      opts.signal,
      opts.modelId,
    );

    try {
      return JSON.parse(text) as T;
    } catch {
      throw new UnprocessableEntityException(
        'Gemini did not return valid JSON',
      );
    }
  }

  // Plain text → text. Used for AI copy generation (board descriptions).
  async generateText(opts: {
    prompt: string;
    signal: AbortSignal;
  }): Promise<string> {
    return this.generateContentText(
      {
        contents: [{ role: 'user', parts: [{ text: opts.prompt }] }],
        generationConfig: { temperature: 0 },
        safetySettings: SAFETY_SETTINGS,
      },
      opts.signal,
    );
  }

  private getAuth(): GoogleAuth {
    if (!this.auth) {
      // VERTEX_SA_KEY_FILE points at the Vertex/Gemini SA. Empty falls
      // through to ADC for local dev (gcloud auth application-default login).
      const keyFile =
        this.config.get<string>('VERTEX_SA_KEY_FILE') || undefined;
      this.auth = new GoogleAuth({
        scopes: ['https://www.googleapis.com/auth/cloud-platform'],
        keyFile,
      });
    }
    return this.auth;
  }

  private storageClient(): Storage {
    if (!this.storage) {
      const keyFilename =
        this.config.get<string>('VERTEX_SA_KEY_FILE') || undefined;
      this.storage = new Storage({ keyFilename });
    }
    return this.storage;
  }

  private async accessToken(): Promise<string> {
    const token = await this.getAuth().getAccessToken();
    if (!token) {
      throw new BadGatewayException(
        'Failed to obtain a Google access token. Check VERTEX_SA_KEY_FILE / ADC.',
      );
    }
    return token;
  }

  // Pull text out of a Gemini SSE data payload. Each payload is a
  // GenerateContentResponse with shape:
  //   { candidates: [ { content: { parts: [ { text: "..." }, ... ] } } ],
  //     ...optional finishReason etc }
  // Trailing chunks may carry finishReason and no parts — those should
  // contribute empty text, not throw.
  extractTextFromChunk(dataJson: string): string {
    let parsed: unknown;
    try {
      parsed = JSON.parse(dataJson);
    } catch {
      return '';
    }
    const candidates = (parsed as { candidates?: unknown }).candidates;
    if (!Array.isArray(candidates)) return '';
    let out = '';
    for (const cand of candidates) {
      const parts = (cand as { content?: { parts?: unknown } }).content?.parts;
      if (!Array.isArray(parts)) continue;
      for (const part of parts) {
        const text = (part as { text?: unknown }).text;
        if (typeof text === 'string') out += text;
      }
    }
    return out;
  }

  // Scan accumulated text for complete `{ ... }` JSON objects that look like
  // a location pin (have a "name" field). Returns parsed pins; duplicates are
  // filtered by the caller.
  harvestPins(text: string): ExtractedPin[] {
    const pins: ExtractedPin[] = [];
    let depth = 0;
    let inString = false;
    let escape = false;
    let startIdx = -1;

    for (let i = 0; i < text.length; i++) {
      const ch = text[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (ch === '\\') {
        escape = true;
        continue;
      }
      if (ch === '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch === '{') {
        if (depth === 0) startIdx = i;
        depth++;
      } else if (ch === '}') {
        depth--;
        if (depth === 0 && startIdx !== -1) {
          const slice = text.slice(startIdx, i + 1);
          startIdx = -1;
          try {
            const obj = JSON.parse(slice);
            if (this.isPinShape(obj)) {
              pins.push(this.normalizePin(obj));
            } else if (Array.isArray(obj?.locations)) {
              for (const loc of obj.locations) {
                if (this.isPinShape(loc)) pins.push(this.normalizePin(loc));
              }
            }
          } catch {
            // Not a complete or valid object; skip.
          }
        }
      }
    }
    return pins;
  }

  private isPinShape(obj: unknown): obj is { name: string } {
    return (
      typeof obj === 'object' &&
      obj !== null &&
      typeof (obj as { name?: unknown }).name === 'string' &&
      (obj as { name: string }).name.length > 0
    );
  }

  private normalizePin(raw: Record<string, unknown>): ExtractedPin {
    const num = (v: unknown): number | undefined => {
      if (typeof v === 'number' && Number.isFinite(v)) return v;
      if (typeof v === 'string') {
        const n = Number(v);
        if (Number.isFinite(n)) return n;
      }
      return undefined;
    };
    const str = (v: unknown): string | undefined => {
      if (typeof v === 'string' && v.trim().length > 0) return v.trim();
      return undefined;
    };
    const city = str(raw.city);
    const country = str(raw.country);
    let address = str(raw.address);
    if (!address) {
      if (city && country) address = `${city}, ${country}`;
      else if (city) address = city;
      else if (country) address = country;
    }
    return {
      name: (raw.name as string).trim(),
      address,
      city,
      country,
      category: str(raw.category),
      latitude: num(raw.latitude),
      longitude: num(raw.longitude),
      notes: str(raw.notes),
      sourceTimestampSec: num(raw.sourceTimestampSec),
      dayNumber: (() => {
        const d = num(raw.dayNumber);
        if (d === undefined) return undefined;
        const rounded = Math.round(d);
        return rounded >= 1 ? rounded : undefined;
      })(),
      timeOfDayText: (() => {
        const t = str(raw.timeOfDayText)?.slice(0, 64);
        if (!t) return undefined;
        // Range-shaped values ("7:00-17:00", "9am - 5pm") are opening hours
        // the model quoted off a sign, not a visit time — drop them.
        const time = /\d{1,2}(:\d{2})?\s*(am|pm|h)?/i.source;
        if (new RegExp(`${time}\\s*[-–—~]\\s*${time}`, 'i').test(t)) {
          return undefined;
        }
        return t;
      })(),
    };
  }
}
