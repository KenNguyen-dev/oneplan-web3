/*
  Warnings:

  - A unique constraint covering the columns `[friend_code]` on the table `user` will be added. If there are existing duplicate values, this will fail.

*/
-- CreateEnum
CREATE TYPE "oneplandb"."friend_request_status" AS ENUM ('PENDING', 'DECLINED');

-- AlterTable
ALTER TABLE "oneplandb"."user" ADD COLUMN     "friend_code" VARCHAR(64);

-- CreateTable
CREATE TABLE "oneplandb"."friend_request" (
    "id" SERIAL NOT NULL,
    "sender_id" INTEGER NOT NULL,
    "receiver_id" INTEGER NOT NULL,
    "status" "oneplandb"."friend_request_status" NOT NULL DEFAULT 'PENDING',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "friend_request_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."friendship" (
    "id" SERIAL NOT NULL,
    "user_a_id" INTEGER NOT NULL,
    "user_b_id" INTEGER NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "friendship_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "friend_request_sender_id_idx" ON "oneplandb"."friend_request"("sender_id");

-- CreateIndex
CREATE INDEX "friend_request_receiver_id_idx" ON "oneplandb"."friend_request"("receiver_id");

-- CreateIndex
CREATE UNIQUE INDEX "friend_request_sender_id_receiver_id_key" ON "oneplandb"."friend_request"("sender_id", "receiver_id");

-- CreateIndex
CREATE INDEX "friendship_user_a_id_idx" ON "oneplandb"."friendship"("user_a_id");

-- CreateIndex
CREATE INDEX "friendship_user_b_id_idx" ON "oneplandb"."friendship"("user_b_id");

-- CreateIndex
CREATE UNIQUE INDEX "friendship_user_a_id_user_b_id_key" ON "oneplandb"."friendship"("user_a_id", "user_b_id");

-- CreateIndex
CREATE UNIQUE INDEX "user_friend_code_key" ON "oneplandb"."user"("friend_code");

-- AddForeignKey
ALTER TABLE "oneplandb"."friend_request" ADD CONSTRAINT "friend_request_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."friend_request" ADD CONSTRAINT "friend_request_receiver_id_fkey" FOREIGN KEY ("receiver_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."friendship" ADD CONSTRAINT "friendship_user_a_id_fkey" FOREIGN KEY ("user_a_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."friendship" ADD CONSTRAINT "friendship_user_b_id_fkey" FOREIGN KEY ("user_b_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
