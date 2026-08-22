-- CreateTable
CREATE TABLE "oneplandb"."device_token" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "token" VARCHAR(200) NOT NULL,
    "platform" VARCHAR(10) NOT NULL DEFAULT 'ios',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "device_token_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "device_token_token_key" ON "oneplandb"."device_token"("token");

-- CreateIndex
CREATE INDEX "device_token_user_id_idx" ON "oneplandb"."device_token"("user_id");

-- AddForeignKey
ALTER TABLE "oneplandb"."device_token" ADD CONSTRAINT "device_token_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE CASCADE;
