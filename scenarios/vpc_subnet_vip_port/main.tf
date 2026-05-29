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

resource "samsungcloudplatformv2_vpc_subnet_vip_port" "regr" {
  port_id = "00000000-0000-0000-0000-000000000000"
  subnet_id = "00000000-0000-0000-0000-000000000000"
  vip_id = "00000000-0000-0000-0000-000000000000"
}
