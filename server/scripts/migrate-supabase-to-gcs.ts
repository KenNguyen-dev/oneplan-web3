/**
 * One-shot migration: copy every object in the Supabase media/public buckets
 * to the matching GCS bucket, preserving keys.
 *
 * Reads env vars directly (NOT via Nest/ConfigService) so it works while both
 * Supabase and GCS credentials coexist locally, and isn't blocked by Joi
 * removing the SUPABASE_* requirements from the runtime schema.
 *
 * Required env:
 *   SUPABASE_URL
 *   SUPABASE_S3_ACCESS_KEY
 *   SUPABASE_S3_SECRET_KEY
 *   SUPABASE_STORAGE_BUCKET    (source bucket for --bucket=media)
 *   SUPABASE_PUBLIC_BUCKET     (source bucket for --bucket=public)
 *   GCS_MEDIA_BUCKET           (target for --bucket=media)
 *   GCS_PUBLIC_BUCKET          (target for --bucket=public)
 *   GOOGLE_CLOUD_PROJECT       (optional — picked up by SDK if set)
 *   STORAGE_SA_KEY_FILE               (path to the storage SA JSON; optional if using ADC)
 *
 * Usage:
 *   pnpm tsx --env-file=.env scripts/migrate-supabase-to-gcs.ts --bucket=media
 *   pnpm tsx --env-file=.env scripts/migrate-supabase-to-gcs.ts --bucket=public
 *
 * Idempotent: skips objects that already exist in GCS with the same size.
 */
import { PrismaClient } from '@prisma/client';
import {
  GetObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  S3Client,
} from '@aws-sdk/client-s3';
import { Storage } from '@google-cloud/storage';

const THUMB_SUFFIX = '.thumb.webp';
const CONCURRENCY = 5;

function envOrThrow(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing env var: ${name}`);
  return value;
}

function parseArgs(): { bucket: 'media' | 'public' } {
  const arg = process.argv.find((a) => a.startsWith('--bucket='));
  const value = arg?.split('=')[1];
  if (value !== 'media' && value !== 'public') {
    console.error('Usage: migrate-supabase-to-gcs.ts --bucket=media|public');
    process.exit(1);
  }
  return { bucket: value };
}

const { bucket: mode } = parseArgs();

const SUPABASE_URL = envOrThrow('SUPABASE_URL');
const SUPABASE_BUCKET =
  mode === 'media'
    ? envOrThrow('SUPABASE_STORAGE_BUCKET')
    : envOrThrow('SUPABASE_PUBLIC_BUCKET');
const GCS_BUCKET =
  mode === 'media' ? envOrThrow('GCS_MEDIA_BUCKET') : envOrThrow('GCS_PUBLIC_BUCKET');

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

const gcs = new Storage({
  projectId: process.env.GOOGLE_CLOUD_PROJECT || undefined,
  keyFilename: process.env.STORAGE_SA_KEY_FILE || undefined,
});
const gcsBucket = gcs.bucket(GCS_BUCKET);

const prisma = new PrismaClient();

type Outcome = 'copied' | 'skipped' | 'failed';

function isObjectKey(value: string | null | undefined): value is string {
  if (!value) return false;
  if (/^https?:\/\//i.test(value)) return false;
  return true;
}

async function collectMediaKeys(): Promise<string[]> {
  const keys = new Set<string>();
  const collect = (value: string | null | undefined) => {
    if (isObjectKey(value)) {
      keys.add(value);
      // Thumb sibling for image keys (audio etc. won't have one — copy will
      // just fail-soft and the outcome counter records it).
      if (!value.endsWith(THUMB_SUFFIX)) {
        keys.add(`${value}${THUMB_SUFFIX}`);
      }
    }
  };

  const [
    users,
    trips,
    photos,
    listings,
    items,
    messages,
    acquisitions,
    expenses,
    boards,
  ] = await Promise.all([
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
    prisma.expense.findMany({ select: { receiptUrl: true } }),
    prisma.board.findMany({ select: { coverImageUrl: true } }),
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
  expenses.forEach((e) => collect(e.receiptUrl));
  boards.forEach((b) => collect(b.coverImageUrl));

  return [...keys];
}

async function listPublicBucketKeys(): Promise<string[]> {
  const keys: string[] = [];
  let continuationToken: string | undefined;
  do {
    const response = await s3.send(
      new ListObjectsV2Command({
        Bucket: SUPABASE_BUCKET,
        ContinuationToken: continuationToken,
      }),
    );
    for (const obj of response.Contents ?? []) {
      if (obj.Key) keys.push(obj.Key);
    }
    continuationToken = response.IsTruncated
      ? response.NextContinuationToken
      : undefined;
  } while (continuationToken);
  return keys;
}

async function copyKey(key: string): Promise<Outcome> {
  // Fetch source size first (cheap; also confirms it exists in Supabase).
  let sourceSize: number | undefined;
  let sourceContentType: string | undefined;
  try {
    const head = await s3.send(
      new HeadObjectCommand({ Bucket: SUPABASE_BUCKET, Key: key }),
    );
    sourceSize = head.ContentLength;
    sourceContentType = head.ContentType;
  } catch {
    // Doesn't exist in source — most likely a thumb sibling we speculatively
    // added that was never generated. Not an error.
    return 'skipped';
  }

  // Idempotency: skip if GCS already has it at the same size.
  try {
    const [meta] = await gcsBucket.file(key).getMetadata();
    const existingSize =
      typeof meta.size === 'string' ? parseInt(meta.size, 10) : meta.size;
    if (existingSize === sourceSize) return 'skipped';
  } catch {
    // Not in GCS yet — fall through to copy.
  }

  try {
    const body = await s3.send(
      new GetObjectCommand({ Bucket: SUPABASE_BUCKET, Key: key }),
    );
    if (!body.Body) return 'failed';
    const buf = Buffer.from(await body.Body.transformToByteArray());
    await gcsBucket.file(key).save(buf, {
      resumable: false,
      contentType: sourceContentType,
    });
    return 'copied';
  } catch (error) {
    console.error(`  ✗ ${key}: ${error}`);
    return 'failed';
  }
}

async function runWithConcurrency(
  keys: string[],
): Promise<Record<Outcome, number>> {
  const counts: Record<Outcome, number> = {
    copied: 0,
    skipped: 0,
    failed: 0,
  };
  let cursor = 0;

  const runners = Array.from({ length: CONCURRENCY }, async () => {
    while (cursor < keys.length) {
      const i = cursor++;
      const result = await copyKey(keys[i]);
      counts[result]++;
      const total = counts.copied + counts.skipped + counts.failed;
      if (total % 25 === 0) {
        console.log(`  progress: ${total}/${keys.length}`);
      }
    }
  });

  await Promise.all(runners);
  return counts;
}

async function main(): Promise<void> {
  console.log(
    `Migrating Supabase bucket "${SUPABASE_BUCKET}" → GCS bucket "${GCS_BUCKET}" (mode: ${mode})`,
  );

  let keys: string[];
  if (mode === 'media') {
    console.log('Collecting object keys from database…');
    keys = await collectMediaKeys();
  } else {
    console.log('Listing public bucket contents…');
    keys = await listPublicBucketKeys();
  }
  console.log(`Found ${keys.length} candidate keys.`);

  if (keys.length === 0) return;

  console.log(`Copying with concurrency ${CONCURRENCY}…`);
  const counts = await runWithConcurrency(keys);

  console.log('\nDone.');
  console.log(`  copied:  ${counts.copied}`);
  console.log(`  skipped: ${counts.skipped}`);
  console.log(`  failed:  ${counts.failed}`);
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
