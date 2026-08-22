import { PrismaService } from '../../src/prisma/prisma.service';
import { LocationsService } from '../../src/locations/locations.service';

describe('LocationsService', () => {
  let service: LocationsService;
  let prisma: {
    country: { findMany: jest.Mock };
    state: { findMany: jest.Mock };
    city: { findMany: jest.Mock };
    $queryRaw: jest.Mock;
  };

  beforeEach(() => {
    prisma = {
      country: { findMany: jest.fn() },
      state: { findMany: jest.fn() },
      city: { findMany: jest.fn() },
      $queryRaw: jest.fn(),
    };

    service = new LocationsService(prisma as unknown as PrismaService);
  });

  describe('findAllCountries', () => {
    it('returns all countries sorted by name', async () => {
      const countries = [
        {
          id: 1,
          name: 'Australia',
          iso2: 'AU',
          iso3: 'AUS',
          phoneCode: '61',
          capital: 'Canberra',
          currency: 'AUD',
          region: 'Oceania',
          subRegion: 'Australia and New Zealand',
          emoji: '🇦🇺',
        },
        {
          id: 2,
          name: 'Brazil',
          iso2: 'BR',
          iso3: 'BRA',
          phoneCode: '55',
          capital: 'Brasilia',
          currency: 'BRL',
          region: 'Americas',
          subRegion: 'South America',
          emoji: '🇧🇷',
        },
      ];
      prisma.country.findMany.mockResolvedValue(countries);

      const result = await service.findAllCountries();

      expect(result).toEqual(countries);
      expect(prisma.country.findMany).toHaveBeenCalledWith({
        select: {
          id: true,
          name: true,
          iso2: true,
          iso3: true,
          phoneCode: true,
          capital: true,
          currency: true,
          region: true,
          subRegion: true,
          emoji: true,
        },
        orderBy: { name: 'asc' },
      });
    });
  });

  describe('findStatesByCountry', () => {
    it('returns states for a given country', async () => {
      const states = [
        {
          id: 1,
          name: 'California',
          iso2: 'CA',
          type: 'state',
          latitude: '36.778261',
          longitude: '-119.417932',
        },
        {
          id: 2,
          name: 'Texas',
          iso2: 'TX',
          type: 'state',
          latitude: '31.968599',
          longitude: '-99.901810',
        },
      ];
      prisma.state.findMany.mockResolvedValue(states);

      const result = await service.findStatesByCountry(233);

      expect(result).toEqual(states);
      expect(prisma.state.findMany).toHaveBeenCalledWith({
        where: { countryId: 233 },
        select: {
          id: true,
          name: true,
          iso2: true,
          type: true,
          latitude: true,
          longitude: true,
        },
        orderBy: { name: 'asc' },
      });
    });

    it('returns empty array when country has no states', async () => {
      prisma.state.findMany.mockResolvedValue([]);

      const result = await service.findStatesByCountry(999);

      expect(result).toEqual([]);
    });
  });

  describe('findCitiesByState', () => {
    const cities = [
      {
        id: 10,
        name: 'Los Angeles',
        latitude: '34.052234',
        longitude: '-118.243685',
      },
      {
        id: 11,
        name: 'Los Gatos',
        latitude: '37.226611',
        longitude: '-121.974319',
      },
    ];

    it('returns paginated cities with nextCursor when more results exist', async () => {
      const fullPage = Array.from({ length: 50 }, (_, i) => ({
        id: i + 1,
        name: `City ${i}`,
        latitude: '0',
        longitude: '0',
      }));
      prisma.city.findMany.mockResolvedValue(fullPage);

      const result = await service.findCitiesByState(1416);

      expect(result.data).toHaveLength(50);
      expect(result.nextCursor).toBe(50);
    });

    it('returns null nextCursor on last page', async () => {
      prisma.city.findMany.mockResolvedValue(cities);

      const result = await service.findCitiesByState(1416);

      expect(result.data).toEqual(cities);
      expect(result.nextCursor).toBeNull();
    });

    it('applies search filter with case-insensitive contains', async () => {
      prisma.city.findMany.mockResolvedValue(cities);

      await service.findCitiesByState(1416, 'Los');

      expect(prisma.city.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            stateId: 1416,
            name: { contains: 'Los', mode: 'insensitive' },
          },
        }),
      );
    });

    it('applies cursor-based pagination', async () => {
      prisma.city.findMany.mockResolvedValue([]);

      await service.findCitiesByState(1416, undefined, 10, 20);

      expect(prisma.city.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          skip: 1,
          cursor: { id: 10 },
          take: 20,
        }),
      );
    });

    it('does not include cursor params on first page', async () => {
      prisma.city.findMany.mockResolvedValue([]);

      await service.findCitiesByState(1416);

      const call = prisma.city.findMany.mock.calls[0][0];
      expect(call.cursor).toBeUndefined();
      expect(call.skip).toBeUndefined();
    });
  });

  describe('searchLocations', () => {
    const country = {
      id: 241,
      name: 'Vietnam',
      iso2: 'VN',
      iso3: 'VNM',
      phoneCode: '84',
      capital: 'Hanoi',
      currency: 'VND',
      region: 'Asia',
      subRegion: 'South-Eastern Asia',
      emoji: '🇻🇳',
    };

    const state = {
      id: 3794,
      name: 'Lam Dong',
      iso2: '35',
      type: 'province',
      latitude: '11.575279',
      longitude: '108.142866',
    };

    const cityRow = (
      overrides: Partial<{
        cityId: number;
        cityName: string;
        cityLatitude: string;
        cityLongitude: string;
        stateId: number;
        stateName: string;
        stateIso2: string | null;
        stateType: string | null;
        stateLatitude: string | null;
        stateLongitude: string | null;
        countryId: number;
        countryName: string;
        countryIso2: string | null;
        countryIso3: string | null;
        countryPhoneCode: string | null;
        countryCapital: string | null;
        countryCurrency: string | null;
        countryRegion: string | null;
        countrySubRegion: string | null;
        countryEmoji: string | null;
      }> = {},
    ) => ({
      cityId: 130014,
      cityName: 'Đà Nẵng',
      cityLatitude: '16.054407',
      cityLongitude: '108.202167',
      stateId: state.id,
      stateName: state.name,
      stateIso2: state.iso2,
      stateType: state.type,
      stateLatitude: state.latitude,
      stateLongitude: state.longitude,
      countryId: country.id,
      countryName: country.name,
      countryIso2: country.iso2,
      countryIso3: country.iso3,
      countryPhoneCode: country.phoneCode,
      countryCapital: country.capital,
      countryCurrency: country.currency,
      countryRegion: country.region,
      countrySubRegion: country.subRegion,
      countryEmoji: country.emoji,
      ...overrides,
    });

    const stateRow = (
      overrides: Partial<{
        stateId: number;
        stateName: string;
        stateIso2: string | null;
        stateType: string | null;
        stateLatitude: string | null;
        stateLongitude: string | null;
        countryId: number;
        countryName: string;
        countryIso2: string | null;
        countryIso3: string | null;
        countryPhoneCode: string | null;
        countryCapital: string | null;
        countryCurrency: string | null;
        countryRegion: string | null;
        countrySubRegion: string | null;
        countryEmoji: string | null;
      }> = {},
    ) => ({
      stateId: state.id,
      stateName: state.name,
      stateIso2: state.iso2,
      stateType: state.type,
      stateLatitude: state.latitude,
      stateLongitude: state.longitude,
      countryId: country.id,
      countryName: country.name,
      countryIso2: country.iso2,
      countryIso3: country.iso3,
      countryPhoneCode: country.phoneCode,
      countryCapital: country.capital,
      countryCurrency: country.currency,
      countryRegion: country.region,
      countrySubRegion: country.subRegion,
      countryEmoji: country.emoji,
      ...overrides,
    });

    it('returns matching cities with their parent state and country', async () => {
      prisma.$queryRaw
        .mockResolvedValueOnce([cityRow()])
        .mockResolvedValueOnce([]);

      const result = await service.searchLocations(' Da Nang ', 10);

      expect(result).toEqual([
        {
          city: {
            id: 130014,
            name: 'Đà Nẵng',
            latitude: '16.054407',
            longitude: '108.202167',
          },
          state,
          country,
        },
      ]);
      expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
    });

    it('returns state-only matches (city: null) when no city matches', async () => {
      prisma.$queryRaw
        .mockResolvedValueOnce([])
        .mockResolvedValueOnce([stateRow()]);

      const result = await service.searchLocations('Lam Dong', 5);

      expect(result).toEqual([{ city: null, state, country }]);
      expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
    });

    it('suppresses a province row already represented by a city result', async () => {
      prisma.$queryRaw
        .mockResolvedValueOnce([cityRow()])
        .mockResolvedValueOnce([stateRow()]);

      const result = await service.searchLocations('Da Nang', 10);

      expect(result).toEqual([
        {
          city: {
            id: 130014,
            name: 'Đà Nẵng',
            latitude: '16.054407',
            longitude: '108.202167',
          },
          state,
          country,
        },
      ]);
      expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
    });

    it('collapses accent-insensitive city aliases and prefers the native city name', async () => {
      prisma.$queryRaw
        .mockResolvedValueOnce([
          cityRow({ cityId: 1, cityName: 'Da Nang' }),
          cityRow({ cityId: 2, cityName: 'Đà Nẵng' }),
        ])
        .mockResolvedValueOnce([]);

      const result = await service.searchLocations('Da Nang', 10);

      expect(result).toEqual([
        {
          city: {
            id: 2,
            name: 'Đà Nẵng',
            latitude: '16.054407',
            longitude: '108.202167',
          },
          state,
          country,
        },
      ]);
      expect(prisma.$queryRaw).toHaveBeenCalledTimes(2);
    });

    it('collapses administrative city aliases', async () => {
      const vungTauState = {
        id: 3790,
        name: 'Bà Rịa-Vũng Tàu',
        iso2: '43',
        type: 'province',
        latitude: '10.541740',
        longitude: '107.242997',
      };

      prisma.$queryRaw
        .mockResolvedValueOnce([
          cityRow({
            cityId: 10,
            cityName: 'Thành Phố Vũng Tàu',
            cityLatitude: '10.411379',
            cityLongitude: '107.136223',
            stateId: vungTauState.id,
            stateName: vungTauState.name,
            stateIso2: vungTauState.iso2,
            stateType: vungTauState.type,
            stateLatitude: vungTauState.latitude,
            stateLongitude: vungTauState.longitude,
          }),
          cityRow({
            cityId: 11,
            cityName: 'Vũng Tàu',
            cityLatitude: '10.411379',
            cityLongitude: '107.136223',
            stateId: vungTauState.id,
            stateName: vungTauState.name,
            stateIso2: vungTauState.iso2,
            stateType: vungTauState.type,
            stateLatitude: vungTauState.latitude,
            stateLongitude: vungTauState.longitude,
          }),
          cityRow({
            cityId: 12,
            cityName: 'Vũng Tàu Beach',
            cityLatitude: '10.411379',
            cityLongitude: '107.136223',
            stateId: vungTauState.id,
            stateName: vungTauState.name,
            stateIso2: vungTauState.iso2,
            stateType: vungTauState.type,
            stateLatitude: vungTauState.latitude,
            stateLongitude: vungTauState.longitude,
          }),
        ])
        .mockResolvedValueOnce([]);

      const result = await service.searchLocations('Vung Tau', 10);

      expect(result).toEqual([
        {
          city: {
            id: 11,
            name: 'Vũng Tàu',
            latitude: '10.411379',
            longitude: '107.136223',
          },
          state: vungTauState,
          country,
        },
        {
          city: {
            id: 12,
            name: 'Vũng Tàu Beach',
            latitude: '10.411379',
            longitude: '107.136223',
          },
          state: vungTauState,
          country,
        },
      ]);
    });

    it('caps total results to take', async () => {
      prisma.$queryRaw.mockResolvedValueOnce([
        cityRow({
          cityId: 1,
          cityName: 'City 1',
          cityLatitude: '0',
          cityLongitude: '0',
        }),
        cityRow({
          cityId: 2,
          cityName: 'City 2',
          cityLatitude: '0',
          cityLongitude: '0',
        }),
        cityRow({
          cityId: 3,
          cityName: 'City 3',
          cityLatitude: '0',
          cityLongitude: '0',
        }),
      ]);

      const result = await service.searchLocations('City', 2);

      expect(result).toHaveLength(2);
      expect(prisma.$queryRaw).toHaveBeenCalledTimes(1);
    });

    it('does not query for short search text', async () => {
      const result = await service.searchLocations(' a ', 50);

      expect(result).toEqual([]);
      expect(prisma.$queryRaw).not.toHaveBeenCalled();
    });
  });
});
