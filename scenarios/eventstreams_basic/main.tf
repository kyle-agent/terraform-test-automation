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
variable "security_group_id" {
  type = string
}
variable "dbaas_engine_version_id" {
  type = string
}
variable "server_type_name" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "cluster_name" {
  type    = string
  default = "regr-evs"
}

# Multiple allowable IPs to exercise Chapter 4 #14 (list-order regression).
# If access_rules list is order-sensitive and Read doesn't sort, re-plan will
# show spurious diff like "- 10.0.0.0/8" even though config unchanged.
variable "allowable_ip_addresses" {
  type    = list(string)
  default = [
    "10.194.177.128/26",
    "10.0.0.0/8",
    "10.113.0.0/16",
  ]
}

resource "samsungcloudplatformv2_eventstreams_cluster" "regression" {
  name                   = var.cluster_name
  akhq_enabled           = true
  is_combined            = true
  allowable_ip_addresses = var.allowable_ip_addresses
  dbaas_engine_version_id = var.dbaas_engine_version_id

  init_config_option = {
    broker_port              = 9091
    broker_sasl_id           = "broker"
    broker_sasl_password     = "Broker1234!"
    zookeeper_port           = 2181
    zookeeper_sasl_id        = "zookeeper"
    zookeeper_sasl_password  = "Zookeeper1234!"
  }

  instance_groups = [
    {
      role_type        = "BROKER"
      server_type_name = var.server_type_name
      block_storage_groups = [
        { role_type = "OS",   size_gb = 100, volume_type = "SSD" },
        { role_type = "DATA", size_gb = 200, volume_type = "SSD" },
      ]
      instances = [
        { role_type = "BROKER" },
      ]
    },
  ]

  subnet_id         = var.subnet_id
  security_group_id = var.security_group_id
  vpc_id            = var.vpc_id
}
