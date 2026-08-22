-- CreateTable
CREATE TABLE "oneplandb"."vault_cash_settlement" (
    "id" SERIAL NOT NULL,
    "trip_vault_id" INTEGER NOT NULL,
    "from_user_id" INTEGER NOT NULL,
    "to_user_id" INTEGER NOT NULL,
    "amount_micro" BIGINT NOT NULL,
    "confirmed_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "vault_cash_settlement_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "vault_cash_settlement_trip_vault_id_from_user_id_to_user_id_key" ON "oneplandb"."vault_cash_settlement"("trip_vault_id", "from_user_id", "to_user_id");

-- AddForeignKey
ALTER TABLE "oneplandb"."vault_cash_settlement" ADD CONSTRAINT "vault_cash_settlement_trip_vault_id_fkey" FOREIGN KEY ("trip_vault_id") REFERENCES "oneplandb"."trip_vault"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."vault_cash_settlement" ADD CONSTRAINT "vault_cash_settlement_from_user_id_fkey" FOREIGN KEY ("from_user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "oneplandb"."vault_cash_settlement" ADD CONSTRAINT "vault_cash_settlement_to_user_id_fkey" FOREIGN KEY ("to_user_id") REFERENCES "oneplandb"."user"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
