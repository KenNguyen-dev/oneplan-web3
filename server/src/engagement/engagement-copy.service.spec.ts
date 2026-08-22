import { EngagementLocale, EngagementTrigger } from '@prisma/client';
import { GeminiService } from '../common/gemini/gemini.service';
import { EngagementCopyService } from './engagement-copy.service';
import { TriggerCandidate } from './engagement.types';

function candidate(coarseHint: string): TriggerCandidate {
  return {
    trigger: EngagementTrigger.DORMANT,
    dedupeKey: 'DORMANT:user:1:2026-W25',
    hints: { coarseHint },
    deepLink: { type: 'engagement_dormant' },
  };
}

describe('EngagementCopyService', () => {
  let gemini: { generateJsonFromText: jest.Mock };
  let service: EngagementCopyService;

  beforeEach(() => {
    gemini = { generateJsonFromText: jest.fn() };
    service = new EngagementCopyService(gemini as unknown as GeminiService);
  });

  it('falls back to a static template when the LLM throws', async () => {
    gemini.generateJsonFromText.mockRejectedValue(new Error('vertex down'));
    const copy = await service.generate(candidate('a'), EngagementLocale.EN);
    expect(copy.usedLlm).toBe(false);
    expect(copy.title.length).toBeGreaterThan(0);
    expect(copy.body.length).toBeGreaterThan(0);
  });

  it('uses the LLM result when valid and truncates over-long fields', async () => {
    gemini.generateJsonFromText.mockResolvedValue({
      title: 'x'.repeat(80),
      body: 'y'.repeat(200),
    });
    const copy = await service.generate(candidate('b'), EngagementLocale.EN);
    expect(copy.usedLlm).toBe(true);
    expect(copy.title.length).toBe(40);
    expect(copy.body.length).toBe(110);
  });

  it('falls back when the LLM returns empty fields', async () => {
    gemini.generateJsonFromText.mockResolvedValue({ title: '', body: '' });
    const copy = await service.generate(candidate('c'), EngagementLocale.VN);
    expect(copy.usedLlm).toBe(false);
  });

  it('serves a cohort from cache without re-calling the LLM', async () => {
    gemini.generateJsonFromText.mockResolvedValue({ title: 'Hi', body: 'Yo' });
    await service.generate(candidate('shared'), EngagementLocale.EN);
    await service.generate(candidate('shared'), EngagementLocale.EN);
    expect(gemini.generateJsonFromText).toHaveBeenCalledTimes(1);
  });
});
