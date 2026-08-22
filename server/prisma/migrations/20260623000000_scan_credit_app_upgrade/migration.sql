-- App-update reward grants (source='app_upgrade'). One grant per
-- (user, app version): external_ref holds the reported version string.
-- Partial unique index so it dedupes per version and never collides with the
-- purchase index (different predicate). Belt-and-suspenders behind the
-- advisory-lock + findFirst guard in ScanCreditService.grantAppUpgrade.
CREATE UNIQUE INDEX "scan_credit_grant_app_upgrade_uq"
  ON "oneplandb"."scan_credit_grant"("user_id", "external_ref")
  WHERE "source" = 'app_upgrade';
