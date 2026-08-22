-- CreateEnum
CREATE TYPE "oneplandb"."chat_message_type" AS ENUM ('TEXT', 'IMAGE');

-- AlterTable
ALTER TABLE "oneplandb"."chat_message"
ADD COLUMN "type" "oneplandb"."chat_message_type" NOT NULL DEFAULT 'TEXT',
ADD COLUMN "image_object_key" VARCHAR(500);
