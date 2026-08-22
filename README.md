# OnePlan — group trips with a shared on-chain wallet

Group trip planning (itinerary, expenses, bill splitting, chat) plus a **Solana USDC group vault**: members fund a shared wallet, pay merchants via VietQR, approve large spends, and settle at trip end.

```
ios/      SwiftUI app (iOS 17.2+, Xcode 16+)
server/   NestJS + Fastify + Prisma + PostgreSQL API
solana/   Anchor program `oneplan-vault`
```

## Backend

```bash
cd server
pnpm install
pnpm db:up                  # PostgreSQL in Docker on localhost:5433
cp .env.example .env        # create your own — see variables below
pnpm prisma:migrate:dev
pnpm start:dev              # http://localhost:3000 — Swagger at /docs
pnpm test
```

Minimum env vars to boot: `PORT`, `DATABASE_URL`, `JWT_SECRET`, `JWT_REFRESH_SECRET` (≥32 chars each), `APPLE_CLIENT_ID`, `GOOGLE_CLIENT_ID`, `GCS_MEDIA_BUCKET`, `GCS_PUBLIC_BUCKET`, `STORAGE_SA_KEY_FILE`. The Joi config schema (`src/config/`) lists everything else.

Web3 vault vars:

| Var | Purpose |
|---|---|
| `SOLANA_RPC_URL` | `https://api.devnet.solana.com` |
| `SOLANA_PROGRAM_ID` | `8pjmDZvmRzjcSwzffqnsdzsPRb3nV9BiVDhGU3vmR7uD` (devnet) |
| `SOLANA_USDC_MINT` | `4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU` (devnet USDC) |
| `SOLANA_COMMITMENT` | `confirmed` |
| `SOLANA_FEE_PAYER_SECRET_KEY` | base58 key of the server fee payer; empty disables vault endpoints |
| `SOLANA_RECEIVER_SECRET_KEY` | mock merchant receiver (phase 1) |
| `MOCK_PAYOUT_OUTCOME` | `success \| failed \| timeout \| unknown` |
| `WALLET_JWT_PRIVATE_KEY_FILE` | PEM used to sign embedded-wallet JWTs |

`scripts/setup-solana-devnet.mjs` generates a fee-payer keypair and airdrops devnet SOL.

## iOS

Open `ios/OnePlan/OnePlan.xcodeproj`, select the `OnePlan` scheme, build for a simulator. The API client is generated at build time by the swift-openapi-generator plugin from `OnePlan/OpenAPI/openapi.json`.

`GoogleService-Info.plist` is not included — add your own Firebase/Google config to enable Google Sign-In; Apple Sign-In and email work without it.

## Solana program

```bash
cd solana
anchor build
cargo test            # unit + attack/invariant tests in programs/oneplan-vault/tests
```

Deployed on devnet at `8pjmDZvmRzjcSwzffqnsdzsPRb3nV9BiVDhGU3vmR7uD`. The IDL and TS types are committed under `server/src/solana/idl/` and `server/src/solana/types/` (`server/scripts/sync-idl.sh` refreshes them after a build).

### Vault design

One `TripVault` PDA + its USDC ATA per trip — no per-member or per-proposal accounts.

| Role | On-chain |
|---|---|
| HOST | `authority` (trip creator); approver |
| CO_HOST | approver bit |
| MEMBER | deposit / spend; approves only when no HOST+CO_HOST pair exists |

| Action | On-chain |
|---|---|
| Enable group wallet / first deposit | `init_vault` + seed members + deposit (0.1% fee → treasury) |
| Pay ≤ threshold | `spend` within daily limit |
| Pay > threshold | `active_spend` proposal → second approval → transfer |
| End trip | settlement → `Settling` → 2 approvals → payouts → `Closed` |
| Member leaves mid-trip | `payout_leave` refund |
| After close | server `close_vault` reclaims rent |

Users never hold SOL; the server pays rent and tx fees.

### Mocked in this build

| What | Now | Where |
|---|---|---|
| QR scan | photo library | `VaultScanQRView.swift` |
| Merchant payout | always SUCCESS | `mock-payout.provider.ts` |
| FX | `VND_PER_USDC = 26_500` | `mock-payout.provider.ts` |
| Quote fee | `FEE_BPS = 75` | `mock-payout.provider.ts` |
| Approval threshold | 3 USDC | `trips.service.ts` |
