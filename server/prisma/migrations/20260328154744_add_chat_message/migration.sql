-- CreateTable
CREATE TABLE "oneplandb"."chat_message" (
    "id" SERIAL NOT NULL,
    "trip_id" INTEGER NOT NULL,
    "sender_id" INTEGER NOT NULL,
    "content" VARCHAR(2000) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "chat_message_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "chat_message_trip_id_created_at_idx" ON "oneplandb"."chat_message"("trip_id", "created_at");

-- CreateIndex
CREATE INDEX "chat_message_trip_id_id_idx" ON "oneplandb"."chat_message"("trip_id", "id");

-- CreateIndex
CREATE INDEX "chat_message_sender_id_idx" ON "oneplandb"."chat_message"("sender_id");

-- AddForeignKey
ALTER TABLE "oneplandb"."chat_message" ADD CONSTRAINT "chat_message_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "oneplandb"."trip"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."chat_message" ADD CONSTRAINT "chat_message_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "oneplandb"."user"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;
