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

# Guards the samsungcloudplatformv2_mysql_cluster fixture: a single-node MySQL
# DBaaS cluster with full init_config_option / instance_groups nesting so the
# schema validate sweep catches regressions in the deeply-nested DB cluster API.

# Real subnet/version/server-type ids are environment-specific; integration
# supplies them via TF_VAR_subnet_id / TF_VAR_dbaas_engine_version_id /
# TF_VAR_server_type_name. Defaults are placeholders so validate works offline.
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

resource "samsungcloudplatformv2_mysql_cluster" "regr" {
  name                    = "regrmysql"
  dbaas_engine_version_id = var.dbaas_engine_version_id
  ha_enabled              = false
  nat_enabled             = false
  service_state           = "RUNNING"
  timezone                = "Asia/Seoul"
  instance_name_prefix    = "regrmysql"
  allowable_ip_addresses  = ["10.0.0.0/24"]
  subnet_id               = var.subnet_id

  init_config_option = {
    database_name           = "regrdb"
    database_user_name      = "regradmin"
    database_user_password  = "Regr1234!@"
    database_port           = 3306
    database_character_set  = "utf8mb4"
    database_case_sensitive = false
    backup_option = {
      retention_period_day     = "7"
      starting_time_hour       = "11"
      archive_frequency_minute = "30"
    }
  }

  maintenance_option = {
    use_maintenance_option = false
  }

  instance_groups = [
    {
      role_type        = "ACTIVE"
      server_type_name = var.server_type_name
      block_storage_groups = [
        { role_type = "OS", size_gb = 100, volume_type = "SSD" },
        { role_type = "DATA", size_gb = 200, volume_type = "SSD" },
      ]
      instances = [
        { role_type = "ACTIVE" },
      ]
    },
  ]
}
