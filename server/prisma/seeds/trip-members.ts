import { InviteStatus, PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const NAMES = [
  'Alice', 'Bob', 'Carlos', 'Diana', 'Elena',
  'Frank', 'Grace', 'Hiro', 'Ivy', 'Jake',
  'Kai', 'Luna', 'Marco', 'Nadia', 'Oscar',
  'Priya', 'Quinn', 'Rosa', 'Sam', 'Tara',
];

function parseArgs(): { count: number; tripId: number } {
  const args = process.argv.slice(2);
  let count = 3;
  let tripId = 1;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--count' && args[i + 1]) {
      count = parseInt(args[i + 1], 10);
    }
    if (args[i] === '--tripId' && args[i + 1]) {
      tripId = parseInt(args[i + 1], 10);
    }
  }

  return { count, tripId };
}

function generateProfiles(count: number): { email: string; displayName: string }[] {
  const shuffled = [...NAMES].sort(() => Math.random() - 0.5);
  const profiles: { email: string; displayName: string }[] = [];

  for (let i = 0; i < count; i++) {
    const name = i < shuffled.length ? shuffled[i] : `${shuffled[i % shuffled.length]}${Math.floor(i / shuffled.length)}`;
    profiles.push({
      email: `${name.toLowerCase()}@seed.test`,
      displayName: name,
    });
  }

  return profiles;
}

async function main() {
  const { count, tripId } = parseArgs();

  console.log(`Seeding ${count} trip member(s) for trip ${tripId}...`);

  // Validate trip exists
  try {
    await prisma.trip.findUniqueOrThrow({ where: { id: tripId } });
  } catch {
    console.error(`Trip with id ${tripId} not found. Please create the trip first.`);
    process.exit(1);
  }

  // Generate user profiles
  const profiles = generateProfiles(count);
  const emails = profiles.map(p => p.email);

  // Create users (idempotent)
  await prisma.user.createMany({
    data: profiles,
    skipDuplicates: true,
  });

  // Fetch created users by exact email list
  const users = await prisma.user.findMany({
    where: { email: { in: emails } },
  });

  // Create trip members
  const now = new Date();
  const memberData = users.map((user, index) => {
    const isFirst = index === 0;
    const isAccepted = isFirst || Math.random() > 0.5;

    return {
      tripId,
      userId: user.id,
      inviteStatus: isAccepted ? InviteStatus.ACCEPTED : InviteStatus.PENDING,
      joinedAt: isAccepted ? now : null,
      createdAt: now,
    };
  });

  await prisma.tripMember.createMany({
    data: memberData,
    skipDuplicates: true,
  });

  // Log results
  const accepted = memberData.filter(m => m.inviteStatus === InviteStatus.ACCEPTED).length;
  const pending = memberData.filter(m => m.inviteStatus === InviteStatus.PENDING).length;

  console.log(`Created ${memberData.length} trip member(s):`);
  console.log(`  ACCEPTED: ${accepted}`);
  console.log(`  PENDING:  ${pending}`);
  memberData.forEach((m, i) => {
    const profile = profiles[i];
    console.log(`  - ${profile.displayName} (${profile.email}) → ${m.inviteStatus}`);
  });
}

main()
  .catch(e => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
