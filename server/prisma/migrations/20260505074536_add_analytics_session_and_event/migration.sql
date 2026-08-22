-- CreateTable
CREATE TABLE "oneplandb"."analytics_session" (
    "id" VARCHAR(36) NOT NULL,
    "user_id" INTEGER,
    "anonymous_id" VARCHAR(36),
    "platform" VARCHAR(16) NOT NULL,
    "app_version" VARCHAR(32),
    "os_version" VARCHAR(32),
    "started_at" TIMESTAMPTZ(6) NOT NULL,
    "ended_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "analytics_session_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."analytics_event" (
    "id" SERIAL NOT NULL,
    "session_id" VARCHAR(36),
    "user_id" INTEGER,
    "event_name" VARCHAR(64) NOT NULL,
    "properties" JSONB,
    "occurred_at" TIMESTAMPTZ(6) NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "analytics_event_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "analytics_session_user_id_started_at_idx" ON "oneplandb"."analytics_session"("user_id", "started_at");

-- CreateIndex
CREATE INDEX "analytics_session_started_at_idx" ON "oneplandb"."analytics_session"("started_at");

-- CreateIndex
CREATE INDEX "analytics_event_event_name_occurred_at_idx" ON "oneplandb"."analytics_event"("event_name", "occurred_at");

-- CreateIndex
CREATE INDEX "analytics_event_user_id_occurred_at_idx" ON "oneplandb"."analytics_event"("user_id", "occurred_at");

-- CreateIndex
CREATE INDEX "analytics_event_session_id_idx" ON "oneplandb"."analytics_event"("session_id");

-- AddForeignKey
ALTER TABLE "oneplandb"."analytics_session" ADD CONSTRAINT "analytics_session_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."analytics_event" ADD CONSTRAINT "analytics_event_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "oneplandb"."analytics_session"("id") ON DELETE SET NULL ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."analytics_event" ADD CONSTRAINT "analytics_event_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE SET NULL ON UPDATE NO ACTION;
