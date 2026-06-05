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

# Guards the samsungcloudplatformv2_postgresql_cluster fixture: a single-node
# PostgreSQL DBaaS cluster exercising the audit_enabled / encoding / locale
# init options plus instance_groups nesting in the schema validate sweep.

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

resource "samsungcloudplatformv2_postgresql_cluster" "regr" {
  name                    = "regrpgsql"
  dbaas_engine_version_id = var.dbaas_engine_version_id
  ha_enabled              = false
  nat_enabled             = false
  service_state           = "RUNNING"
  timezone                = "Asia/Seoul"
  instance_name_prefix    = "regrpgsql"
  allowable_ip_addresses  = ["10.0.0.0/24"]
  subnet_id               = var.subnet_id

  init_config_option = {
    audit_enabled          = false
    database_name          = "regrdb"
    database_user_name     = "regradmin"
    database_user_password = "Regr1234!@"
    database_port          = 5432
    database_encoding      = "UTF-8"
    database_locale        = "C"
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
