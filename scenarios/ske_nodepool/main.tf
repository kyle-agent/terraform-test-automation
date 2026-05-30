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

# Promoted regression fixture: an SKE nodepool with a real OS image, version and
# volume sizing. UUID inputs default to the zero-UUID, overridable via TF_VAR_*;
# passes validate offline.

variable "nodepool_name" {
  description = "Nodepool name."
  type        = string
  default     = "regr-nodepool"
}

variable "cluster_id" {
  description = "Parent SKE cluster UUID."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "server_type_id" {
  description = "Server (instance) type UUID for nodepool nodes."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "kubernetes_version" {
  description = "Kubernetes version string for the nodepool (e.g. 1.30.1)."
  type        = string
  default     = "1.30.1"
}

variable "keypair_name" {
  description = "SSH keypair name applied to nodepool nodes."
  type        = string
  default     = "regr-keypair"
}

variable "volume_size" {
  description = "Node boot volume size in GB."
  type        = number
  default     = 100
}

resource "samsungcloudplatformv2_ske_nodepool" "regr" {
  name               = var.nodepool_name
  cluster_id         = var.cluster_id
  server_type_id     = var.server_type_id
  kubernetes_version = var.kubernetes_version
  keypair_name       = var.keypair_name
  image_os           = "ubuntu"
  image_os_version   = "22.04"
  is_auto_recovery   = true
  is_auto_scale      = false
  volume_size        = var.volume_size
  volume_type_name   = "SSD"
}
