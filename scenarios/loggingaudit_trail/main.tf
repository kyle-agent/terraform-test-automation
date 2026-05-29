terraform {
  required_version = ">= 1.6"
  required_providers {
    samsungcloudplatformv2 = {
      source  = "SamsungSDSCloud/samsungcloudplatformv2"
      version = ">= 0.0.1"
    }
  }
}

provider "samsungcloudplatformv2" {}

# AUTO-GENERATED minimal coverage fixture (scripts/gen_scenarios.py).
# Validated against the real provider schema. Exercised in dry-run by the
# tests/schema validate sweep; extend with integration assertions as needed.

resource "samsungcloudplatformv2_loggingaudit_trail" "regr" {
  account_id = "00000000-0000-0000-0000-000000000000"
  log_archive_account_id = "00000000-0000-0000-0000-000000000000"
  log_type_total_yn = "regr"
  log_verification_yn = "regr"
  organization_trail_yn = "regr"
  region_total_yn = "regr"
  resource_type_total_yn = "regr"
  trail_description = "10.0.0.10"
  user_total_yn = "regr"
}
