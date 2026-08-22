import { ConfigService } from '@nestjs/config';
import { GeminiService } from './gemini.service';

describe('GeminiService', () => {
  let service: GeminiService;

  beforeEach(() => {
    const config = {
      get: jest.fn().mockImplementation((key: string) => {
        if (key === 'GOOGLE_CLOUD_PROJECT') return 'test-project';
        if (key === 'GOOGLE_CLOUD_LOCATION') return 'global';
        if (key === 'GCS_GEMINI_BUCKET') return 'test-bucket';
        if (key === 'GEMINI_MODEL_ID') return 'gemini-2.5-flash';
        if (key === 'GEMINI_DEBUG') return 'false';
        return undefined;
      }),
    } as unknown as ConfigService;
    service = new GeminiService(config);
  });

  describe('extractTextFromChunk', () => {
    it('reads candidates[*].content.parts[*].text and concatenates', () => {
      const payload = JSON.stringify({
        candidates: [
          {
            content: {
              parts: [{ text: 'hello ' }, { text: 'world' }],
            },
          },
        ],
      });
      expect(service.extractTextFromChunk(payload)).toBe('hello world');
    });

    it('returns empty string for a finishReason-only chunk with no parts', () => {
      const payload = JSON.stringify({
        candidates: [{ finishReason: 'STOP' }],
      });
      expect(service.extractTextFromChunk(payload)).toBe('');
    });

    it('returns empty string for malformed JSON without throwing', () => {
      expect(() => service.extractTextFromChunk('not-json')).not.toThrow();
      expect(service.extractTextFromChunk('not-json')).toBe('');
    });

    it('handles multiple candidates by concatenating their parts', () => {
      const payload = JSON.stringify({
        candidates: [
          { content: { parts: [{ text: 'a' }] } },
          { content: { parts: [{ text: 'b' }] } },
        ],
      });
      expect(service.extractTextFromChunk(payload)).toBe('ab');
    });
  });

  describe('harvestPins', () => {
    it('extracts pin objects from accumulated text', () => {
      const text = `{
        "locations": [
          { "name": "Bunkerland", "city": "Da Lat", "country": "Vietnam", "notes": "test" },
          { "name": "Erim 2", "city": "Da Lat" }
        ]
      }`;
      const pins = service.harvestPins(text);
      expect(pins).toHaveLength(2);
      expect(pins[0].name).toBe('Bunkerland');
      expect(pins[0].address).toBe('Da Lat, Vietnam');
      expect(pins[1].name).toBe('Erim 2');
      expect(pins[1].address).toBe('Da Lat');
    });

    it('composes address from city alone when country missing', () => {
      const pins = service.harvestPins(
        '{ "name": "Café Apollo", "city": "Hanoi" }',
      );
      expect(pins[0].address).toBe('Hanoi');
    });

    it('skips objects without a name', () => {
      const pins = service.harvestPins(
        '{ "city": "Tokyo" } { "name": "Real" }',
      );
      expect(pins).toHaveLength(1);
      expect(pins[0].name).toBe('Real');
    });

    it('ignores malformed JSON without crashing', () => {
      expect(() =>
        service.harvestPins('{ "name": "X" } not-json { broken'),
      ).not.toThrow();
    });
  });

  describe('config errors', () => {
    it('throws BadGatewayException when GOOGLE_CLOUD_PROJECT is missing', async () => {
      const cfg = {
        get: jest.fn().mockReturnValue(''),
      } as unknown as ConfigService;
      const s = new GeminiService(cfg);
      const gen = s.analyzeStream(
        '/tmp/anything.mp4',
        'video/mp4',
        new AbortController().signal,
      );
      await expect(gen.next()).rejects.toThrow(/Vertex AI is not configured/);
    });

    it('throws BadGatewayException when GCS_GEMINI_BUCKET is missing (video path only)', async () => {
      const cfg = {
        get: jest.fn().mockImplementation((key: string) => {
          if (key === 'GOOGLE_CLOUD_PROJECT') return 'test-project';
          if (key === 'GOOGLE_CLOUD_LOCATION') return 'global';
          return '';
        }),
      } as unknown as ConfigService;
      const s = new GeminiService(cfg);
      const gen = s.analyzeStream(
        '/tmp/anything.mp4',
        'video/mp4',
        new AbortController().signal,
      );
      await expect(gen.next()).rejects.toThrow(
        /staging bucket is not configured/,
      );
    });
  });

  describe('generateJson / generateText (bucket-free generateContent path)', () => {
    const originalFetch = global.fetch;

    // GCS_GEMINI_BUCKET intentionally unset — proves requireGenConfig does
    // NOT require the staging bucket for image/text generation.
    const makeService = () => {
      const cfg = {
        get: jest.fn().mockImplementation((key: string) => {
          if (key === 'GOOGLE_CLOUD_PROJECT') return 'test-project';
          if (key === 'GOOGLE_CLOUD_LOCATION') return 'global';
          if (key === 'GEMINI_MODEL_ID') return 'gemini-2.5-flash';
          return '';
        }),
      } as unknown as ConfigService;
      const s = new GeminiService(cfg);
      // Bypass ADC: stub the auth client used by accessToken().
      (s as unknown as { getAuth: () => unknown }).getAuth = () => ({
        getAccessToken: async () => 'test-token',
      });
      return s;
    };

    const geminiResponse = (text: string) => ({
      ok: true,
      status: 200,
      json: async () => ({
        candidates: [{ content: { parts: [{ text }] } }],
      }),
    });

    afterEach(() => {
      global.fetch = originalFetch;
    });

    it('generateJson parses the model JSON and posts to :generateContent (no ?alt=sse, inline image)', async () => {
      const fetchMock = jest
        .fn()
        .mockResolvedValue(
          geminiResponse('{"items":[{"name":"Tea","totalPrice":100}]}'),
        );
      global.fetch = fetchMock as unknown as typeof fetch;

      const s = makeService();
      const result = await s.generateJson<{ items: unknown[] }>({
        imageBytes: Buffer.from('imgbytes'),
        mimeType: 'image/jpeg',
        prompt: 'parse this',
        responseSchema: { type: 'OBJECT' },
        signal: new AbortController().signal,
      });

      expect(result).toEqual({ items: [{ name: 'Tea', totalPrice: 100 }] });
      const [url, init] = fetchMock.mock.calls[0];
      expect(url).toContain(':generateContent');
      expect(url).not.toContain('?alt=sse');
      const body = JSON.parse((init as { body: string }).body);
      expect(body.contents[0].parts[0].inlineData.mimeType).toBe('image/jpeg');
      expect(body.contents[0].parts[0].inlineData.data).toBe(
        Buffer.from('imgbytes').toString('base64'),
      );
      expect(body.generationConfig.response_mime_type).toBe('application/json');
    });

    it('generateJson throws UnprocessableEntityException on non-JSON model text', async () => {
      global.fetch = jest
        .fn()
        .mockResolvedValue(geminiResponse('not json at all')) as never;
      const s = makeService();
      await expect(
        s.generateJson({
          imageBytes: Buffer.from('x'),
          mimeType: 'image/jpeg',
          prompt: 'p',
          responseSchema: {},
          signal: new AbortController().signal,
        }),
      ).rejects.toThrow(/Could not extract items/);
    });

    it('generateJson throws BadGatewayException on a non-OK Vertex response', async () => {
      global.fetch = jest.fn().mockResolvedValue({
        ok: false,
        status: 503,
        text: async () => 'unavailable',
      }) as never;
      const s = makeService();
      await expect(
        s.generateJson({
          imageBytes: Buffer.from('x'),
          mimeType: 'image/jpeg',
          prompt: 'p',
          responseSchema: {},
          signal: new AbortController().signal,
        }),
      ).rejects.toThrow(/Gemini request failed \(503\)/);
    });

    it('generateText returns the concatenated model text', async () => {
      global.fetch = jest
        .fn()
        .mockResolvedValue(geminiResponse('A friendly description.')) as never;
      const s = makeService();
      const text = await s.generateText({
        prompt: 'write copy',
        signal: new AbortController().signal,
      });
      expect(text).toBe('A friendly description.');
    });
  });
});
