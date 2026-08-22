-- CreateEnum
CREATE TYPE "oneplandb"."trip_request_status" AS ENUM ('OPEN', 'FULFILLED', 'REJECTED');

-- AlterEnum
ALTER TYPE "oneplandb"."analytics_event_name" ADD VALUE 'TRIP_REQUEST_CREATED';

-- CreateTable
CREATE TABLE "oneplandb"."trip_request" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "city_id" INTEGER,
    "state_id" INTEGER,
    "country_id" INTEGER,
    "tag" "oneplandb"."listing_tag" NOT NULL,
    "budget" DECIMAL(18,2),
    "currency" "oneplandb"."currency_type" NOT NULL DEFAULT 'VND',
    "status" "oneplandb"."trip_request_status" NOT NULL DEFAULT 'OPEN',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_request_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "trip_request_user_id_idx" ON "oneplandb"."trip_request"("user_id");

-- CreateIndex
CREATE INDEX "trip_request_status_idx" ON "oneplandb"."trip_request"("status");

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_request" ADD CONSTRAINT "trip_request_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_request" ADD CONSTRAINT "trip_request_city_id_fkey" FOREIGN KEY ("city_id") REFERENCES "oneplandb"."city"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_request" ADD CONSTRAINT "trip_request_state_id_fkey" FOREIGN KEY ("state_id") REFERENCES "oneplandb"."state"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_request" ADD CONSTRAINT "trip_request_country_id_fkey" FOREIGN KEY ("country_id") REFERENCES "oneplandb"."country"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;
