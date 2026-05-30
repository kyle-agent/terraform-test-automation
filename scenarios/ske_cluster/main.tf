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

# Promoted regression fixture: a Kubernetes (SKE) cluster pinned to a real
# version with vpc/subnet/volume/security-group references. UUID inputs default
# to the zero-UUID, overridable via TF_VAR_*; passes validate offline.

variable "cluster_name" {
  description = "SKE cluster name."
  type        = string
  default     = "regr-ske-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version string (e.g. 1.30.1)."
  type        = string
  default     = "1.30.1"
}

variable "vpc_id" {
  description = "VPC UUID hosting the cluster."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "subnet_id" {
  description = "Subnet UUID for the cluster control plane."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "volume_id" {
  description = "Boot volume type UUID for cluster nodes."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "security_group_id_list" {
  description = "Security group UUIDs attached to the cluster."
  type        = list(string)
  default     = ["00000000-0000-0000-0000-000000000000"]
}

resource "samsungcloudplatformv2_ske_cluster" "regr" {
  name                          = var.cluster_name
  kubernetes_version            = var.kubernetes_version
  cloud_logging_enabled         = false
  service_watch_logging_enabled = false
  security_group_id_list        = var.security_group_id_list
  subnet_id                     = var.subnet_id
  volume_id                     = var.volume_id
  vpc_id                        = var.vpc_id

  tags = {
    env = "regression"
  }
}
