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

variable "name_suffix" {
  type        = string
  default     = ""
  description = "Per-run unique suffix (injected by the harness as TF_VAR_name_suffix)."
}

# The harness only exports TF_VAR_suffix (= github.run_id); prefer it so the
# cluster name is actually unique per run. Falls back to name_suffix, then "".
variable "suffix" {
  type        = string
  default     = ""
  description = "Per-run unique suffix injected by the harness as TF_VAR_suffix (github.run_id)."
}

locals {
  ske_suffix = var.suffix != "" ? var.suffix : var.name_suffix
}

variable "kubernetes_version" {
  description = "Kubernetes version (Required pattern ^v\\d\\.\\d{1,2}\\.\\d{1,2}$, e.g. v1.29.8). Integration overrides via TF_VAR_kubernetes_version from the catalog."
  type        = string
  default     = "v1.30.1"
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
  # name pattern ^[a-z][a-z0-9-]*[a-z0-9]$, 3-30 chars. suffix is numeric
  # (github.run_id) so "rske<suffix>" stays valid (and "rske" when empty for
  # offline validate).
  name                          = "rske${local.ske_suffix}"
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
