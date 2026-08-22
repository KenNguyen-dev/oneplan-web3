-- AlterTable
ALTER TABLE "oneplandb"."budget" ADD COLUMN     "exchange_rate" DECIMAL(18,8),
ADD COLUMN     "original_amount" DECIMAL(18,2),
ADD COLUMN     "original_currency" "oneplandb"."currency_type";

-- AlterTable
ALTER TABLE "oneplandb"."expense" ADD COLUMN     "exchange_rate" DECIMAL(18,8),
ADD COLUMN     "original_amount" DECIMAL(18,2),
ADD COLUMN     "original_currency" "oneplandb"."currency_type";

-- AlterTable
ALTER TABLE "oneplandb"."trip" ADD COLUMN     "local_currencies" "oneplandb"."currency_type"[] DEFAULT ARRAY[]::"oneplandb"."currency_type"[];

-- CreateTable
CREATE TABLE "oneplandb"."exchange_rates" (
    "id" SERIAL NOT NULL,
    "from_currency" "oneplandb"."currency_type" NOT NULL,
    "to_currency" "oneplandb"."currency_type" NOT NULL,
    "rate" DECIMAL(18,8) NOT NULL,
    "fetched_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "source" VARCHAR(64) NOT NULL DEFAULT 'exchangerate-api.com',

    CONSTRAINT "exchange_rates_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "exchange_rates_from_currency_to_currency_fetched_at_idx" ON "oneplandb"."exchange_rates"("from_currency", "to_currency", "fetched_at");

-- CreateIndex
CREATE UNIQUE INDEX "exchange_rates_from_currency_to_currency_key" ON "oneplandb"."exchange_rates"("from_currency", "to_currency");
