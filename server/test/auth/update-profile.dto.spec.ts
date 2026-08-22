import { validateSync } from 'class-validator';
import { UpdateProfileDto } from '../../src/auth/dto/update-profile.dto';

describe('UpdateProfileDto', () => {
  it('accepts valid displayName', () => {
    const dto = new UpdateProfileDto();
    dto.displayName = 'Danny';

    const errors = validateSync(dto);
    expect(errors).toHaveLength(0);
  });

  it('rejects empty displayName', () => {
    const dto = new UpdateProfileDto();
    dto.displayName = '';

    const errors = validateSync(dto);
    expect(errors).toHaveLength(1);
  });

  it('rejects displayName longer than 100 chars', () => {
    const dto = new UpdateProfileDto();
    dto.displayName = 'a'.repeat(101);

    const errors = validateSync(dto);
    expect(errors).toHaveLength(1);
  });
});
