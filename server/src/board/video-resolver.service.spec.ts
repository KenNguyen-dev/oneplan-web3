import { ConfigService } from '@nestjs/config';
import {
  VideoResolverError,
  VideoResolverService,
} from './video-resolver.service';

describe('VideoResolverService', () => {
  let service: VideoResolverService;

  beforeEach(() => {
    const config = {
      get: jest.fn().mockReturnValue('yt-dlp'),
    } as unknown as ConfigService;
    service = new VideoResolverService(config);
    // Don't actually hit the network for short-link resolution.
    jest
      .spyOn(
        service as unknown as {
          resolveRedirect: (u: string) => Promise<string>;
        },
        'resolveRedirect',
      )
      .mockImplementation(async (u: string) => u);
  });

  describe('canonicalizeSourceUrl', () => {
    it('strips Instagram tracking params and normalizes /reels/ → /reel/', async () => {
      const a = await service.canonicalizeSourceUrl(
        'https://www.instagram.com/reels/CxYzAbCdEfG/?igsh=ABC&_t=123',
      );
      const b = await service.canonicalizeSourceUrl(
        'https://instagram.com/p/CxYzAbCdEfG/',
      );
      const c = await service.canonicalizeSourceUrl(
        'https://m.instagram.com/reel/CxYzAbCdEfG/?si=xyz',
      );
      expect(a).toBe('https://www.instagram.com/reel/CxYzAbCdEfG');
      expect(b).toBe('https://www.instagram.com/reel/CxYzAbCdEfG');
      expect(c).toBe('https://www.instagram.com/reel/CxYzAbCdEfG');
    });

    it('normalizes m.tiktok.com to www.tiktok.com and strips trailing slash', async () => {
      const out = await service.canonicalizeSourceUrl(
        'https://m.tiktok.com/@user/video/7123456789012345678/?_t=abc',
      );
      expect(out).toBe(
        'https://www.tiktok.com/@user/video/7123456789012345678',
      );
    });

    it('rejects unsupported hosts', async () => {
      await expect(
        service.canonicalizeSourceUrl('https://youtube.com/watch?v=abc'),
      ).rejects.toBeInstanceOf(VideoResolverError);
      await expect(
        service.canonicalizeSourceUrl('https://example.com/foo'),
      ).rejects.toBeInstanceOf(VideoResolverError);
    });

    it('rejects unparseable URLs', async () => {
      await expect(service.canonicalizeSourceUrl('not a url')).rejects.toThrow(
        VideoResolverError,
      );
    });
  });

  describe('isTikTokPhotoUrl', () => {
    it('detects TikTok photo posts', () => {
      expect(
        service.isTikTokPhotoUrl(
          'https://www.tiktok.com/@di.cung.xink/photo/7531619881926659336',
        ),
      ).toBe(true);
    });

    it('is false for TikTok videos, Instagram, unresolved short links, and junk', () => {
      expect(
        service.isTikTokPhotoUrl('https://www.tiktok.com/@user/video/123'),
      ).toBe(false);
      expect(
        service.isTikTokPhotoUrl('https://www.instagram.com/reel/ABC'),
      ).toBe(false);
      // Unresolved short link keeps its short form — no /photo/ path.
      expect(service.isTikTokPhotoUrl('https://vm.tiktok.com/ZS123abc')).toBe(
        false,
      );
      expect(service.isTikTokPhotoUrl('not a url')).toBe(false);
    });
  });

  describe('downloadImages retries', () => {
    type GallerySpawnable = {
      spawnGalleryDl: (url: string, signal?: AbortSignal) => Promise<unknown>;
      delay: (ms: number, signal?: AbortSignal) => Promise<void>;
    };
    const url = 'https://www.tiktok.com/@user/photo/7531619881926659336';

    beforeEach(() => {
      jest
        .spyOn(service as unknown as GallerySpawnable, 'delay')
        .mockResolvedValue(undefined);
    });

    it('retries transient 403s then succeeds', async () => {
      const result = {
        images: [{ tmpPath: '/tmp/pin-x-0.jpeg', contentType: 'image/jpeg' }],
        title: 'trip',
      };
      const spawn = jest
        .spyOn(service as unknown as GallerySpawnable, 'spawnGalleryDl')
        .mockRejectedValueOnce(new VideoResolverError('unknown', '403'))
        .mockResolvedValueOnce(result);

      await expect(service.downloadImages(url)).resolves.toEqual(result);
      expect(spawn).toHaveBeenCalledTimes(2);
    });

    it('does not retry unsupported URLs', async () => {
      const spawn = jest
        .spyOn(service as unknown as GallerySpawnable, 'spawnGalleryDl')
        .mockRejectedValue(
          new VideoResolverError('unsupported_url', 'unsupported'),
        );

      await expect(service.downloadImages(url)).rejects.toMatchObject({
        code: 'unsupported_url',
      });
      expect(spawn).toHaveBeenCalledTimes(1);
    });
  });

  describe('spawnGalleryDl parsing', () => {
    type GalleryInternals = {
      spawnGalleryDl: (url: string, signal?: AbortSignal) => Promise<unknown>;
      runGalleryDlJson: (
        url: string,
        signal?: AbortSignal,
      ) => Promise<{ stdout: string; stderr: string }>;
      fetchImage: (
        url: string,
        index: number,
        signal?: AbortSignal,
      ) => Promise<{ tmpPath: string; contentType: string; sizeBytes: number }>;
      cleanup: (p: string) => Promise<void>;
    };
    const url = 'https://www.tiktok.com/@user/photo/7531619881926659336';

    it('extracts meta + image URLs from the -j tuple output and skips unknown codes', async () => {
      jest
        .spyOn(service as unknown as GalleryInternals, 'runGalleryDlJson')
        .mockResolvedValue({
          stdout: JSON.stringify([
            [
              2,
              { desc: 'Đà Nẵng food tour', author: { nickname: 'Ello XinK' } },
            ],
            [3, 'https://cdn.tiktok.com/img0.jpeg', { extension: 'jpeg' }],
            [3, 'https://cdn.tiktok.com/img1.webp', { extension: 'webp' }],
            // Photo posts also list their background audio — must be skipped.
            [3, 'https://cdn.tiktok.com/music.mp3', { extension: 'mp3' }],
            [99, 'future-message-code'],
            'garbage-entry',
          ]),
          stderr: '',
        });
      const fetchImage = jest
        .spyOn(service as unknown as GalleryInternals, 'fetchImage')
        .mockImplementation((imgUrl: string, index: number) =>
          Promise.resolve({
            tmpPath: `/tmp/pin-t-${index}.jpeg`,
            contentType: 'image/jpeg',
            sizeBytes: 1000,
          }),
        );

      const result = (await (
        service as unknown as GalleryInternals
      ).spawnGalleryDl(url)) as {
        images: unknown[];
        title?: string;
        description?: string;
        uploader?: string;
        thumbnail?: string;
      };

      expect(result.images).toHaveLength(2);
      expect(result.description).toBe('Đà Nẵng food tour');
      expect(result.title).toBe('Đà Nẵng food tour');
      expect(result.uploader).toBe('Ello XinK');
      expect(result.thumbnail).toBe('https://cdn.tiktok.com/img0.jpeg');
      expect(fetchImage).toHaveBeenCalledTimes(2);
    });

    it('cleans up already-fetched tmp files when a later image fetch fails', async () => {
      jest
        .spyOn(service as unknown as GalleryInternals, 'runGalleryDlJson')
        .mockResolvedValue({
          stdout: JSON.stringify([
            [3, 'https://cdn.tiktok.com/img0.jpeg', {}],
            [3, 'https://cdn.tiktok.com/img1.jpeg', {}],
          ]),
          stderr: '',
        });
      jest
        .spyOn(service as unknown as GalleryInternals, 'fetchImage')
        .mockResolvedValueOnce({
          tmpPath: '/tmp/pin-t-0.jpeg',
          contentType: 'image/jpeg',
          sizeBytes: 1000,
        })
        .mockRejectedValueOnce(new VideoResolverError('unknown', 'HTTP 403'));
      const cleanup = jest
        .spyOn(service as unknown as GalleryInternals, 'cleanup')
        .mockResolvedValue(undefined);

      await expect(
        (service as unknown as GalleryInternals).spawnGalleryDl(url),
      ).rejects.toMatchObject({ code: 'unknown' });
      expect(cleanup).toHaveBeenCalledWith('/tmp/pin-t-0.jpeg');
    });

    it('fails with video_unavailable when the post genuinely has no images', async () => {
      jest
        .spyOn(service as unknown as GalleryInternals, 'runGalleryDlJson')
        .mockResolvedValue({
          stdout: JSON.stringify([[2, { desc: 'no images' }]]),
          stderr: '',
        });

      await expect(
        (service as unknown as GalleryInternals).spawnGalleryDl(url),
      ).rejects.toMatchObject({ code: 'video_unavailable' });
    });

    it('maps an exit-0 empty result with a stderr [error] to a retryable unknown', async () => {
      // gallery-dl exits 0 on TikTok's intermittent 403 JS-challenge
      // rejection — stdout is `[]` and the failure only appears on stderr.
      jest
        .spyOn(service as unknown as GalleryInternals, 'runGalleryDlJson')
        .mockResolvedValue({
          stdout: '[]',
          stderr:
            "[tiktok][error] https://…: Failed to extract post (HttpError: '403 Forbidden' for '…')",
        });

      await expect(
        (service as unknown as GalleryInternals).spawnGalleryDl(url),
      ).rejects.toMatchObject({ code: 'unknown' });
    });
  });

  describe('gallery-dl error mapping', () => {
    type Mappable = { mapGalleryDlStderrToCode: (s: string) => string };
    const cases: Array<[string, string]> = [
      ['error: unsupported URL', 'unsupported_url'],
      ['No suitable extractor found', 'unsupported_url'],
      ['login required', 'login_required'],
      ["HttpError: '404 Not Found'", 'video_unavailable'],
      ["Failed to extract post (HttpError: '403 Forbidden')", 'unknown'],
    ];
    it.each(cases)('maps %j → %s', (stderr, expected) => {
      const code = (service as unknown as Mappable).mapGalleryDlStderrToCode(
        stderr,
      );
      expect(code).toBe(expected);
    });
  });

  describe('image content types', () => {
    type Typeable = { contentTypeForExt: (ext: string) => string };
    it.each([
      ['jpg', 'image/jpeg'],
      ['jpeg', 'image/jpeg'],
      ['png', 'image/png'],
      ['webp', 'image/webp'],
      ['heic', 'image/heic'],
      ['heif', 'image/heif'],
      ['mp4', 'video/mp4'],
    ])('maps %s → %s', (ext, expected) => {
      expect((service as unknown as Typeable).contentTypeForExt(ext)).toBe(
        expected,
      );
    });
  });

  describe('download retries', () => {
    type Spawnable = {
      spawnDownload: (url: string, signal?: AbortSignal) => Promise<unknown>;
      delay: (ms: number, signal?: AbortSignal) => Promise<void>;
    };
    const url = 'https://www.tiktok.com/@user/video/7123456789012345678';

    beforeEach(() => {
      // Don't actually wait between retries.
      jest
        .spyOn(service as unknown as Spawnable, 'delay')
        .mockResolvedValue(undefined);
    });

    it('retries transient (unknown) failures then succeeds', async () => {
      const spawn = jest
        .spyOn(service as unknown as Spawnable, 'spawnDownload')
        .mockRejectedValueOnce(new VideoResolverError('unknown', 'rehydration'))
        .mockRejectedValueOnce(new VideoResolverError('unknown', 'rehydration'))
        .mockResolvedValueOnce({ tmpPath: '/tmp/x.mp4' });

      const result = await service.download(url);
      expect(result).toEqual({ tmpPath: '/tmp/x.mp4' });
      expect(spawn).toHaveBeenCalledTimes(3);
    });

    it('gives up after max attempts on persistent transient failures', async () => {
      const spawn = jest
        .spyOn(service as unknown as Spawnable, 'spawnDownload')
        .mockRejectedValue(new VideoResolverError('unknown', 'rehydration'));

      await expect(service.download(url)).rejects.toMatchObject({
        code: 'unknown',
      });
      expect(spawn).toHaveBeenCalledTimes(3);
    });

    it('does not retry permanent failures', async () => {
      const spawn = jest
        .spyOn(service as unknown as Spawnable, 'spawnDownload')
        .mockRejectedValue(new VideoResolverError('private_video', 'private'));

      await expect(service.download(url)).rejects.toMatchObject({
        code: 'private_video',
      });
      expect(spawn).toHaveBeenCalledTimes(1);
    });

    it('does not retry once the signal is aborted', async () => {
      const controller = new AbortController();
      const spawn = jest
        .spyOn(service as unknown as Spawnable, 'spawnDownload')
        .mockImplementation(async () => {
          controller.abort();
          throw new VideoResolverError('unknown', 'rehydration');
        });

      await expect(
        service.download(url, controller.signal),
      ).rejects.toMatchObject({ code: 'unknown' });
      expect(spawn).toHaveBeenCalledTimes(1);
    });
  });

  describe('error mapping', () => {
    type Mappable = { mapStderrToCode: (s: string) => string };
    const cases: Array<[string, string]> = [
      ['ERROR: Unsupported URL: foo', 'unsupported_url'],
      ['ERROR: Login required to view this post', 'login_required'],
      ['ERROR: cookies are required', 'login_required'],
      ['ERROR: This post is private', 'private_video'],
      ['ERROR: Private video', 'private_video'],
      ['ERROR: Video unavailable', 'video_unavailable'],
      ['HTTP Error 404: Not Found', 'video_unavailable'],
      ['ERROR: File is larger than max-filesize', 'too_large'],
      ['ERROR: something totally unexpected', 'unknown'],
    ];
    it.each(cases)('maps %j → %s', (stderr, expected) => {
      const code = (service as unknown as Mappable).mapStderrToCode(stderr);
      expect(code).toBe(expected);
    });
  });
});
