import { AuthProvider, PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';
import { randomBytes } from 'crypto';

const prisma = new PrismaClient();
const BCRYPT_SALT_ROUNDS = 12;

function parseArgs(): { email: string; password: string; displayName?: string } {
  const args = process.argv.slice(2);
  let email = '';
  let password = '';
  let displayName: string | undefined;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--email' && args[i + 1]) {
      email = args[i + 1];
    }
    if (args[i] === '--password' && args[i + 1]) {
      password = args[i + 1];
    }
    if (args[i] === '--name' && args[i + 1]) {
      displayName = args[i + 1];
    }
  }

  if (!email || !password) {
    console.error('Usage: tsx prisma/seeds/create-user.ts --email <email> --password <password> [--name <displayName>]');
    process.exit(1);
  }

  return { email, password, displayName };
}

async function main() {
  const { email, password, displayName } = parseArgs();
  const normalizedEmail = email.toLowerCase();

  const existing = await prisma.user.findUnique({ where: { email: normalizedEmail } });
  if (existing) {
    console.error(`User with email "${normalizedEmail}" already exists (id: ${existing.id}).`);
    process.exit(1);
  }

  const passwordHash = await bcrypt.hash(password, BCRYPT_SALT_ROUNDS);

  const user = await prisma.$transaction(async (tx) => {
    const newUser = await tx.user.create({
      data: {
        email: normalizedEmail,
        displayName: displayName || normalizedEmail.split('@')[0],
        friendCode: randomBytes(32).toString('hex'),
      },
    });

    await tx.authAccount.create({
      data: {
        userId: newUser.id,
        provider: AuthProvider.EMAIL,
        providerUserId: normalizedEmail,
        passwordHash,
      },
    });

    return newUser;
  });

  console.log(`User created successfully:`);
  console.log(`  ID:    ${user.id}`);
  console.log(`  Email: ${user.email}`);
  console.log(`  Name:  ${user.displayName}`);
}

main()
  .catch(e => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
