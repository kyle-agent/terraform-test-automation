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

variable "subnet_id" {
  type = string
}
# Empty default => look the engine version up at runtime via the data source
# below. Set TF_VAR_dbaas_engine_version_id to override (e.g. to pin a version).
variable "dbaas_engine_version_id" {
  type    = string
  default = ""
}
variable "server_type_name" {
  type = string
}

# Engine versions are account/region-specific, so resolve a valid id at runtime
# instead of hardcoding one. Prefer a version that is not end-of-service.
data "samsungcloudplatformv2_eventstreams_engine_version" "regr" {}

locals {
  eventstreams_engine_versions_available = [
    for v in data.samsungcloudplatformv2_eventstreams_engine_version.regr.contents :
    v if !v.end_of_service
  ]
  eventstreams_engine_version_id = var.dbaas_engine_version_id != "" ? var.dbaas_engine_version_id : (
    length(local.eventstreams_engine_versions_available) > 0 ?
    local.eventstreams_engine_versions_available[0].id :
    data.samsungcloudplatformv2_eventstreams_engine_version.regr.contents[0].id
  )
}
variable "cluster_name" {
  type    = string
  default = "regr-evs"
}

# Multiple allowable IPs to exercise Chapter 4 #14 (list-order regression).
# If access_rules list is order-sensitive and Read doesn't sort, re-plan will
# show spurious diff like "- 10.0.0.0/8" even though config unchanged.
variable "allowable_ip_addresses" {
  type = list(string)
  default = [
    "10.194.177.128/26",
    "10.0.0.0/8",
    "10.113.0.0/16",
  ]
}

resource "samsungcloudplatformv2_eventstreams_cluster" "regression" {
  name                    = var.cluster_name
  akhq_enabled            = true
  is_combined             = true
  allowable_ip_addresses  = var.allowable_ip_addresses
  dbaas_engine_version_id = local.eventstreams_engine_version_id

  # Required by the provider schema (v3.x). subnet_id is top-level; there is no
  # security_group_id / vpc_id argument on this resource anymore.
  instance_name_prefix = "regrevs"
  nat_enabled          = false
  service_state        = "RUNNING"
  timezone             = "Asia/Seoul"

  maintenance_option = {
    use_maintenance_option = false
  }

  init_config_option = {
    broker_port             = 9091
    broker_sasl_id          = "broker"
    broker_sasl_password    = "Broker1234!"
    zookeeper_port          = 2181
    zookeeper_sasl_id       = "zookeeper"
    zookeeper_sasl_password = "Zookeeper1234!"
  }

  instance_groups = [
    {
      role_type        = "BROKER"
      server_type_name = var.server_type_name
      block_storage_groups = [
        { role_type = "OS", size_gb = 100, volume_type = "SSD" },
        { role_type = "DATA", size_gb = 200, volume_type = "SSD" },
      ]
      instances = [
        { role_type = "BROKER" },
      ]
    },
  ]

  subnet_id = var.subnet_id
}
