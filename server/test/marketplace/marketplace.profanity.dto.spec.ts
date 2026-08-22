import { validateSync } from 'class-validator';
import { CreateMarketItemDto } from '../../src/marketplace/dto/create-market-item.dto';
import { CreateMarketplaceListingDto } from '../../src/marketplace/dto/create-marketplace-listing.dto';
import { UpdateMarketItemDto } from '../../src/marketplace/dto/update-market-item.dto';
import { UpdateMarketplaceListingDto } from '../../src/marketplace/dto/update-marketplace-listing.dto';

function getConstraintMessages(
  errors: ReturnType<typeof validateSync>,
): string[] {
  return errors.flatMap((error) => Object.values(error.constraints ?? {}));
}

function createValidListingDto(): CreateMarketplaceListingDto {
  return Object.assign(new CreateMarketplaceListingDto(), {
    name: 'Da Lat weekend',
    price: 100,
    durationDays: 2,
    description: 'A scenic trip',
    tags: ['FRIENDS'],
  });
}

function createValidItemDto(): CreateMarketItemDto {
  return Object.assign(new CreateMarketItemDto(), {
    dayNumber: 1,
    title: 'Breakfast',
    description: 'Tasty local food',
    location: 'Da Lat',
    startTime: '08:30',
    imageUrls: ['https://cdn.example.com/fuck-image.jpg'],
  });
}

describe('Marketplace DTO profanity filtering', () => {
  describe('CreateMarketplaceListingDto', () => {
    it.each(['name', 'description'] as const)(
      'rejects profanity in %s',
      (field) => {
        const dto = createValidListingDto();
        dto[field] = 'This is shit';

        const errors = validateSync(dto);

        expect(errors).toHaveLength(1);
        expect(errors[0].property).toBe(field);
        expect(getConstraintMessages(errors).join(' ')).toContain('shit');
      },
    );

    it('does not apply profanity validation to coverImageUrl', () => {
      const dto = createValidListingDto();
      dto.coverImageUrl = 'https://cdn.example.com/fuck-cover.jpg';

      const errors = validateSync(dto);

      expect(errors).toHaveLength(0);
    });
  });

  describe('UpdateMarketplaceListingDto', () => {
    it.each(['name', 'description'] as const)(
      'rejects profanity in %s',
      (field) => {
        const dto = Object.assign(new UpdateMarketplaceListingDto(), {
          [field]: 'fuck',
        });

        const errors = validateSync(dto);

        expect(errors).toHaveLength(1);
        expect(errors[0].property).toBe(field);
        expect(getConstraintMessages(errors).join(' ')).toContain('fuck');
      },
    );
  });

  describe('CreateMarketItemDto', () => {
    it.each(['title', 'description', 'location'] as const)(
      'rejects profanity in %s',
      (field) => {
        const dto = createValidItemDto();
        dto[field] = 'shit plan';

        const errors = validateSync(dto);

        expect(errors).toHaveLength(1);
        expect(errors[0].property).toBe(field);
        expect(getConstraintMessages(errors).join(' ')).toContain('shit');
      },
    );

    it('does not apply profanity validation to startTime and imageUrls', () => {
      const dto = createValidItemDto();
      dto.startTime = '12:30';
      dto.imageUrls = ['https://cdn.example.com/fuck-photo.jpg'];

      const errors = validateSync(dto);

      expect(errors).toHaveLength(0);
    });
  });

  describe('UpdateMarketItemDto', () => {
    it.each(['title', 'description', 'location'] as const)(
      'rejects profanity in %s',
      (field) => {
        const dto = Object.assign(new UpdateMarketItemDto(), {
          [field]: 'fuck',
        });

        const errors = validateSync(dto);

        expect(errors).toHaveLength(1);
        expect(errors[0].property).toBe(field);
        expect(getConstraintMessages(errors).join(' ')).toContain('fuck');
      },
    );
  });
});
