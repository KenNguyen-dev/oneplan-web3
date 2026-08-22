-- AlterTable
ALTER TABLE "trip_member" ADD COLUMN "vault_leave_requested_at" TIMESTAMPTZ(6),
ADD COLUMN "vault_leave_request_net_micro" BIGINT;
