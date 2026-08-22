-- CreateTable
CREATE TABLE "oneplandb"."deleted_user_archive" (
    "id" SERIAL NOT NULL,
    "original_user_id" INTEGER NOT NULL,
    "email" VARCHAR(255) NOT NULL,
    "display_name" VARCHAR(255) NOT NULL,
    "snapshot" JSONB NOT NULL,
    "deleted_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "deleted_user_archive_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "deleted_user_archive_deleted_at_idx" ON "oneplandb"."deleted_user_archive"("deleted_at");

-- CreateIndex
CREATE INDEX "deleted_user_archive_email_idx" ON "oneplandb"."deleted_user_archive"("email");
