-- Zalo ZNS alert templates require a customer-name parameter, so orders now
-- carry the guest's display name. Schema-qualified per repo convention.
ALTER TABLE "oneplandb"."fare_watch_order" ADD COLUMN "name" VARCHAR(60);
