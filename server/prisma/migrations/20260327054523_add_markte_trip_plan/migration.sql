-- CreateTable
CREATE TABLE "oneplandb"."trip_plan_market_item" (
    "id" SERIAL NOT NULL,
    "created_by_id" INTEGER NOT NULL,
    "plan_date" DATE NOT NULL,
    "title" VARCHAR(255) NOT NULL,
    "description" VARCHAR(500),
    "location" VARCHAR(500),
    "start_time" VARCHAR(5),
    "category" "oneplandb"."expense_category",
    "image_urls" TEXT[],
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_plan_market_item_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "trip_plan_market_item_created_by_id_idx" ON "oneplandb"."trip_plan_market_item"("created_by_id");

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_plan_market_item" ADD CONSTRAINT "trip_plan_market_item_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "oneplandb"."user"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;
