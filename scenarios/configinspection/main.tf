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
# tests/schema validate sweep; extend with integration assertions to promote.

resource "samsungcloudplatformv2_configinspection" "regr" {
  account_id = "00000000-0000-0000-0000-000000000000"
  auth_key_request = {
      auth_key_id = "00000000-0000-0000-0000-000000000000"
    }
  csp_type = "regr"
  diagnosis_account_id = "00000000-0000-0000-0000-000000000000"
  diagnosis_check_type = "regr"
  diagnosis_id = "00000000-0000-0000-0000-000000000000"
  diagnosis_name = "regr"
  diagnosis_type = "regr"
  plan_type = "regr"
}
