import { existsSync, readFileSync } from 'fs';
import { join } from 'path';
import { PrismaService } from '../../src/prisma/prisma.service';
import { LocationsService } from '../../src/locations/locations.service';

/**
 * DB-backed ranking tests for searchLocations. The relevance ranking lives
 * entirely in SQL (normalize_loc + exactness tiers), so it cannot be verified
 * with a mocked $queryRaw — it needs the real seeded `city` table.
 *
 * Opt-in (keeps default `pnpm test` / CI green without seeded location data):
 *   RUN_DB_TESTS=1 pnpm test test/locations/locations.search.db.spec.ts
 */
const runDb = process.env.RUN_DB_TESTS === '1';
const describeDb = runDb ? describe : describe.skip;

// Known seeded rows (see prisma:seed:countries) used as a sanity gate.
const HUE_CITY_ID = 130554; // "Huế", Vietnam
const HANOI_CITY_ID = 130201; // "Hanoi", Vietnam

function ensureDatabaseUrl(): void {
  if (process.env.DATABASE_URL) return;
  const envPath = join(process.cwd(), '.env');
  if (!existsSync(envPath)) return;
  const line = readFileSync(envPath, 'utf8')
    .split('\n')
    .find((l) => l.startsWith('DATABASE_URL='));
  if (line)
    process.env.DATABASE_URL = line.slice('DATABASE_URL='.length).trim();
}

describeDb('LocationsService.searchLocations (DB-backed ranking)', () => {
  let prisma: PrismaService;
  let service: LocationsService;

  beforeAll(async () => {
    ensureDatabaseUrl();
    prisma = new PrismaService();
    await prisma.$connect();

    const [hue, hanoi] = await Promise.all([
      prisma.city.findUnique({ where: { id: HUE_CITY_ID } }),
      prisma.city.findUnique({ where: { id: HANOI_CITY_ID } }),
    ]);
    if (!hue || !hanoi) {
      throw new Error(
        'Seed data missing (Huế/Hanoi). Run `pnpm prisma:seed:countries` before RUN_DB_TESTS.',
      );
    }

    service = new LocationsService(prisma);
  });

  afterAll(async () => {
    await prisma?.$disconnect();
  });

  it('ranks the exact city "Huế" first for query "Hue" (was buried at ~77)', async () => {
    const result = await service.searchLocations('Hue', 50);

    expect(result.length).toBeGreaterThan(0);
    expect(result[0].city?.name).toBe('Huế');
    expect(result[0].country.iso2).toBe('VN');
  });

  it('matches "Hanoi" for the space-separated query "Ha Noi" (was zero results)', async () => {
    const result = await service.searchLocations('Ha Noi', 50);

    expect(result.length).toBeGreaterThan(0);
    expect(result[0].city?.name).toBe('Hanoi');
    expect(result[0].country.iso2).toBe('VN');
  });

  it('ranks Da Nang first and collapses the accented/plain alias', async () => {
    const result = await service.searchLocations('Da Nang', 50);

    expect(result.length).toBeGreaterThan(0);
    const top = result[0];
    expect(top.country.iso2).toBe('VN');
    expect(top.city?.name.normalize('NFD').replace(/[̀-ͯ]/g, '')).toBe('Da Nang');
    // Da Nang + Đà Nẵng must dedupe to a single entry for that state.
    const danangForState = result.filter(
      (r) =>
        r.state.id === top.state.id &&
        r.city?.name.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase() ===
          'da nang',
    );
    expect(danangForState).toHaveLength(1);
  });

  it('returns the province as a state-only match for "Dak Lak"', async () => {
    const result = await service.searchLocations('Dak Lak', 50);

    expect(result.length).toBeGreaterThan(0);
    expect(result[0].city).toBeNull();
    expect(result[0].state.name).toBe('Đắk Lắk');
    expect(result[0].country.iso2).toBe('VN');
  });

  it('returns nothing when the query normalizes to empty (punctuation only)', async () => {
    const result = await service.searchLocations('--', 50);
    expect(result).toEqual([]);
  });
});
