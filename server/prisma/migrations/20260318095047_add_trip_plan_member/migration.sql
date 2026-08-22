-- CreateTable
CREATE TABLE "oneplandb"."trip_plan_item_member" (
    "id" SERIAL NOT NULL,
    "trip_plan_item_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "created_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_plan_item_member_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "trip_plan_item_member_trip_plan_item_id_idx" ON "oneplandb"."trip_plan_item_member"("trip_plan_item_id");

-- CreateIndex
CREATE INDEX "trip_plan_item_member_user_id_idx" ON "oneplandb"."trip_plan_item_member"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "trip_plan_item_member_trip_plan_item_id_user_id_key" ON "oneplandb"."trip_plan_item_member"("trip_plan_item_id", "user_id");

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_plan_item_member" ADD CONSTRAINT "trip_plan_item_member_trip_plan_item_id_fkey" FOREIGN KEY ("trip_plan_item_id") REFERENCES "oneplandb"."trip_plan_item"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_plan_item_member" ADD CONSTRAINT "trip_plan_item_member_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
