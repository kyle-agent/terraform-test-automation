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

resource "samsungcloudplatformv2_searchengine_cluster" "regr" {
  allowable_ip_addresses = ["10.0.0.0/24"]
  dbaas_engine_version_id = "v1.30.1"
  init_config_option = {
      backup_option = {}
      database_port = 1
      database_user_name = "regr"
      database_user_password = "regr"
    }
  instance_groups = [
    {
      block_storage_groups = [
      {
        role_type = "MASTER_DATA"
        size_gb = 1
        volume_type = "SSD"
      }
    ]
      instances = [
      {
        role_type = "MASTER_DATA"
      }
    ]
      role_type = "MASTER_DATA"
      server_type_name = "regr"
    }
  ]
  instance_name_prefix = "regr"
  is_combined = false
  maintenance_option = {}
  name = "regr"
  nat_enabled = false
  service_state = "RUNNING"
  subnet_id = "00000000-0000-0000-0000-000000000000"
  timezone = "regr"
}
