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
# Empty default => look the engine version up at runtime via the data source
# below. Set TF_VAR_dbaas_engine_version_id to override (e.g. to pin a version).
variable "dbaas_engine_version_id" {
  type    = string
  default = ""
}
variable "server_type_name" {
  type = string
  # ROOT CAUSE (dbaas_probe catalog harvest, run 27802022018, 2026-06-19): the
  # earlier 400 "invalid data (Server type)" with redis1v2m4/redis1v1m2 was NOT a
  # missing name — both ARE in the live /v1/server-types catalog (70 types). The
  # defect is an ENGINE/SERVER-TYPE IMAGE MISMATCH: the catalog has 2 engine
  # versions, "Valkey Sentinel 8.1.4" (first non-EOS) and "Redis OSS Sentinel
  # 7.2.11"; every server-type carries a product_image_type ("Valkey Sentinel" ->
  # css*, "Redis OSS Sentinel" -> redis*). The fixture auto-resolved the engine
  # version to the FIRST non-EOS (Valkey) but sent a redis* server-type -> reject.
  # Empty default => the locals below derive a server-type whose image matches the
  # chosen engine version. Set TF_VAR_server_type_name only to pin a tier.
  default = ""
}

# Engine versions are account/region-specific, so resolve a valid id at runtime
# instead of hardcoding one. Prefer a version that is not end-of-service.
data "samsungcloudplatformv2_cachestore_engine_version" "regr" {}

locals {
  cachestore_engine_versions_available = [
    for v in data.samsungcloudplatformv2_cachestore_engine_version.regr.contents :
    v if !v.end_of_service
  ]
  # The single engine version the cluster will use (first non-EOS, else first).
  cachestore_chosen_engine_version = length(local.cachestore_engine_versions_available) > 0 ? (
    local.cachestore_engine_versions_available[0]
  ) : data.samsungcloudplatformv2_cachestore_engine_version.regr.contents[0]
  cachestore_engine_version_id = var.dbaas_engine_version_id != "" ? var.dbaas_engine_version_id : local.cachestore_chosen_engine_version.id

  # server_type_name MUST share the chosen engine version's product_image_type
  # (live catalog: "Valkey Sentinel" -> css*, "Redis OSS Sentinel" -> redis*),
  # else create 400s "invalid data (Server type)". Pick the smallest general tier
  # of the matching family; default to Valkey since it is the first listed.
  cachestore_server_type_by_image = {
    "Valkey Sentinel"    = "css1v2m4"
    "Redis OSS Sentinel" = "redis1v2m4"
  }
  cachestore_server_type_name = var.server_type_name != "" ? var.server_type_name : lookup(
    local.cachestore_server_type_by_image, local.cachestore_chosen_engine_version.product_image_type, "css1v2m4"
  )
}

resource "samsungcloudplatformv2_cachestore_cluster" "regr" {
  name                    = "regrcache"
  dbaas_engine_version_id = local.cachestore_engine_version_id
  ha_enabled              = false
  nat_enabled             = false
  service_state           = "RUNNING"
  timezone                = "Asia/Seoul"
  instance_name_prefix    = "regrcache"
  allowable_ip_addresses  = ["10.0.0.0/24"]
  subnet_id               = var.subnet_id
  replica_count           = 0

  init_config_option = {
    database_user_password = "Regr1234!@"
    database_port          = 6379
    sentinel_port          = 26379
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
      role_type        = "MASTER"
      server_type_name = local.cachestore_server_type_name
      block_storage_groups = [
        { role_type = "OS", size_gb = 104, volume_type = "SSD" },
        { role_type = "DATA", size_gb = 200, volume_type = "SSD" },
      ]
      instances = [
        { role_type = "MASTER" },
      ]
    },
  ]
}
