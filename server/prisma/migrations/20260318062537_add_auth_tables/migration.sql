/*
  Warnings:

  - Made the column `created_at` on table `user` required. This step will fail if there are existing NULL values in that column.

*/
-- CreateEnum
CREATE TYPE "oneplandb"."auth_provider" AS ENUM ('EMAIL', 'APPLE', 'GOOGLE');

-- AlterTable
ALTER TABLE "oneplandb"."user" ALTER COLUMN "created_at" SET NOT NULL,
ALTER COLUMN "created_at" SET DEFAULT CURRENT_TIMESTAMP;

-- CreateTable
CREATE TABLE "oneplandb"."auth_account" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "provider" "oneplandb"."auth_provider" NOT NULL,
    "provider_user_id" VARCHAR(255) NOT NULL,
    "password_hash" VARCHAR(255),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "auth_account_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."refresh_token" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "jti" VARCHAR(36) NOT NULL,
    "family" VARCHAR(36) NOT NULL,
    "is_revoked" BOOLEAN NOT NULL DEFAULT false,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "refresh_token_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "auth_account_user_id_idx" ON "oneplandb"."auth_account"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "auth_account_provider_provider_user_id_key" ON "oneplandb"."auth_account"("provider", "provider_user_id");

-- CreateIndex
CREATE UNIQUE INDEX "refresh_token_jti_key" ON "oneplandb"."refresh_token"("jti");

-- CreateIndex
CREATE INDEX "refresh_token_user_id_idx" ON "oneplandb"."refresh_token"("user_id");

-- CreateIndex
CREATE INDEX "refresh_token_family_idx" ON "oneplandb"."refresh_token"("family");

-- AddForeignKey
ALTER TABLE "oneplandb"."auth_account" ADD CONSTRAINT "auth_account_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."refresh_token" ADD CONSTRAINT "refresh_token_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
