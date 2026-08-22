-- Stable StoreKit account association for purchases made in the app.
ALTER TABLE "oneplandb"."user"
ADD COLUMN "app_account_token" UUID;

CREATE UNIQUE INDEX "user_app_account_token_key"
ON "oneplandb"."user"("app_account_token");

-- App Store Server Notification deliveries are events, not transactions.
CREATE TABLE "oneplandb"."subscription_notification" (
    "id" SERIAL NOT NULL,
    "notification_uuid" VARCHAR(255) NOT NULL,
    "notification_type" VARCHAR(100),
    "original_transaction_id" VARCHAR(255),
    "transaction_id" VARCHAR(255),
    "environment" VARCHAR(50),
    "signed_date" TIMESTAMPTZ(6),
    "outcome" VARCHAR(32) NOT NULL DEFAULT 'RECEIVED',
    "error_message" VARCHAR(255),
    "processed_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "user_id" INTEGER,

    CONSTRAINT "subscription_notification_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "subscription_notification_notification_uuid_key"
ON "oneplandb"."subscription_notification"("notification_uuid");

CREATE INDEX "subscription_notification_original_transaction_id_idx"
ON "oneplandb"."subscription_notification"("original_transaction_id");

CREATE INDEX "subscription_notification_user_id_idx"
ON "oneplandb"."subscription_notification"("user_id");

ALTER TABLE "oneplandb"."subscription_notification"
ADD CONSTRAINT "subscription_notification_user_id_fkey"
FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id")
ON DELETE SET NULL ON UPDATE NO ACTION;
