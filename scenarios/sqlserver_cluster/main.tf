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

resource "samsungcloudplatformv2_sqlserver_cluster" "regr" {
  allowable_ip_addresses = ["10.0.0.0/24"]
  dbaas_engine_version_id = "v1.30.1"
  ha_enabled = false
  init_config_option = {
      audit_enabled = false
      backup_option = {}
      database_collation = "regr"
      database_port = 1
      database_service_name = "regr"
      database_user_name = "regr"
      database_user_password = "regr"
      databases = [
      {
        database_name = "regr"
        drive_letter = "regr"
      }
    ]
      license = "regr"
    }
  instance_groups = [
    {
      block_storage_groups = [
      {
        role_type = "ACTIVE"
        size_gb = 1
        volume_type = "SSD"
      }
    ]
      instances = [
      {
        role_type = "ACTIVE"
      }
    ]
      role_type = "ACTIVE"
      server_type_name = "regr"
    }
  ]
  instance_name_prefix = "regr"
  maintenance_option = {}
  name = "regr"
  nat_enabled = false
  service_state = "RUNNING"
  subnet_id = "00000000-0000-0000-0000-000000000000"
  timezone = "regr"
}
