-- CreateEnum
CREATE TYPE "oneplandb"."trip_status" AS ENUM ('PLANNING', 'ONGOING', 'ENDED');

-- CreateEnum
CREATE TYPE "oneplandb"."invite_status" AS ENUM ('PENDING', 'ACCEPTED', 'DECLINED');

-- CreateEnum
CREATE TYPE "oneplandb"."expense_category" AS ENUM ('FOOD', 'STAY', 'TICKET', 'PLANE', 'OTHER');

-- CreateEnum
CREATE TYPE "oneplandb"."plan_scope" AS ENUM ('GROUP', 'PERSONAL');

-- CreateEnum
CREATE TYPE "oneplandb"."activity_action" AS ENUM ('TRIP_CREATED', 'TRIP_UPDATED', 'TRIP_ENDED', 'MEMBER_INVITED', 'MEMBER_JOINED', 'MEMBER_REMOVED', 'BUDGET_CREATED', 'BUDGET_UPDATED', 'BUDGET_DELETED', 'BUDGET_PAID', 'EXPENSE_CREATED', 'EXPENSE_UPDATED', 'EXPENSE_DELETED', 'EXPENSE_SETTLED', 'PLAN_ITEM_CREATED', 'PLAN_ITEM_UPDATED', 'PLAN_ITEM_DELETED', 'PHOTO_UPLOADED');

-- CreateTable
CREATE TABLE "oneplandb"."user" (
    "id" SERIAL NOT NULL,
    "email" VARCHAR(255) NOT NULL,
    "display_name" VARCHAR(100) NOT NULL,
    "avatar_url" VARCHAR(500),
    "created_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."trip" (
    "id" SERIAL NOT NULL,
    "name" VARCHAR(255) NOT NULL,
    "cover_image_url" VARCHAR(500),
    "status" "oneplandb"."trip_status" NOT NULL DEFAULT 'PLANNING',
    "start_date" DATE,
    "end_date" DATE,
    "invite_code" VARCHAR(64),
    "created_by_id" INTEGER NOT NULL,
    "city_id" INTEGER,
    "state_id" INTEGER,
    "country_id" INTEGER,
    "created_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."trip_member" (
    "id" SERIAL NOT NULL,
    "trip_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "invite_status" "oneplandb"."invite_status" NOT NULL DEFAULT 'PENDING',
    "joined_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_member_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."budget" (
    "id" SERIAL NOT NULL,
    "trip_id" INTEGER NOT NULL,
    "name" VARCHAR(255) NOT NULL,
    "amount" DECIMAL(18,2) NOT NULL,
    "per_person_amount" DECIMAL(18,2),
    "scope" "oneplandb"."plan_scope" NOT NULL DEFAULT 'GROUP',
    "created_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "budget_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."budget_payment" (
    "id" SERIAL NOT NULL,
    "budget_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "amount" DECIMAL(18,2) NOT NULL,
    "is_paid" BOOLEAN NOT NULL DEFAULT false,
    "paid_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "budget_payment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."expense" (
    "id" SERIAL NOT NULL,
    "trip_id" INTEGER NOT NULL,
    "paid_by_id" INTEGER NOT NULL,
    "name" VARCHAR(255) NOT NULL,
    "amount" DECIMAL(18,2) NOT NULL,
    "category" "oneplandb"."expense_category" NOT NULL DEFAULT 'OTHER',
    "scope" "oneplandb"."plan_scope" NOT NULL DEFAULT 'GROUP',
    "note" VARCHAR(500),
    "receipt_url" VARCHAR(500),
    "expense_date" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "expense_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."expense_share" (
    "id" SERIAL NOT NULL,
    "expense_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "share_amount" DECIMAL(18,2) NOT NULL,
    "is_settled" BOOLEAN NOT NULL DEFAULT false,
    "settled_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "expense_share_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."trip_plan_item" (
    "id" SERIAL NOT NULL,
    "trip_id" INTEGER NOT NULL,
    "plan_date" DATE NOT NULL,
    "title" VARCHAR(255) NOT NULL,
    "description" VARCHAR(500),
    "location" VARCHAR(500),
    "start_time" VARCHAR(5),
    "category" "oneplandb"."expense_category",
    "notes" TEXT[],
    "voice_url" VARCHAR(500),
    "voice_duration" INTEGER,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_plan_item_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."trip_photo" (
    "id" SERIAL NOT NULL,
    "trip_id" INTEGER NOT NULL,
    "uploaded_by_id" INTEGER NOT NULL,
    "photo_url" VARCHAR(500) NOT NULL,
    "caption" VARCHAR(255),
    "created_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "trip_photo_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."trip_activity" (
    "id" SERIAL NOT NULL,
    "trip_id" INTEGER NOT NULL,
    "user_id" INTEGER NOT NULL,
    "action" "oneplandb"."activity_action" NOT NULL,
    "target_id" INTEGER,
    "metadata" JSONB,
    "created_at" TIMESTAMPTZ(6),

    CONSTRAINT "trip_activity_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "user_email_key" ON "oneplandb"."user"("email");

-- CreateIndex
CREATE UNIQUE INDEX "trip_invite_code_key" ON "oneplandb"."trip"("invite_code");

-- CreateIndex
CREATE INDEX "trip_created_by_id_idx" ON "oneplandb"."trip"("created_by_id");

-- CreateIndex
CREATE INDEX "trip_city_id_idx" ON "oneplandb"."trip"("city_id");

-- CreateIndex
CREATE INDEX "trip_state_id_idx" ON "oneplandb"."trip"("state_id");

-- CreateIndex
CREATE INDEX "trip_country_id_idx" ON "oneplandb"."trip"("country_id");

-- CreateIndex
CREATE INDEX "trip_status_idx" ON "oneplandb"."trip"("status");

-- CreateIndex
CREATE INDEX "trip_member_trip_id_idx" ON "oneplandb"."trip_member"("trip_id");

-- CreateIndex
CREATE INDEX "trip_member_user_id_idx" ON "oneplandb"."trip_member"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "trip_member_trip_id_user_id_key" ON "oneplandb"."trip_member"("trip_id", "user_id");

-- CreateIndex
CREATE INDEX "budget_trip_id_idx" ON "oneplandb"."budget"("trip_id");

-- CreateIndex
CREATE INDEX "budget_payment_budget_id_idx" ON "oneplandb"."budget_payment"("budget_id");

-- CreateIndex
CREATE INDEX "budget_payment_user_id_idx" ON "oneplandb"."budget_payment"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "budget_payment_budget_id_user_id_key" ON "oneplandb"."budget_payment"("budget_id", "user_id");

-- CreateIndex
CREATE INDEX "expense_trip_id_idx" ON "oneplandb"."expense"("trip_id");

-- CreateIndex
CREATE INDEX "expense_paid_by_id_idx" ON "oneplandb"."expense"("paid_by_id");

-- CreateIndex
CREATE INDEX "expense_category_idx" ON "oneplandb"."expense"("category");

-- CreateIndex
CREATE INDEX "expense_expense_date_idx" ON "oneplandb"."expense"("expense_date");

-- CreateIndex
CREATE INDEX "expense_share_expense_id_idx" ON "oneplandb"."expense_share"("expense_id");

-- CreateIndex
CREATE INDEX "expense_share_user_id_idx" ON "oneplandb"."expense_share"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "expense_share_expense_id_user_id_key" ON "oneplandb"."expense_share"("expense_id", "user_id");

-- CreateIndex
CREATE INDEX "trip_plan_item_trip_id_idx" ON "oneplandb"."trip_plan_item"("trip_id");

-- CreateIndex
CREATE INDEX "trip_plan_item_trip_id_plan_date_idx" ON "oneplandb"."trip_plan_item"("trip_id", "plan_date");

-- CreateIndex
CREATE INDEX "trip_photo_trip_id_idx" ON "oneplandb"."trip_photo"("trip_id");

-- CreateIndex
CREATE INDEX "trip_photo_uploaded_by_id_idx" ON "oneplandb"."trip_photo"("uploaded_by_id");

-- CreateIndex
CREATE INDEX "trip_activity_trip_id_idx" ON "oneplandb"."trip_activity"("trip_id");

-- CreateIndex
CREATE INDEX "trip_activity_user_id_idx" ON "oneplandb"."trip_activity"("user_id");

-- CreateIndex
CREATE INDEX "trip_activity_trip_id_created_at_idx" ON "oneplandb"."trip_activity"("trip_id", "created_at");

-- AddForeignKey
ALTER TABLE "oneplandb"."trip" ADD CONSTRAINT "trip_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "oneplandb"."user"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip" ADD CONSTRAINT "trip_city_id_fkey" FOREIGN KEY ("city_id") REFERENCES "oneplandb"."city"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip" ADD CONSTRAINT "trip_state_id_fkey" FOREIGN KEY ("state_id") REFERENCES "oneplandb"."state"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip" ADD CONSTRAINT "trip_country_id_fkey" FOREIGN KEY ("country_id") REFERENCES "oneplandb"."country"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_member" ADD CONSTRAINT "trip_member_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "oneplandb"."trip"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_member" ADD CONSTRAINT "trip_member_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."budget" ADD CONSTRAINT "budget_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "oneplandb"."trip"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."budget_payment" ADD CONSTRAINT "budget_payment_budget_id_fkey" FOREIGN KEY ("budget_id") REFERENCES "oneplandb"."budget"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."budget_payment" ADD CONSTRAINT "budget_payment_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."expense" ADD CONSTRAINT "expense_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "oneplandb"."trip"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."expense" ADD CONSTRAINT "expense_paid_by_id_fkey" FOREIGN KEY ("paid_by_id") REFERENCES "oneplandb"."user"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."expense_share" ADD CONSTRAINT "expense_share_expense_id_fkey" FOREIGN KEY ("expense_id") REFERENCES "oneplandb"."expense"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."expense_share" ADD CONSTRAINT "expense_share_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_plan_item" ADD CONSTRAINT "trip_plan_item_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "oneplandb"."trip"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_photo" ADD CONSTRAINT "trip_photo_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "oneplandb"."trip"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_photo" ADD CONSTRAINT "trip_photo_uploaded_by_id_fkey" FOREIGN KEY ("uploaded_by_id") REFERENCES "oneplandb"."user"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_activity" ADD CONSTRAINT "trip_activity_trip_id_fkey" FOREIGN KEY ("trip_id") REFERENCES "oneplandb"."trip"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."trip_activity" ADD CONSTRAINT "trip_activity_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;
