-- CreateTable
CREATE TABLE "oneplandb"."recent_location" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "name" VARCHAR(255) NOT NULL,
    "address" VARCHAR(500) NOT NULL DEFAULT '',
    "latitude" DECIMAL(10,8),
    "longitude" DECIMAL(11,8),
    "last_viewed_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "recent_location_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "recent_location_user_id_last_viewed_at_idx" ON "oneplandb"."recent_location"("user_id", "last_viewed_at");

-- CreateIndex
CREATE UNIQUE INDEX "recent_location_user_id_name_address_key" ON "oneplandb"."recent_location"("user_id", "name", "address");

-- AddForeignKey
ALTER TABLE "oneplandb"."recent_location" ADD CONSTRAINT "recent_location_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE CASCADE;
