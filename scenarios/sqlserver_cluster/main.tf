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

# Guards the samsungcloudplatformv2_sqlserver_cluster fixture: a single-node
# SQL Server DBaaS cluster. Unique to SQL Server: the nested databases list
# (database_name + drive_letter), collation, license, and a backup_option that
# also carries full_backup_day_of_week.

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
  default = "db1v2m8"
}

resource "samsungcloudplatformv2_sqlserver_cluster" "regr" {
  name                    = "regrmssql"
  dbaas_engine_version_id = var.dbaas_engine_version_id
  ha_enabled              = false
  nat_enabled             = false
  service_state           = "RUNNING"
  timezone                = "Asia/Seoul"
  instance_name_prefix    = "regrmssql"
  allowable_ip_addresses  = ["10.0.0.0/24"]
  subnet_id               = var.subnet_id

  init_config_option = {
    audit_enabled          = false
    database_service_name  = "Regrsvc"
    database_user_name     = "regradmin"
    database_user_password = "Regr1234!@"
    database_port          = 2866
    database_collation     = "SQL_Latin1_General_CP1_CI_AS"
    license                = "HMWJ3-KY3J2-NMVD7-KG4JR-X2G8G"
    databases = [
      {
        database_name = "regrdb"
        drive_letter  = "D"
      },
    ]
    backup_option = {
      retention_period_day     = "7"
      starting_time_hour       = "11"
      archive_frequency_minute = "30"
      full_backup_day_of_week  = "SUN"
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
