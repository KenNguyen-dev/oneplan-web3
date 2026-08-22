-- CreateEnum
CREATE TYPE "oneplandb"."FareWatchStatus" AS ENUM ('ACTIVE', 'PAUSED', 'TRIGGERED', 'EXPIRED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "oneplandb"."FareTripType" AS ENUM ('ONE_WAY', 'ROUND_TRIP');

-- CreateEnum
CREATE TYPE "oneplandb"."FareAlertChannel" AS ENUM ('ZNS', 'PUSH', 'BOTH');

-- CreateTable
CREATE TABLE "oneplandb"."fare_watch_order" (
    "id" SERIAL NOT NULL,
    "public_id" TEXT NOT NULL,
    "user_id" INTEGER,
    "phone" VARCHAR(16),
    "phone_verified" BOOLEAN NOT NULL DEFAULT false,
    "otp_hash" VARCHAR(64),
    "otp_expires_at" TIMESTAMPTZ(6),
    "otp_attempts" INTEGER NOT NULL DEFAULT 0,
    "origin" VARCHAR(3) NOT NULL,
    "destination" VARCHAR(3) NOT NULL,
    "trip_type" "oneplandb"."FareTripType" NOT NULL DEFAULT 'ONE_WAY',
    "date_from" DATE NOT NULL,
    "date_to" DATE NOT NULL,
    "return_from" DATE,
    "return_to" DATE,
    "target_price" INTEGER,
    "auto_target" BOOLEAN NOT NULL DEFAULT false,
    "channel" "oneplandb"."FareAlertChannel" NOT NULL DEFAULT 'ZNS',
    "trip_id" INTEGER,
    "status" "oneplandb"."FareWatchStatus" NOT NULL DEFAULT 'ACTIVE',
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "last_notified_at" TIMESTAMPTZ(6),
    "last_notified_price" INTEGER,
    "notify_count" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "fare_watch_order_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."fare_quote" (
    "id" SERIAL NOT NULL,
    "origin" VARCHAR(3) NOT NULL,
    "destination" VARCHAR(3) NOT NULL,
    "depart_date" DATE NOT NULL,
    "return_date" DATE,
    "airline" VARCHAR(8) NOT NULL,
    "price" INTEGER NOT NULL,
    "source" VARCHAR(24) NOT NULL,
    "deep_link" TEXT,
    "fetched_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "fare_quote_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."fare_alert_log" (
    "id" SERIAL NOT NULL,
    "order_id" INTEGER NOT NULL,
    "quote_id" INTEGER,
    "price" INTEGER NOT NULL,
    "channel" "oneplandb"."FareAlertChannel" NOT NULL,
    "zns_msg_id" VARCHAR(64),
    "status" VARCHAR(16) NOT NULL,
    "sent_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "clicked_at" TIMESTAMPTZ(6),

    CONSTRAINT "fare_alert_log_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."zalo_oauth_token" (
    "id" INTEGER NOT NULL DEFAULT 1,
    "access_token" TEXT NOT NULL,
    "refresh_token" TEXT NOT NULL,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "zalo_oauth_token_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "fare_watch_order_public_id_key" ON "oneplandb"."fare_watch_order"("public_id");

-- CreateIndex
CREATE INDEX "fare_watch_order_status_expires_at_idx" ON "oneplandb"."fare_watch_order"("status", "expires_at");

-- CreateIndex
CREATE INDEX "fare_watch_order_origin_destination_date_from_idx" ON "oneplandb"."fare_watch_order"("origin", "destination", "date_from");

-- CreateIndex
CREATE INDEX "fare_watch_order_user_id_idx" ON "oneplandb"."fare_watch_order"("user_id");

-- CreateIndex
CREATE INDEX "fare_watch_order_phone_idx" ON "oneplandb"."fare_watch_order"("phone");

-- CreateIndex
CREATE INDEX "fare_quote_origin_destination_depart_date_fetched_at_idx" ON "oneplandb"."fare_quote"("origin", "destination", "depart_date", "fetched_at");

-- CreateIndex
CREATE INDEX "fare_alert_log_order_id_sent_at_idx" ON "oneplandb"."fare_alert_log"("order_id", "sent_at");

-- AddForeignKey
ALTER TABLE "oneplandb"."fare_alert_log" ADD CONSTRAINT "fare_alert_log_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "oneplandb"."fare_watch_order"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "oneplandb"."fare_alert_log" ADD CONSTRAINT "fare_alert_log_quote_id_fkey" FOREIGN KEY ("quote_id") REFERENCES "oneplandb"."fare_quote"("id") ON DELETE SET NULL ON UPDATE CASCADE;

