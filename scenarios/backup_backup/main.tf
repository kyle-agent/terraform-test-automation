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

resource "samsungcloudplatformv2_backup_backup" "regr" {
  encrypt_enabled = "true"
  name = "regr"
  policy_category = "AGENTLESS"
  policy_type = "VM_IMAGE"
  retention_period = "WEEK_2"
  schedules = [
    {
      frequency = "regr"
      start_time = "regr"
      type = "regr"
    }
  ]
  server_category = "VIRTUAL_SERVER"
  server_uuid = "regr"
}
