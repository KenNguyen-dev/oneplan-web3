-- CreateTable
CREATE TABLE "oneplandb"."video_extraction_usage" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "session_id" TEXT NOT NULL,
    "tier" VARCHAR(32) NOT NULL,
    "consumed_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "refunded_at" TIMESTAMPTZ(6),

    CONSTRAINT "video_extraction_usage_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "video_extraction_usage_session_id_key" ON "oneplandb"."video_extraction_usage"("session_id");

-- CreateIndex
CREATE INDEX "video_extraction_usage_user_id_consumed_at_idx" ON "oneplandb"."video_extraction_usage"("user_id", "consumed_at");

-- CreateIndex
CREATE INDEX "video_extraction_usage_user_id_refunded_at_idx" ON "oneplandb"."video_extraction_usage"("user_id", "refunded_at");

-- AddForeignKey
ALTER TABLE "oneplandb"."video_extraction_usage" ADD CONSTRAINT "video_extraction_usage_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."video_extraction_usage" ADD CONSTRAINT "video_extraction_usage_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "oneplandb"."pin_extraction_session"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
