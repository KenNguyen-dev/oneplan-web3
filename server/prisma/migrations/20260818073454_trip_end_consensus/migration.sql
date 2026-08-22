-- CreateEnum
CREATE TYPE "oneplandb"."trip_end_request_status" AS ENUM ('PENDING', 'APPROVED', 'DENIED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "oneplandb"."trip_end_vote_decision" AS ENUM ('APPROVED', 'DENIED');

-- CreateTable
CREATE TABLE "oneplandb"."trip_end_request" (
    "id" SERIAL NOT NULL,
    "trip_id" INTEGER NOT NULL,
    "requested_by" INTEGER NOT NULL,
    "status" "oneplandb"."trip_end_request_status" NOT NULL DEFAULT 'PENDING',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolved_at" TIMESTAMPTZ(6),

    CONSTRAINT "trip_end_request_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."trip_end_vote" (
    "id" SERIAL NOT NULL,
    "request_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "decision" "oneplandb"."trip_end_vote_decision" NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_end_vote_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "trip_end_request_trip_id_key" ON "oneplandb"."trip_end_request"("trip_id");

-- CreateIndex
CREATE INDEX "trip_end_request_status_idx" ON "oneplandb"."trip_end_request"("status");

-- CreateIndex
CREATE INDEX "trip_end_vote_user_id_idx" ON "oneplandb"."trip_end_vote"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "trip_end_vote_request_id_user_id_key" ON "oneplandb"."trip_end_vote"("request_id", "user_id");

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_end_request" ADD CONSTRAINT "trip_end_request_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "oneplandb"."trip"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_end_request" ADD CONSTRAINT "trip_end_request_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_end_vote" ADD CONSTRAINT "trip_end_vote_request_id_fkey" FOREIGN KEY ("request_id") REFERENCES "oneplandb"."trip_end_request"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_end_vote" ADD CONSTRAINT "trip_end_vote_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
