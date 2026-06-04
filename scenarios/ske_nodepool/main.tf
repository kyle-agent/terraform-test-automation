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

# Self-contained SKE nodepool fixture: a nodepool needs a parent cluster, so this
# scenario provisions an ske_cluster and an ske_nodepool on it. Network / volume /
# keypair / k8s-version inputs come from the dependent-probe bootstrap via TF_VAR_*.
# The nodepool OS image (image_os/image_os_version) is self-selected from the
# ske_nodepool_images catalog for the chosen kubernetes_version so we never guess a
# combo the catalog doesn't offer (a bad combo errors at plan, before any cluster
# is created). UUID inputs default to the zero-UUID; passes validate offline.

variable "name_suffix" {
  type        = string
  default     = ""
  description = "Per-run unique suffix (injected by the harness as TF_VAR_name_suffix)."
}

variable "kubernetes_version" {
  description = "Kubernetes version (Required pattern ^v\\d\\.\\d{1,2}\\.\\d{1,2}$). Integration overrides via TF_VAR_kubernetes_version from the catalog."
  type        = string
  default     = "v1.30.1"
}

variable "vpc_id" {
  type    = string
  default = "00000000-0000-0000-0000-000000000000"
}

variable "subnet_id" {
  type    = string
  default = "00000000-0000-0000-0000-000000000000"
}

variable "volume_id" {
  description = "SKE cluster volume_id — a filestorage_volume id (see provider #66)."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "security_group_id_list" {
  type    = list(string)
  default = ["00000000-0000-0000-0000-000000000000"]
}

variable "server_type_id" {
  description = "Server (instance) type for nodepool nodes."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "keypair_name" {
  description = "SSH keypair name applied to nodepool nodes."
  type        = string
  default     = "regr-keypair"
}

# Valid nodepool OS image for the chosen k8s version (scp_original_image_type k8s).
data "samsungcloudplatformv2_ske_nodepool_images" "np" {
  scp_original_image_type = "k8s"
  os                      = "ubuntu"
  kubernetes_version      = var.kubernetes_version
}

locals {
  np_image     = try(data.samsungcloudplatformv2_ske_nodepool_images.np.nodepool_images[0], null)
  np_image_os  = try(local.np_image.os, "ubuntu")
  np_image_ver = try(local.np_image.os_version, "22.04")
}

# Parent cluster (volume_id = filestorage volume id; see provider #66).
resource "samsungcloudplatformv2_ske_cluster" "regr" {
  name                          = "rske${var.name_suffix}"
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

resource "samsungcloudplatformv2_ske_nodepool" "regr" {
  name               = "rnp${var.name_suffix}"
  cluster_id         = samsungcloudplatformv2_ske_cluster.regr.id
  server_type_id     = var.server_type_id
  kubernetes_version = var.kubernetes_version
  keypair_name       = var.keypair_name
  image_os           = local.np_image_os
  image_os_version   = local.np_image_ver
  is_auto_recovery   = true
  is_auto_scale      = false
  desired_node_count = 1
  volume_size        = 104
  volume_type_name   = "SSD"
}
