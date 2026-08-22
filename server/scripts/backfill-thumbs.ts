/**
 * Backfill thumbnails for legacy image uploads.
 *
 * Walks every DB column that stores a Supabase storage object key for an
 * image, and ensures a sibling `<key>.thumb.webp` exists. Idempotent — re-runs
 * skip keys whose thumb is already present.
 *
 * Usage: pnpm tsx --env-file=.env scripts/backfill-thumbs.ts
 */
import { PrismaClient } from '@prisma/client';
import {
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import sharp from 'sharp';

const THUMB_SUFFIX = '.thumb.webp';
const THUMB_WIDTH = 1200;
const THUMB_QUALITY = 75;
const CONCURRENCY = 5;

const prisma = new PrismaClient();

function envOrThrow(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing env var: ${name}`);
  return value;
}

const SUPABASE_URL = envOrThrow('SUPABASE_URL');
const BUCKET = envOrThrow('SUPABASE_STORAGE_BUCKET');

const s3 = new S3Client({
  forcePathStyle: true,
  region: 'auto',
  endpoint: SUPABASE_URL.endsWith('/storage/v1/s3')
    ? SUPABASE_URL
    : `${SUPABASE_URL}/storage/v1/s3`,
  credentials: {
    accessKeyId: envOrThrow('SUPABASE_S3_ACCESS_KEY'),
    secretAccessKey: envOrThrow('SUPABASE_S3_SECRET_KEY'),
  },
});

function isObjectKey(value: string | null | undefined): value is string {
  if (!value) return false;
  if (/^https?:\/\//i.test(value)) return false;
  if (value.endsWith(THUMB_SUFFIX)) return false;
  return true;
}

async function thumbExists(thumbKey: string): Promise<boolean> {
  try {
    await s3.send(new HeadObjectCommand({ Bucket: BUCKET, Key: thumbKey }));
    return true;
  } catch {
    return false;
  }
}

type Outcome = 'generated' | 'skipped' | 'failed';

async function processKey(objectKey: string): Promise<Outcome> {
  const thumbKey = `${objectKey}${THUMB_SUFFIX}`;
  if (await thumbExists(thumbKey)) return 'skipped';

  try {
    const original = await s3.send(
      new GetObjectCommand({ Bucket: BUCKET, Key: objectKey }),
    );
    if (!original.Body) return 'failed';
    const buf = Buffer.from(await original.Body.transformToByteArray());
    const thumb = await sharp(buf)
      .rotate()
      .resize({ width: THUMB_WIDTH, withoutEnlargement: true })
      .webp({ quality: THUMB_QUALITY })
      .toBuffer();
    await s3.send(
      new PutObjectCommand({
        Bucket: BUCKET,
        Key: thumbKey,
        Body: thumb,
        ContentType: 'image/webp',
      }),
    );
    return 'generated';
  } catch (error) {
    console.error(`  ✗ ${objectKey}: ${error}`);
    return 'failed';
  }
}

async function collectKeys(): Promise<string[]> {
  const keys = new Set<string>();
  const collect = (value: string | null | undefined) => {
    if (isObjectKey(value)) keys.add(value);
  };

  const [users, trips, photos, listings, items, messages, acquisitions] =
    await Promise.all([
      prisma.user.findMany({ select: { avatarUrl: true } }),
      prisma.trip.findMany({ select: { coverImageUrl: true } }),
      prisma.tripPhoto.findMany({ select: { photoUrl: true } }),
      prisma.marketplaceListing.findMany({ select: { coverImageUrl: true } }),
      prisma.tripPlanMarketItem.findMany({ select: { imageUrls: true } }),
      prisma.chatMessage.findMany({ select: { imageObjectKey: true } }),
      prisma.marketplaceAcquisition.findMany({
        select: {
          snapshotCoverImageUrl: true,
          snapshotCreatorAvatarUrl: true,
        },
      }),
    ]);

  users.forEach((u) => collect(u.avatarUrl));
  trips.forEach((t) => collect(t.coverImageUrl));
  photos.forEach((p) => collect(p.photoUrl));
  listings.forEach((l) => collect(l.coverImageUrl));
  items.forEach((i) => i.imageUrls.forEach(collect));
  messages.forEach((m) => collect(m.imageObjectKey));
  acquisitions.forEach((a) => {
    collect(a.snapshotCoverImageUrl);
    collect(a.snapshotCreatorAvatarUrl);
  });

  return [...keys];
}

async function runWithConcurrency(
  keys: string[],
  worker: (k: string) => Promise<Outcome>,
): Promise<Record<Outcome, number>> {
  const counts: Record<Outcome, number> = {
    generated: 0,
    skipped: 0,
    failed: 0,
  };
  let cursor = 0;

  const runners = Array.from({ length: CONCURRENCY }, async () => {
    while (cursor < keys.length) {
      const i = cursor++;
      const result = await worker(keys[i]);
      counts[result]++;
      if ((counts.generated + counts.skipped + counts.failed) % 25 === 0) {
        console.log(
          `  progress: ${counts.generated + counts.skipped + counts.failed}/${keys.length}`,
        );
      }
    }
  });

  await Promise.all(runners);
  return counts;
}

async function main(): Promise<void> {
  console.log('Collecting object keys from database…');
  const keys = await collectKeys();
  console.log(`Found ${keys.length} unique image object keys.`);

  if (keys.length === 0) return;

  console.log(`Processing with concurrency ${CONCURRENCY}…`);
  const counts = await runWithConcurrency(keys, processKey);

  console.log('\nDone.');
  console.log(`  generated: ${counts.generated}`);
  console.log(`  skipped (already present): ${counts.skipped}`);
  console.log(`  failed: ${counts.failed}`);
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
