-- CreateEnum
CREATE TYPE "oneplandb"."journal_label" AS ENUM ('TRIP_PLAN', 'JOURNAL', 'INTERVIEW');

-- CreateEnum
CREATE TYPE "oneplandb"."journal_status" AS ENUM ('DRAFT', 'PUBLISHED');

-- CreateTable
CREATE TABLE "oneplandb"."journal" (
    "id" SERIAL NOT NULL,
    "slug" VARCHAR(255) NOT NULL,
    "title" VARCHAR(255) NOT NULL,
    "label" "oneplandb"."journal_label" NOT NULL,
    "excerpt" VARCHAR(500),
    "content" TEXT NOT NULL,
    "cover_image_key" VARCHAR(500),
    "status" "oneplandb"."journal_status" NOT NULL DEFAULT 'DRAFT',
    "published_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "journal_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "journal_slug_key" ON "oneplandb"."journal"("slug");
