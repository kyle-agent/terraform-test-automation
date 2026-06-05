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

# Guards the samsungcloudplatformv2_mariadb_cluster fixture: a single-node
# MariaDB DBaaS cluster exercising audit_enabled / character_set init options
# plus instance_groups nesting in the schema validate sweep.

# Real ids are environment-specific; integration supplies them via
# TF_VAR_subnet_id / TF_VAR_dbaas_engine_version_id / TF_VAR_server_type_name.
# Defaults are placeholders so validate works offline.
variable "subnet_id" {
  type    = string
  default = "00000000-0000-0000-0000-000000000000"
}
# Empty default => look the engine version up at runtime via the data source
# below. Set TF_VAR_dbaas_engine_version_id to override (e.g. to pin a version).
variable "dbaas_engine_version_id" {
  type    = string
  default = ""
}
variable "server_type_name" {
  type    = string
  default = "db1v2m4"
}

# Engine versions are account/region-specific, so resolve a valid id at runtime
# instead of hardcoding one. Prefer a version that is not end-of-service.
data "samsungcloudplatformv2_mariadb_engine_version" "regr" {}

locals {
  mariadb_engine_versions_available = [
    for v in data.samsungcloudplatformv2_mariadb_engine_version.regr.contents :
    v if !v.end_of_service
  ]
  mariadb_engine_version_id = var.dbaas_engine_version_id != "" ? var.dbaas_engine_version_id : (
    length(local.mariadb_engine_versions_available) > 0 ?
    local.mariadb_engine_versions_available[0].id :
    data.samsungcloudplatformv2_mariadb_engine_version.regr.contents[0].id
  )
}

resource "samsungcloudplatformv2_mariadb_cluster" "regr" {
  name                    = "regrmariadb"
  dbaas_engine_version_id = local.mariadb_engine_version_id
  ha_enabled              = false
  nat_enabled             = false
  service_state           = "RUNNING"
  timezone                = "Asia/Seoul"
  instance_name_prefix    = "regrmaria"
  allowable_ip_addresses  = ["10.0.0.0/24"]
  subnet_id               = var.subnet_id

  init_config_option = {
    audit_enabled          = false
    database_name          = "regrdb"
    database_user_name     = "regradmin"
    database_user_password = "Regr1234!@"
    database_port          = 3306
    database_character_set = "utf8"
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
        { role_type = "OS", size_gb = 104, volume_type = "SSD" },
        { role_type = "DATA", size_gb = 200, volume_type = "SSD" },
      ]
      instances = [
        { role_type = "ACTIVE" },
      ]
    },
  ]
}
