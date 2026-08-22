import { BadRequestException } from '@nestjs/common';
import { Keypair, PublicKey } from '@solana/web3.js';

import { WalletWithdrawService } from './wallet-withdraw.service';

/**
 * A withdrawal is one transfer and cannot be undone, so what is worth testing
 * is not the transfer but everything that refuses to make one.
 */
function build(overrides: { balanceMicro?: bigint } = {}) {
  const owner = Keypair.generate().publicKey;
  const prisma = {
    walletAccount: {
      findUnique: jest
        .fn()
        .mockResolvedValue({ userId: 7, publicKey: owner.toBase58() }),
    },
  };
  const solana = {
    usdcMint: Keypair.generate().publicKey,
    feePayer: Keypair.generate(),
    connection: {},
    getTokenBalance: jest
      .fn()
      .mockResolvedValue(overrides.balanceMicro ?? 100_000_000n),
    buildUnsignedTx: jest.fn().mockResolvedValue('base64tx'),
  };
  return {
    service: new WalletWithdrawService(prisma as never, solana as never),
    owner,
    solana,
  };
}

describe('WalletWithdrawService', () => {
  // The mistake this refuses by name. USDC sent to an Ethereum address on
  // Solana is gone, and the message has to say which chain the wallet is on.
  it('refuses an Ethereum address', async () => {
    const { service } = build();
    await expect(
      service.buildWithdrawal(7, '0xd35Cd6F11e1Fc6A0E0dC33Db6fF9A2b8fA1eAd3g', 1n),
    ).rejects.toThrow(/Ethereum/);
  });

  it('refuses something that is not an address at all', async () => {
    const { service } = build();
    await expect(service.buildWithdrawal(7, 'hello', 1n)).rejects.toThrow(
      BadRequestException,
    );
  });

  // Off-curve keys belong to programs. Nobody holds their private key, so
  // anything sent there stays there.
  it('refuses a program address', async () => {
    const { service } = build();
    const [pda] = PublicKey.findProgramAddressSync(
      [Buffer.from('seed')],
      Keypair.generate().publicKey,
    );
    await expect(
      service.buildWithdrawal(7, pda.toBase58(), 1n),
    ).rejects.toThrow(BadRequestException);
  });

  it('refuses this wallet as its own recipient', async () => {
    const { service, owner } = build();
    await expect(
      service.buildWithdrawal(7, owner.toBase58(), 1n),
    ).rejects.toThrow(/this wallet/i);
  });

  it('refuses more than the wallet holds', async () => {
    const { service } = build({ balanceMicro: 5_000_000n });
    await expect(
      service.buildWithdrawal(7, Keypair.generate().publicKey.toBase58(), 6_000_000n),
    ).rejects.toThrow(/more than/i);
  });

  it('refuses nothing at all', async () => {
    const { service } = build();
    await expect(
      service.buildWithdrawal(7, Keypair.generate().publicKey.toBase58(), 0n),
    ).rejects.toThrow(BadRequestException);
  });
});
