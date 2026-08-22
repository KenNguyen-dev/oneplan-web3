-- CreateEnum
CREATE TYPE "oneplandb"."currency_type" AS ENUM ('USD', 'EUR', 'VND', 'THB', 'KRW', 'JPY', 'CNY', 'TWD', 'SGD', 'MYR');

-- AlterTable
ALTER TABLE "oneplandb"."user" ADD COLUMN     "preferred_currency" "oneplandb"."currency_type" NOT NULL DEFAULT 'USD';

-- AlterTable
ALTER TABLE "oneplandb"."trip" ADD COLUMN     "currency" "oneplandb"."currency_type" NOT NULL DEFAULT 'VND';
