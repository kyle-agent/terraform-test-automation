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

resource "samsungcloudplatformv2_baremetal_baremetal" "regr" {
  image_id = "00000000-0000-0000-0000-000000000000"
  os_user_id = "00000000-0000-0000-0000-000000000000"
  os_user_password = "Regr1234!@"
  region_id = "00000000-0000-0000-0000-000000000000"
  server_details = [
    {
      bare_metal_server_name = "regr"
      nat_enabled = false
      server_type_id = "00000000-0000-0000-0000-000000000000"
    }
  ]
  subnet_id = "00000000-0000-0000-0000-000000000000"
  vpc_id = "00000000-0000-0000-0000-000000000000"
}
