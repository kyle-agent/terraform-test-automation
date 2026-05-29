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

resource "samsungcloudplatformv2_ske_nodepool" "regr" {
  cluster_id = "00000000-0000-0000-0000-000000000000"
  image_os = "regr"
  image_os_version = "regr"
  is_auto_recovery = false
  is_auto_scale = false
  keypair_name = "regr"
  kubernetes_version = "regr"
  name = "regr"
  server_type_id = "00000000-0000-0000-0000-000000000000"
  volume_size = 100
  volume_type_name = "regr"
}
