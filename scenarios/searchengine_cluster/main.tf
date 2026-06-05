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

# Guards the samsungcloudplatformv2_searchengine_cluster fixture: a single-node
# OpenSearch-style search DBaaS cluster. Unique to searchengine: is_combined
# flag, optional license, and the MASTER_DATA combined node role.

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
  default = "ses1v2m4"
}

resource "samsungcloudplatformv2_searchengine_cluster" "regr" {
  name                    = "regrsearch"
  dbaas_engine_version_id = var.dbaas_engine_version_id
  nat_enabled             = false
  service_state           = "RUNNING"
  timezone                = "Asia/Seoul"
  instance_name_prefix    = "regrsearch"
  allowable_ip_addresses  = ["10.0.0.0/24"]
  subnet_id               = var.subnet_id
  is_combined             = true

  init_config_option = {
    database_user_name     = "regradmin"
    database_user_password = "Regr1234!@"
    database_port          = 9201
    backup_option = {
      retention_period_day = "7"
      starting_time_hour   = "11"
    }
  }

  maintenance_option = {
    use_maintenance_option = false
  }

  instance_groups = [
    {
      role_type        = "MASTER_DATA"
      server_type_name = var.server_type_name
      block_storage_groups = [
        { role_type = "OS", size_gb = 100, volume_type = "SSD" },
        { role_type = "DATA", size_gb = 200, volume_type = "SSD" },
      ]
      instances = [
        { role_type = "MASTER_DATA" },
      ]
    },
    {
      role_type        = "KIBANA"
      server_type_name = var.server_type_name
      block_storage_groups = [
        { role_type = "OS", size_gb = 100, volume_type = "SSD" },
      ]
      instances = [
        { role_type = "KIBANA" },
      ]
    },
  ]
}
