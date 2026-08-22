-- CreateTable
CREATE TABLE "oneplandb"."plan_route_cache" (
    "id" SERIAL NOT NULL,
    "route_hash" VARCHAR(64) NOT NULL,
    "payload" JSONB NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "plan_route_cache_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "plan_route_cache_route_hash_key" ON "oneplandb"."plan_route_cache"("route_hash");
