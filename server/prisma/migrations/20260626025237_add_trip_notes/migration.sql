-- CreateTable
CREATE TABLE "oneplandb"."trip_note" (
    "id" SERIAL NOT NULL,
    "trip_id" INTEGER NOT NULL,
    "created_by_id" INTEGER NOT NULL,
    "title" VARCHAR(255) NOT NULL,
    "body" VARCHAR(2000),
    "is_done" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_note_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "trip_note_trip_id_idx" ON "oneplandb"."trip_note"("trip_id");

-- CreateIndex
CREATE INDEX "trip_note_created_by_id_idx" ON "oneplandb"."trip_note"("created_by_id");

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_note" ADD CONSTRAINT "trip_note_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "oneplandb"."trip"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_note" ADD CONSTRAINT "trip_note_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "oneplandb"."user"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;
