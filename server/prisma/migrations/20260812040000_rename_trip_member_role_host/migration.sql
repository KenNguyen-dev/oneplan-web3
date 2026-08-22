-- Rename TripMemberRole values to match product language (HOST / CO_HOST).
ALTER TYPE "oneplandb"."TripMemberRole" RENAME VALUE 'LEADER' TO 'HOST';
ALTER TYPE "oneplandb"."TripMemberRole" RENAME VALUE 'CO_LEADER' TO 'CO_HOST';
