-- CreateTable
CREATE TABLE "oneplandb"."gift_log" (
    "id" SERIAL NOT NULL,
    "recipient_user_id" INTEGER NOT NULL,
    "recipient_email" VARCHAR(255) NOT NULL,
    "admin_email" VARCHAR(255) NOT NULL,
    "scans" INTEGER NOT NULL DEFAULT 0,
    "package" VARCHAR(32),
    "subscription_expires_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "gift_log_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "gift_log_recipient_user_id_idx" ON "oneplandb"."gift_log"("recipient_user_id");

-- CreateIndex
CREATE INDEX "gift_log_created_at_idx" ON "oneplandb"."gift_log"("created_at");

-- AddForeignKey
ALTER TABLE "oneplandb"."gift_log" ADD CONSTRAINT "gift_log_recipient_user_id_fkey" FOREIGN KEY ("recipient_user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
