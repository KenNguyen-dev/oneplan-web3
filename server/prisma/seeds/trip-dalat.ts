import { randomBytes } from 'crypto';
import { ExpenseCategory, InviteStatus, PrismaClient, TripStatus } from '@prisma/client';

const prisma = new PrismaClient();

const DA_LAT_CITY_ID = 130630;
const LAM_DONG_STATE_ID = 3818;
const VIETNAM_COUNTRY_ID = 240;

const NAMES = [
  'Alice', 'Bob', 'Carlos', 'Diana', 'Elena',
  'Frank', 'Grace', 'Hiro', 'Ivy', 'Jake',
  'Kai', 'Luna', 'Marco', 'Nadia', 'Oscar',
  'Priya', 'Quinn', 'Rosa', 'Sam', 'Tara',
];

interface PlanItemSeed {
  sortOrder: number;
  startTime: string;
  title: string;
  location: string;
  category: ExpenseCategory;
}

const PLAN_DAYS: PlanItemSeed[][] = [
  // Day 1 — City & Nature
  [
    { sortOrder: 0, startTime: '08:00', title: 'Breakfast at Liên Hoa', location: '1 Nhà Chung, Da Lat', category: ExpenseCategory.FOOD },
    { sortOrder: 1, startTime: '09:30', title: 'Xuân Hương Lake Walk', location: 'Xuân Hương Lake, Da Lat', category: ExpenseCategory.OTHER },
    { sortOrder: 2, startTime: '12:00', title: 'Lunch at Nhà Hàng Gió', location: 'Trần Phú Street, Da Lat', category: ExpenseCategory.FOOD },
    { sortOrder: 3, startTime: '14:00', title: 'Crazy House Visit', location: '3 Huỳnh Thúc Kháng, Da Lat', category: ExpenseCategory.TICKET },
    { sortOrder: 4, startTime: '18:00', title: 'Da Lat Night Market', location: 'Da Lat Night Market', category: ExpenseCategory.FOOD },
  ],
  // Day 2 — Highlands
  [
    { sortOrder: 0, startTime: '07:00', title: 'Coffee at La Viet', location: '200 Nguyễn Công Trứ, Da Lat', category: ExpenseCategory.FOOD },
    { sortOrder: 1, startTime: '09:00', title: 'Datanla Waterfall', location: 'Datanla Waterfall, Da Lat', category: ExpenseCategory.TICKET },
    { sortOrder: 2, startTime: '12:00', title: 'Lunch at Lẩu Bò Hà Nội', location: 'Phan Đình Phùng, Da Lat', category: ExpenseCategory.FOOD },
    { sortOrder: 3, startTime: '14:00', title: 'Valley of Love', location: 'Valley of Love, Da Lat', category: ExpenseCategory.TICKET },
    { sortOrder: 4, startTime: '17:00', title: 'Check in homestay', location: 'Đường Hoa Hồng, Da Lat', category: ExpenseCategory.STAY },
  ],
  // Day 3 — Countryside
  [
    { sortOrder: 0, startTime: '07:30', title: 'Breakfast at Bánh Mì Xin Chào', location: 'Nguyễn Chí Thanh, Da Lat', category: ExpenseCategory.FOOD },
    { sortOrder: 1, startTime: '09:00', title: 'Linh Phước Pagoda', location: '120 Tự Phước, Da Lat', category: ExpenseCategory.OTHER },
    { sortOrder: 2, startTime: '11:30', title: 'Ride to Langbiang', location: 'Langbiang Mountain, Lạc Dương', category: ExpenseCategory.TRANSPORT },
    { sortOrder: 3, startTime: '14:00', title: 'Hike Langbiang Peak', location: 'Langbiang Mountain, Lạc Dương', category: ExpenseCategory.OTHER },
    { sortOrder: 4, startTime: '18:00', title: 'Farewell Dinner', location: 'Trần Phú, Da Lat', category: ExpenseCategory.FOOD },
  ],
];

function parseArgs(): { members: number; userId?: number } {
  const args = process.argv.slice(2);
  let members = 4;
  let userId: number | undefined;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--members' && args[i + 1]) {
      members = parseInt(args[i + 1], 10);
    }
    if (args[i] === '--userId' && args[i + 1]) {
      userId = parseInt(args[i + 1], 10);
    }
  }

  return { members, userId };
}

function generateProfiles(count: number): { email: string; displayName: string }[] {
  const shuffled = [...NAMES].sort(() => Math.random() - 0.5);
  const profiles: { email: string; displayName: string }[] = [];

  for (let i = 0; i < count; i++) {
    const name = i < shuffled.length
      ? shuffled[i]
      : `${shuffled[i % shuffled.length]}${Math.floor(i / shuffled.length)}`;
    profiles.push({
      email: `${name.toLowerCase()}@seed.test`,
      displayName: name,
    });
  }

  return profiles;
}

async function main() {
  const { members, userId } = parseArgs();

  console.log(`Seeding Da Lat trip with ${members} member(s)...`);

  // Validate location data exists
  try {
    await prisma.city.findUniqueOrThrow({ where: { id: DA_LAT_CITY_ID } });
  } catch {
    console.error(`City Da Lat (id ${DA_LAT_CITY_ID}) not found. Run prisma:seed:countries first.`);
    process.exit(1);
  }

  // Resolve trip creator
  let creator!: { id: number; displayName: string | null };
  if (userId) {
    try {
      creator = await prisma.user.findUniqueOrThrow({ where: { id: userId } });
      console.log(`Using existing user "${creator.displayName}" (id: ${creator.id}) as trip creator.`);
    } catch {
      console.error(`User with id ${userId} not found.`);
      process.exit(1);
    }
  }

  // Create seed users for additional members
  const profiles = generateProfiles(members);
  const emails = profiles.map(p => p.email);

  await prisma.user.createMany({
    data: profiles,
    skipDuplicates: true,
  });

  const seedUsers = await prisma.user.findMany({
    where: { email: { in: emails } },
  });

  // If no --userId provided, first seed user is the creator
  if (!userId) {
    creator = seedUsers[0];
  }

  const allMembers = userId
    ? [creator!, ...seedUsers]
    : seedUsers;

  // Remove prior Da Lat seed trips created by this user (idempotent re-seed).
  const existingDalatTrips = await prisma.trip.findMany({
    where: { name: 'Da Lat Adventure', createdById: creator.id },
    select: { id: true },
  });
  if (existingDalatTrips.length > 0) {
    await prisma.trip.deleteMany({
      where: { id: { in: existingDalatTrips.map(t => t.id) } },
    });
    console.log(`Removed ${existingDalatTrips.length} prior Da Lat trip(s).`);
  }

  // Create trip (tomorrow → tomorrow + 2 days)
  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);
  tomorrow.setHours(0, 0, 0, 0);

  const endDate = new Date(tomorrow);
  endDate.setDate(endDate.getDate() + 2);

  const trip = await prisma.trip.create({
    data: {
      name: 'Da Lat Adventure',
      status: TripStatus.PLANNING,
      startDate: tomorrow,
      endDate,
      inviteCode: randomBytes(16).toString('hex'),
      createdById: creator.id,
      cityId: DA_LAT_CITY_ID,
      stateId: LAM_DONG_STATE_ID,
      countryId: VIETNAM_COUNTRY_ID,
    },
  });

  console.log(`Created trip "${trip.name}" (id: ${trip.id})`);

  // Create trip members — all ACCEPTED
  const now = new Date();
  const memberData = allMembers.map(user => ({
    tripId: trip.id,
    userId: user.id,
    inviteStatus: InviteStatus.ACCEPTED,
    joinedAt: now,
    createdAt: now,
  }));

  await prisma.tripMember.createMany({
    data: memberData,
    skipDuplicates: true,
  });

  console.log(`Added ${memberData.length} member(s): ${allMembers.map(m => m.displayName).join(', ')}`);

  // Create plan items for 3 days
  let totalItems = 0;

  for (let dayOffset = 0; dayOffset < PLAN_DAYS.length; dayOffset++) {
    const planDate = new Date(tomorrow);
    planDate.setDate(planDate.getDate() + dayOffset);

    const dayItems = PLAN_DAYS[dayOffset];

    for (const item of dayItems) {
      const planItem = await prisma.tripPlanItem.create({
        data: {
          tripId: trip.id,
          planDate,
          dayNumber: dayOffset + 1,
          title: item.title,
          location: item.location,
          startTime: item.startTime,
          category: item.category,
          sortOrder: item.sortOrder,
        },
      });

      // Assign 1–3 random members to each plan item
      const shuffledUsers = [...allMembers].sort(() => Math.random() - 0.5);
      const assignCount = Math.min(1 + Math.floor(Math.random() * 3), allMembers.length);
      const assigned = shuffledUsers.slice(0, assignCount);

      await prisma.tripPlanItemMember.createMany({
        data: assigned.map(u => ({
          tripPlanItemId: planItem.id,
          userId: u.id,
        })),
        skipDuplicates: true,
      });

      totalItems++;
    }

    console.log(`  Day ${dayOffset + 1} (${planDate.toISOString().split('T')[0]}): ${dayItems.length} items`);
  }

  console.log(`Created ${totalItems} plan item(s) across 3 days.`);
}

main()
  .catch(e => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
