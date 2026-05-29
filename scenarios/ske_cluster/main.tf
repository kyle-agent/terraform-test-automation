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

resource "samsungcloudplatformv2_ske_cluster" "regr" {
  cloud_logging_enabled = false
  kubernetes_version = "v1.30.1"
  name = "regr"
  security_group_id_list = ["regr"]
  service_watch_logging_enabled = false
  subnet_id = "00000000-0000-0000-0000-000000000000"
  volume_id = "00000000-0000-0000-0000-000000000000"
  vpc_id = "00000000-0000-0000-0000-000000000000"
}
