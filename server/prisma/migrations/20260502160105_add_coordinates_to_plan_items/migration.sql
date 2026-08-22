-- AlterTable
ALTER TABLE "oneplandb"."acquisition_item" ADD COLUMN     "address" VARCHAR(500),
ADD COLUMN     "latitude" DOUBLE PRECISION,
ADD COLUMN     "longitude" DOUBLE PRECISION;

-- AlterTable
ALTER TABLE "oneplandb"."trip_plan_item" ADD COLUMN     "address" VARCHAR(500),
ADD COLUMN     "latitude" DOUBLE PRECISION,
ADD COLUMN     "longitude" DOUBLE PRECISION;

-- AlterTable
ALTER TABLE "oneplandb"."trip_plan_market_item" ADD COLUMN     "address" VARCHAR(500),
ADD COLUMN     "latitude" DOUBLE PRECISION,
ADD COLUMN     "longitude" DOUBLE PRECISION;
