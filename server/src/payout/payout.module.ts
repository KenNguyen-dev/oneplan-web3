import { Module } from '@nestjs/common';

import { MockPayoutProvider } from './mock-payout.provider';
import { PAYOUT_PROVIDER } from './payout-provider.interface';

/**
 * Phase 1 binds the mock. Phase 2 swaps the binding for FinFanPayoutProvider;
 * nothing that injects PAYOUT_PROVIDER changes.
 */
@Module({
  providers: [
    MockPayoutProvider,
    { provide: PAYOUT_PROVIDER, useExisting: MockPayoutProvider },
  ],
  exports: [PAYOUT_PROVIDER],
})
export class PayoutModule {}
