-- CreateTable
CREATE TABLE "oneplandb"."board" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "title" VARCHAR(255) NOT NULL,
    "description" VARCHAR(500),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "board_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."board_pin" (
    "id" SERIAL NOT NULL,
    "board_id" INTEGER NOT NULL,
    "name" VARCHAR(255) NOT NULL,
    "address" VARCHAR(500),
    "latitude" DOUBLE PRECISION,
    "longitude" DOUBLE PRECISION,
    "notes" VARCHAR(1000),
    "source_url" VARCHAR(1000),
    "source_timestamp_sec" DOUBLE PRECISION,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "board_pin_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."pin_extraction_cache" (
    "id" SERIAL NOT NULL,
    "url_hash" VARCHAR(64) NOT NULL,
    "source_url" VARCHAR(1000) NOT NULL,
    "payload" JSONB NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "pin_extraction_cache_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "board_user_id_idx" ON "oneplandb"."board"("user_id");

-- CreateIndex
CREATE INDEX "board_pin_board_id_idx" ON "oneplandb"."board_pin"("board_id");

-- CreateIndex
CREATE UNIQUE INDEX "pin_extraction_cache_url_hash_key" ON "oneplandb"."pin_extraction_cache"("url_hash");

-- AddForeignKey
ALTER TABLE "oneplandb"."board" ADD CONSTRAINT "board_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."board_pin" ADD CONSTRAINT "board_pin_board_id_fkey" FOREIGN KEY ("board_id") REFERENCES "oneplandb"."board"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
