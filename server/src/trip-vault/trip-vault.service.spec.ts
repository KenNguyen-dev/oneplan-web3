import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Keypair, PublicKey } from '@solana/web3.js';

import { TripVaultService } from './trip-vault.service';

const PROGRAM_ID = new PublicKey(
  '8pjmDZvmRzjcSwzffqnsdzsPRb3nV9BiVDhGU3vmR7uD',
);

function makeDeps() {
  const prisma = {
    tripVault: { findUnique: jest.fn(), create: jest.fn() },
    walletAccount: {
      upsert: jest.fn(),
      findMany: jest.fn(),
      findUnique: jest.fn(),
    },
    tripMember: {
      findMany: jest.fn(),
      findUnique: jest.fn(),
      update: jest.fn(),
    },
    vaultTransaction: {
      create: jest.fn(),
      update: jest.fn(),
    },
    user: { findUnique: jest.fn() },
  };
  const vaultPda = Keypair.generate().publicKey;
  const instruction = jest.fn().mockResolvedValue({
    programId: PROGRAM_ID,
    keys: [],
    data: Buffer.alloc(0),
  });
  // Anchor exposes both: accounts() for fully resolvable account sets, and
  // accountsPartial() where a PDA seed reads a field of the account itself.
  const anchorMethod = () => ({
    accounts: () => ({ instruction }),
    accountsPartial: () => ({ instruction }),
  });
  const solana = {
    isConfigured: true,
    program: {
      programId: PROGRAM_ID,
      methods: {
        initVault: anchorMethod,
        addMember: anchorMethod,
        deposit: anchorMethod,
      },
      account: {
        tripVault: {
          fetch: jest.fn().mockResolvedValue({ members: [] }),
        },
      },
    },
    usdcMint: Keypair.generate().publicKey,
    feePayer: Keypair.generate(),
    connection: { getAccountInfo: jest.fn() },
    vaultPda: jest.fn().mockReturnValue(vaultPda),
    treasuryAta: jest.fn().mockReturnValue(Keypair.generate().publicKey),
    ensureTreasuryAta: jest.fn().mockResolvedValue(Keypair.generate().publicKey),
    getTokenBalance: jest.fn().mockResolvedValue(1_500_000n),
    buildUnsignedTx: jest.fn().mockResolvedValue('base64tx'),
    sendAsFeePayer: jest.fn().mockResolvedValue('sig'),
  };
  const trips = { sendVaultBalanceChanged: jest.fn() };
  return { prisma, solana, trips, vaultPda, instruction };
}

function makeService(deps: ReturnType<typeof makeDeps>) {
  return new TripVaultService(
    deps.prisma as never,
    deps.solana as never,
    deps.trips as never,
  );
}

function vaultRow(
  vaultPda: PublicKey,
  overrides: { status?: string; usdcAta?: string } = {},
) {
  return {
    id: 1,
    tripId: 42,
    vaultPda: vaultPda.toBase58(),
    usdcAta: overrides.usdcAta ?? Keypair.generate().publicKey.toBase58(),
    thresholdMicro: 10_000_000n,
    dailyLimitMicro: 50_000_000n,
    status: overrides.status ?? 'ACTIVE',
  };
}

describe('TripVaultService', () => {
  it('throws when the trip has no vault', async () => {
    const deps = makeDeps();
    const { prisma, solana } = deps;
    prisma.tripVault.findUnique.mockResolvedValue(null);
    const service = makeService(deps);

    await expect(service.requireVault(42)).rejects.toThrow(NotFoundException);
  });

  it('returns the on-chain balance for an existing vault', async () => {
    const deps = makeDeps();
    const { prisma, solana, vaultPda } = deps;
    prisma.tripVault.findUnique.mockResolvedValue(vaultRow(vaultPda));
    const service = makeService(deps);

    const result = await service.getBalance(42);
    expect(result.balanceMicro).toBe(1_500_000n);
    expect(result.vaultPda).toBe(vaultPda.toBase58());
  });

  it('returns zero for a closed vault without reading the closed ATA', async () => {
    const deps = makeDeps();
    const { prisma, solana, vaultPda } = deps;
    prisma.tripVault.findUnique.mockResolvedValue(
      vaultRow(vaultPda, { status: 'CLOSED' }),
    );
    const service = makeService(deps);

    const result = await service.getBalance(42);
    expect(result.balanceMicro).toBe(0n);
    expect(result.vaultPda).toBe(vaultPda.toBase58());
    expect(solana.getTokenBalance).not.toHaveBeenCalled();
  });

  it('returns zero when the vault ATA is missing on chain', async () => {
    const deps = makeDeps();
    const { prisma, solana, vaultPda } = deps;
    prisma.tripVault.findUnique.mockResolvedValue(vaultRow(vaultPda));
    solana.getTokenBalance.mockRejectedValue(new Error('AccountNotFound'));
    const service = makeService(deps);

    const result = await service.getBalance(42);
    expect(result.balanceMicro).toBe(0n);
  });

  it('rejects a deposit from a user with no linked wallet', async () => {
    const deps = makeDeps();
    const { prisma, solana, vaultPda } = deps;
    prisma.tripVault.findUnique.mockResolvedValue(vaultRow(vaultPda));
    prisma.walletAccount.findUnique.mockResolvedValue(null);
    const service = makeService(deps);

    await expect(service.buildDepositTx(42, 7, 100_000n)).rejects.toThrow(
      BadRequestException,
    );
  });

  it('rejects a non-positive deposit amount', async () => {
    const deps = makeDeps();
    const { prisma, solana } = deps;
    const service = makeService(deps);

    await expect(service.buildDepositTx(42, 7, 0n)).rejects.toThrow(
      BadRequestException,
    );
  });

  it('stores a linked wallet public key', async () => {
    const deps = makeDeps();
    const { prisma, solana } = deps;
    const pubkey = Keypair.generate().publicKey.toBase58();
    prisma.walletAccount.upsert.mockResolvedValue({
      userId: 7,
      publicKey: pubkey,
    });
    const service = makeService(deps);

    const result = await service.linkWallet(7, pubkey);
    expect(result.publicKey).toBe(pubkey);
    expect(prisma.walletAccount.upsert).toHaveBeenCalled();
  });

  it('rejects a malformed wallet public key', async () => {
    const deps = makeDeps();
    const { prisma, solana } = deps;
    const service = makeService(deps);

    await expect(service.linkWallet(7, 'not-a-pubkey')).rejects.toThrow(
      BadRequestException,
    );
  });

  it('blocks deleting a trip whose vault still holds funds', async () => {
    const deps = makeDeps();
    const { prisma, solana, vaultPda } = deps;
    prisma.tripVault.findUnique.mockResolvedValue(vaultRow(vaultPda));
    solana.getTokenBalance.mockResolvedValue(500_000n);
    const service = makeService(deps);

    await expect(service.assertDeletable(42)).rejects.toThrow(
      BadRequestException,
    );
  });

  it('allows deleting a trip with an empty vault', async () => {
    const deps = makeDeps();
    const { prisma, solana, vaultPda } = deps;
    prisma.tripVault.findUnique.mockResolvedValue(vaultRow(vaultPda));
    solana.getTokenBalance.mockResolvedValue(0n);
    const service = makeService(deps);

    await expect(service.assertDeletable(42)).resolves.toBeUndefined();
  });

  it('allows deleting a trip that never had a vault', async () => {
    const deps = makeDeps();
    const { prisma, solana } = deps;
    prisma.tripVault.findUnique.mockResolvedValue(null);
    const service = makeService(deps);

    await expect(service.assertDeletable(42)).resolves.toBeUndefined();
  });

  it('skips members that already exist on chain when syncing', async () => {
    const deps = makeDeps();
    const { prisma, solana, vaultPda } = deps;
    prisma.tripVault.findUnique.mockResolvedValue(vaultRow(vaultPda));
    prisma.tripMember.findMany.mockResolvedValue([
      { userId: 7 },
      { userId: 8 },
    ]);
    const already = Keypair.generate().publicKey;
    const newbie = Keypair.generate().publicKey;
    prisma.walletAccount.findMany.mockResolvedValue([
      { userId: 7, publicKey: already.toBase58() },
      { userId: 8, publicKey: newbie.toBase58() },
    ]);
    solana.program.account.tripVault.fetch.mockResolvedValue({
      members: [{ owner: already, active: true }],
    });
    const service = makeService(deps);

    const added = await service.syncMembers(42);

    expect(added).toBe(1);
    expect(solana.sendAsFeePayer).toHaveBeenCalledTimes(1);
  });
});
