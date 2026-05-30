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

# Guards the samsungcloudplatformv2_cachestore_cluster fixture: a single-node
# Redis-style cache DBaaS cluster. Unique to cachestore: replica_count and a
# sentinel_port in init_config_option (no database_name / user_name).

# Real ids are environment-specific; integration supplies them via
# TF_VAR_subnet_id / TF_VAR_dbaas_engine_version_id / TF_VAR_server_type_name.
# Defaults are placeholders so validate works offline.
variable "subnet_id" {
  type    = string
  default = "00000000-0000-0000-0000-000000000000"
}
variable "dbaas_engine_version_id" {
  type    = string
  default = "00000000-0000-0000-0000-000000000000"
}
variable "server_type_name" {
  type    = string
  default = "db1v2m4"
}

resource "samsungcloudplatformv2_cachestore_cluster" "regr" {
  name                    = "regr-cache"
  dbaas_engine_version_id = var.dbaas_engine_version_id
  ha_enabled              = false
  nat_enabled             = false
  service_state           = "RUNNING"
  timezone                = "Asia/Seoul"
  instance_name_prefix    = "regrcache"
  allowable_ip_addresses  = ["10.0.0.0/24"]
  subnet_id               = var.subnet_id
  replica_count           = 1

  init_config_option = {
    database_user_password = "Regr1234!@"
    database_port          = 6379
    sentinel_port          = 26379
    backup_option = {
      retention_period_day = "7"
      starting_time_hour   = "02"
    }
  }

  maintenance_option = {
    use_maintenance_option = false
  }

  instance_groups = [
    {
      role_type        = "MASTER"
      server_type_name = var.server_type_name
      block_storage_groups = [
        { role_type = "OS", size_gb = 100, volume_type = "SSD" },
        { role_type = "DATA", size_gb = 200, volume_type = "SSD" },
      ]
      instances = [
        { role_type = "MASTER" },
      ]
    },
  ]
}
