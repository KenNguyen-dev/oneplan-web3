-- AlterTable
ALTER TABLE "oneplandb"."vault_transaction" ADD COLUMN     "expense_category" "oneplandb"."expense_category",
ADD COLUMN     "expense_name" VARCHAR(255),
ADD COLUMN     "share_with_user_ids" INTEGER[];
