import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

type LocationCitySearchRow = {
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
};

type LocationStateSearchRow = Omit<
  LocationCitySearchRow,
  'cityId' | 'cityName' | 'cityLatitude' | 'cityLongitude'
>;

type LocationStateResult = {
  id: number;
  name: string;
  iso2: string | null;
  type: string | null;
  latitude: string | null;
  longitude: string | null;
};

type LocationCountryResult = {
  id: number;
  name: string;
  iso2: string | null;
  iso3: string | null;
  phoneCode: string | null;
  capital: string | null;
  currency: string | null;
  region: string | null;
  subRegion: string | null;
  emoji: string | null;
};

type LocationSearchResult = {
  city: {
    id: number;
    name: string;
    latitude: string;
    longitude: string;
  } | null;
  state: LocationStateResult;
  country: LocationCountryResult;
};

@Injectable()
export class LocationsService {
  constructor(private readonly prisma: PrismaService) {}

  private readonly countrySelect = {
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
  };

  private readonly stateSelect = {
    id: true,
    name: true,
    iso2: true,
    type: true,
    latitude: true,
    longitude: true,
  };

  private readonly citySelect = {
    id: true,
    name: true,
    latitude: true,
    longitude: true,
  };

  findAllCountries() {
    return this.prisma.country.findMany({
      select: this.countrySelect,
      orderBy: { name: 'asc' },
    });
  }

  findStatesByCountry(countryId: number) {
    return this.prisma.state.findMany({
      where: { countryId },
      select: this.stateSelect,
      orderBy: { name: 'asc' },
    });
  }

  async searchLocations(search: string, take: number = 50) {
    const trimmedSearch = search.trim();
    if (trimmedSearch.length < 2) return [];

    const rawCandidateTake = Math.min(take * 3, 300);

    const cities = await this.prisma.$queryRaw<LocationCitySearchRow[]>(
      Prisma.sql`
        SELECT
          c.id AS "cityId",
          c.name AS "cityName",
          c.latitude::text AS "cityLatitude",
          c.longitude::text AS "cityLongitude",
          s.id AS "stateId",
          s.name AS "stateName",
          s.iso2 AS "stateIso2",
          s.type AS "stateType",
          s.latitude::text AS "stateLatitude",
          s.longitude::text AS "stateLongitude",
          co.id AS "countryId",
          co.name AS "countryName",
          co.iso2 AS "countryIso2",
          co.iso3 AS "countryIso3",
          co.phone_code AS "countryPhoneCode",
          co.capital AS "countryCapital",
          co.currency AS "countryCurrency",
          co.region AS "countryRegion",
          co.sub_region AS "countrySubRegion",
          co.emoji AS "countryEmoji"
        FROM "oneplandb"."city" c
        JOIN "oneplandb"."state" s ON s.id = c.state_id
        JOIN "oneplandb"."country" co ON co.id = c.country_id
        WHERE "oneplandb".normalize_loc(${trimmedSearch}::text) <> ''
          AND "oneplandb".normalize_loc(c.name) LIKE
              '%' || "oneplandb".normalize_loc(${trimmedSearch}::text) || '%'
        ORDER BY
          CASE
            WHEN "oneplandb".normalize_loc(c.name) = "oneplandb".normalize_loc(${trimmedSearch}::text) THEN 0
            WHEN "oneplandb".normalize_loc(c.name) LIKE "oneplandb".normalize_loc(${trimmedSearch}::text) || '%' THEN 1
            ELSE 2
          END,
          length("oneplandb".normalize_loc(c.name)) ASC,
          c.name ASC
        LIMIT ${rawCandidateTake}
      `,
    );

    const cityResults = this.dedupeCityResults(
      cities.map((row) => ({
        city: {
          id: row.cityId,
          name: row.cityName,
          latitude: row.cityLatitude,
          longitude: row.cityLongitude,
        },
        state: this.mapStateSearchRow(row),
        country: this.mapCountrySearchRow(row),
      })),
    );

    const remaining = take - cityResults.length;
    const states =
      remaining > 0
        ? await this.prisma.$queryRaw<LocationStateSearchRow[]>(
            Prisma.sql`
              SELECT
                s.id AS "stateId",
                s.name AS "stateName",
                s.iso2 AS "stateIso2",
                s.type AS "stateType",
                s.latitude::text AS "stateLatitude",
                s.longitude::text AS "stateLongitude",
                co.id AS "countryId",
                co.name AS "countryName",
                co.iso2 AS "countryIso2",
                co.iso3 AS "countryIso3",
                co.phone_code AS "countryPhoneCode",
                co.capital AS "countryCapital",
                co.currency AS "countryCurrency",
                co.region AS "countryRegion",
                co.sub_region AS "countrySubRegion",
                co.emoji AS "countryEmoji"
              FROM "oneplandb"."state" s
              JOIN "oneplandb"."country" co ON co.id = s.country_id
              WHERE "oneplandb".normalize_loc(${trimmedSearch}::text) <> ''
                AND "oneplandb".normalize_loc(s.name) LIKE
                    '%' || "oneplandb".normalize_loc(${trimmedSearch}::text) || '%'
              ORDER BY
                CASE
                  WHEN "oneplandb".normalize_loc(s.name) = "oneplandb".normalize_loc(${trimmedSearch}::text) THEN 0
                  WHEN "oneplandb".normalize_loc(s.name) LIKE "oneplandb".normalize_loc(${trimmedSearch}::text) || '%' THEN 1
                  ELSE 2
                END,
                length("oneplandb".normalize_loc(s.name)) ASC,
                s.name ASC
              LIMIT ${Math.min(remaining * 3, 300)}
            `,
          )
        : [];

    const stateResults = this.filterDuplicateStateResults(
      states.map((row) => ({
        city: null,
        state: this.mapStateSearchRow(row),
        country: this.mapCountrySearchRow(row),
      })),
      cityResults,
    );

    return [...cityResults, ...stateResults].slice(0, take);
  }

  private filterDuplicateStateResults(
    stateResults: LocationSearchResult[],
    cityResults: LocationSearchResult[],
  ): LocationSearchResult[] {
    const representedStateIds = new Set(
      cityResults.map((result) => result.state.id),
    );
    return stateResults.filter(
      (result) => !representedStateIds.has(result.state.id),
    );
  }

  private dedupeCityResults(
    results: LocationSearchResult[],
  ): LocationSearchResult[] {
    const bestByDestination = new Map<string, LocationSearchResult>();

    for (const result of results) {
      if (!result.city) continue;

      const key = [
        result.country.id,
        result.state.id,
        this.normalizeLocationName(result.city.name),
      ].join(':');
      const current = bestByDestination.get(key);

      if (!current || this.isBetterCityResult(result, current)) {
        bestByDestination.set(key, result);
      }
    }

    return [...bestByDestination.values()];
  }

  private normalizeLocationName(name: string) {
    return name
      .trim()
      .toLocaleLowerCase('en-US')
      .replace(/đ/g, 'd')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/^(thanh\s+pho|tp\.?)\s+/i, '')
      .replace(/[^\p{L}\p{N}]+/gu, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  private isBetterCityResult(
    candidate: LocationSearchResult,
    current: LocationSearchResult,
  ) {
    const candidateName = candidate.city?.name ?? '';
    const currentName = current.city?.name ?? '';
    const candidateHasAdminPrefix = this.hasAdministrativePrefix(candidateName);
    const currentHasAdminPrefix = this.hasAdministrativePrefix(currentName);

    if (candidateHasAdminPrefix !== currentHasAdminPrefix) {
      return !candidateHasAdminPrefix;
    }

    const candidateHasNativeAccent = this.hasNativeAccent(candidateName);
    const currentHasNativeAccent = this.hasNativeAccent(currentName);

    if (candidateHasNativeAccent !== currentHasNativeAccent) {
      return candidateHasNativeAccent;
    }

    return candidateName.length < currentName.length;
  }

  private hasAdministrativePrefix(name: string) {
    return /^(thành\s+phố|thanh\s+pho|tp\.?)\s+/i.test(name.trim());
  }

  private hasNativeAccent(name: string) {
    return /[^\u0000-\u007F]/.test(name);
  }

  private mapStateSearchRow(row: LocationStateSearchRow) {
    return {
      id: row.stateId,
      name: row.stateName,
      iso2: row.stateIso2,
      type: row.stateType,
      latitude: row.stateLatitude,
      longitude: row.stateLongitude,
    };
  }

  private mapCountrySearchRow(row: LocationStateSearchRow) {
    return {
      id: row.countryId,
      name: row.countryName,
      iso2: row.countryIso2,
      iso3: row.countryIso3,
      phoneCode: row.countryPhoneCode,
      capital: row.countryCapital,
      currency: row.countryCurrency,
      region: row.countryRegion,
      subRegion: row.countrySubRegion,
      emoji: row.countryEmoji,
    };
  }

  async findCitiesByState(
    stateId: number,
    search?: string,
    cursor?: number,
    take: number = 50,
  ) {
    const cities = await this.prisma.city.findMany({
      where: {
        stateId,
        ...(search
          ? { name: { contains: search, mode: 'insensitive' as const } }
          : {}),
      },
      select: this.citySelect,
      orderBy: { name: 'asc' },
      take,
      ...(cursor ? { skip: 1, cursor: { id: cursor } } : {}),
    });

    return {
      data: cities,
      nextCursor: cities.length === take ? cities[cities.length - 1].id : null,
    };
  }
}
