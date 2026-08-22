-- CreateTable
CREATE TABLE "oneplandb"."country" (
    "id" SERIAL NOT NULL,
    "name" VARCHAR(100) NOT NULL,
    "iso3" CHAR(3),
    "iso2" CHAR(2),
    "numeric_code" CHAR(3),
    "phone_code" VARCHAR(255),
    "capital" VARCHAR(255),
    "currency" VARCHAR(255),
    "currency_name" VARCHAR(255),
    "currency_symbol" VARCHAR(255),
    "tld" VARCHAR(255),
    "native" VARCHAR(255),
    "region" VARCHAR(255),
    "sub_region" VARCHAR(255),
    "timezones" TEXT,
    "translations" TEXT,
    "latitude" DECIMAL(10,8),
    "longitude" DECIMAL(11,8),
    "emoji" VARCHAR(191),
    "emoji_u" VARCHAR(191),
    "created_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "flag" BOOLEAN NOT NULL DEFAULT true,
    "wiki_data_id" VARCHAR(255),

    CONSTRAINT "country_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."state" (
    "id" SERIAL NOT NULL,
    "name" VARCHAR(255) NOT NULL,
    "country_code" CHAR(2) NOT NULL,
    "fips_code" VARCHAR(255),
    "iso2" VARCHAR(255),
    "type" VARCHAR(191),
    "latitude" DECIMAL(10,8),
    "longitude" DECIMAL(11,8),
    "created_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "flag" BOOLEAN NOT NULL DEFAULT true,
    "wiki_data_id" VARCHAR(255),
    "country_id" INTEGER NOT NULL,

    CONSTRAINT "state_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oneplandb"."city" (
    "id" SERIAL NOT NULL,
    "name" VARCHAR(255) NOT NULL,
    "state_code" VARCHAR(255) NOT NULL,
    "country_code" CHAR(2) NOT NULL,
    "latitude" DECIMAL(10,8) NOT NULL,
    "longitude" DECIMAL(11,8) NOT NULL,
    "created_at" TIMESTAMPTZ(6),
    "updated_at" TIMESTAMPTZ(6),
    "flag" BOOLEAN NOT NULL DEFAULT true,
    "wiki_data_id" VARCHAR(255),
    "country_id" INTEGER NOT NULL,
    "state_id" INTEGER NOT NULL,

    CONSTRAINT "city_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "state_country_id_idx" ON "oneplandb"."state"("country_id");

-- CreateIndex
CREATE INDEX "city_state_id_idx" ON "oneplandb"."city"("state_id");

-- CreateIndex
CREATE INDEX "city_country_id_idx" ON "oneplandb"."city"("country_id");

-- AddForeignKey
ALTER TABLE "oneplandb"."state" ADD CONSTRAINT "country_region_final" FOREIGN KEY ("country_id") REFERENCES "oneplandb"."country"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."city" ADD CONSTRAINT "city_country_id_fkey" FOREIGN KEY ("country_id") REFERENCES "oneplandb"."country"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."city" ADD CONSTRAINT "city_state_id_fkey" FOREIGN KEY ("state_id") REFERENCES "oneplandb"."state"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;
