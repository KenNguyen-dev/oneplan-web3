-- AlterTable
ALTER TABLE "oneplandb"."board" ADD COLUMN     "city_id" INTEGER,
ADD COLUMN     "country_id" INTEGER,
ADD COLUMN     "cover_image_url" VARCHAR(500),
ADD COLUMN     "state_id" INTEGER;

-- CreateIndex
CREATE INDEX "board_city_id_idx" ON "oneplandb"."board"("city_id");

-- CreateIndex
CREATE INDEX "board_state_id_idx" ON "oneplandb"."board"("state_id");

-- CreateIndex
CREATE INDEX "board_country_id_idx" ON "oneplandb"."board"("country_id");

-- AddForeignKey
ALTER TABLE "oneplandb"."board" ADD CONSTRAINT "board_city_id_fkey" FOREIGN KEY ("city_id") REFERENCES "oneplandb"."city"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."board" ADD CONSTRAINT "board_state_id_fkey" FOREIGN KEY ("state_id") REFERENCES "oneplandb"."state"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."board" ADD CONSTRAINT "board_country_id_fkey" FOREIGN KEY ("country_id") REFERENCES "oneplandb"."country"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;
