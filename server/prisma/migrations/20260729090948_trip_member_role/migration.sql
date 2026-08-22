-- CreateEnum
CREATE TYPE "oneplandb"."TripMemberRole" AS ENUM ('LEADER', 'CO_LEADER', 'MEMBER');

-- AlterTable
ALTER TABLE "oneplandb"."trip_member" ADD COLUMN     "role" "oneplandb"."TripMemberRole" NOT NULL DEFAULT 'MEMBER';
