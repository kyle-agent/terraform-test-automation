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

resource "samsungcloudplatformv2_firewall_firewall_rule" "regr" {
  firewall_id = "00000000-0000-0000-0000-000000000000"
  firewall_rule_create = {
      action = "ALLOW"
      destination_address = ["10.0.0.0/24"]
      direction = "INBOUND"
      service = [
      {
        service_type = "TCP"
      }
    ]
      source_address = ["10.0.0.0/24"]
      status = "ENABLE"
    }
}
