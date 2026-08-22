-- CreateEnum
CREATE TYPE "oneplandb"."PinExtractionStatus" AS ENUM ('QUEUED', 'RUNNING', 'DONE', 'FAILED', 'CANCELLED');

-- CreateTable
CREATE TABLE "oneplandb"."pin_extraction_session" (
    "id" TEXT NOT NULL,
    "user_id" INTEGER NOT NULL,
    "source_url" VARCHAR(1000) NOT NULL,
    "url_hash" VARCHAR(64) NOT NULL,
    "status" "oneplandb"."PinExtractionStatus" NOT NULL DEFAULT 'QUEUED',
    "phase" VARCHAR(32),
    "video_meta" JSONB,
    "pins" JSONB NOT NULL DEFAULT '[]',
    "from_cache" BOOLEAN NOT NULL DEFAULT false,
    "error_code" VARCHAR(64),
    "error_message" VARCHAR(500),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,
    "completed_at" TIMESTAMPTZ(6),
    "dismissed_at" TIMESTAMPTZ(6),

    CONSTRAINT "pin_extraction_session_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "pin_extraction_session_user_id_status_idx" ON "oneplandb"."pin_extraction_session"("user_id", "status");

-- CreateIndex
CREATE INDEX "pin_extraction_session_user_id_dismissed_at_idx" ON "oneplandb"."pin_extraction_session"("user_id", "dismissed_at");

-- AddForeignKey
ALTER TABLE "oneplandb"."pin_extraction_session" ADD CONSTRAINT "pin_extraction_session_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
