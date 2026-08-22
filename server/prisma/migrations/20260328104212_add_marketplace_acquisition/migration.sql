-- CreateEnum
CREATE TYPE "oneplandb"."payment_status" AS ENUM ('PENDING', 'COMPLETED', 'REFUNDED', 'FAILED');

-- CreateTable
CREATE TABLE "oneplandb"."marketplace_acquisition" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "listing_id" INTEGER NOT NULL,
    "acquired_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "marketplace_acquisition_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."marketplace_payment" (
    "id" SERIAL NOT NULL,
    "acquisition_id" INTEGER NOT NULL,
    "amount" DECIMAL(18,2) NOT NULL,
    "currency" VARCHAR(3) NOT NULL DEFAULT 'VND',
    "transaction_id" VARCHAR(255),
    "status" "oneplandb"."payment_status" NOT NULL DEFAULT 'COMPLETED',
    "paid_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "marketplace_payment_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "marketplace_acquisition_user_id_idx" ON "oneplandb"."marketplace_acquisition"("user_id");

-- CreateIndex
CREATE INDEX "marketplace_acquisition_listing_id_idx" ON "oneplandb"."marketplace_acquisition"("listing_id");

-- CreateIndex
CREATE UNIQUE INDEX "marketplace_acquisition_user_id_listing_id_key" ON "oneplandb"."marketplace_acquisition"("user_id", "listing_id");

-- CreateIndex
CREATE UNIQUE INDEX "marketplace_payment_acquisition_id_key" ON "oneplandb"."marketplace_payment"("acquisition_id");

-- CreateIndex
CREATE INDEX "marketplace_payment_acquisition_id_idx" ON "oneplandb"."marketplace_payment"("acquisition_id");

-- AddForeignKey
ALTER TABLE "oneplandb"."marketplace_acquisition" ADD CONSTRAINT "marketplace_acquisition_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."marketplace_acquisition" ADD CONSTRAINT "marketplace_acquisition_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "oneplandb"."marketplace_listing"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."marketplace_payment" ADD CONSTRAINT "marketplace_payment_acquisition_id_fkey" FOREIGN KEY ("acquisition_id") REFERENCES "oneplandb"."marketplace_acquisition"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
