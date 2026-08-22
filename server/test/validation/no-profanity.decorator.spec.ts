import { IsOptional, IsString, validateSync } from 'class-validator';
import {
  NoProfanity,
  extractProfaneTerms,
} from '../../src/common/validators/no-profanity.decorator';

class TestProfanityDto {
  @IsOptional()
  @IsString()
  @NoProfanity()
  value?: string | null;
}

describe('NoProfanity decorator', () => {
  it('rejects profane input', () => {
    const dto = new TestProfanityDto();
    dto.value = 'This is shit';

    const errors = validateSync(dto);

    expect(errors).toHaveLength(1);
    const message = Object.values(errors[0].constraints ?? {}).join(' ');
    expect(message).toContain('contains profanity');
    expect(message).toContain('shit');
  });

  it('accepts clean input', () => {
    const dto = new TestProfanityDto();
    dto.value = 'Family-friendly trip plan';

    const errors = validateSync(dto);
    expect(errors).toHaveLength(0);
  });

  it('accepts undefined, null, and empty values', () => {
    const undefinedDto = new TestProfanityDto();

    const nullDto = new TestProfanityDto();
    nullDto.value = null;

    const emptyDto = new TestProfanityDto();
    emptyDto.value = '';

    expect(validateSync(undefinedDto)).toHaveLength(0);
    expect(validateSync(nullDto)).toHaveLength(0);
    expect(validateSync(emptyDto)).toHaveLength(0);
  });

  it('extracts deduplicated matched profane terms', () => {
    const terms = extractProfaneTerms('fuck this SHIT and fuck that');
    expect(terms).toEqual(['fuck', 'shit']);
  });
});
