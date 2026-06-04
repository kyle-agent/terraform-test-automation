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

# Shared prerequisites created once per dependent-probe run, so the dependent
# scenarios can be exercised without TEST_* secrets. The run id keeps names
# unique across runs; the workflow always destroys this stack afterwards.
#
# NOTE: vpc_subnet is intentionally NOT created — subnet create is broken in
# v3.3.1 (provider bug #59: Value Conversion Error on dns_nameservers). Restore
# it once #59 is fixed to unlock the subnet-dependent scenarios.
variable "suffix" {
  type        = string
  description = "Per-run unique suffix (numeric run id)."
  default     = "boot"
}

# Primary VPC (small /24 so vpc_cidr can add a separate, non-overlapping block).
resource "samsungcloudplatformv2_vpc_vpc" "prereq" {
  name        = "rpv${var.suffix}"
  cidr        = "192.168.0.0/24"
  description = "regr dependent-probe prerequisite vpc"
}

# Internet gateway on the primary VPC (some resources, e.g. vpn gateway, require
# the VPC to have an IGW).
resource "samsungcloudplatformv2_vpc_internet_gateway" "prereq" {
  type              = "IGW"
  vpc_id            = samsungcloudplatformv2_vpc_vpc.prereq.id
  description       = "regr dependent-probe prerequisite igw"
  firewall_enabled  = true
  firewall_loggable = false
}

# Subnet — created with dns_nameservers set EXPLICITLY to work around provider
# bug #59 (omitting the Optional+Computed dns_nameservers makes it unknown, which
# the []string model can't hold -> create fails). Setting it makes the value
# known and lets the subnet be created so subnet-dependent scenarios can run.
resource "samsungcloudplatformv2_vpc_subnet" "prereq" {
  name            = "rps${var.suffix}"
  vpc_id          = samsungcloudplatformv2_vpc_vpc.prereq.id
  type            = "GENERAL"
  cidr            = "192.168.0.0/27" # /27 (.0-.31) so vpc_subnet_vip's 192.168.0.20 fits
  description     = "regr dependent-probe prerequisite subnet"
  dns_nameservers = ["8.8.8.8"] # API permits up to 1; #59 workaround needs a known value
}

resource "samsungcloudplatformv2_security_group_security_group" "prereq" {
  name        = "rpsg${var.suffix}"
  description = "regr dependent-probe prerequisite security group"
  loggable    = false
}

# Public IP (some resources, e.g. vpn gateway, attach to one).
resource "samsungcloudplatformv2_vpc_publicip" "prereq" {
  type        = "IGW"
  description = "regr dependent-probe prerequisite public ip"
}

# Keypair for compute resources (virtualserver_server / ske_nodepool).
resource "samsungcloudplatformv2_virtualserver_keypair" "prereq" {
  name = "rpkp${var.suffix}"
}

# File storage volume — hypothesis under test: the SKE cluster's Required
# volume_id (a UUID with no data source; see #66) may accept a filestorage
# volume id. NFS avoids needing a CIFS password. type_name HDD is the cheapest.
resource "samsungcloudplatformv2_filestorage_volume" "prereq" {
  name                       = "rpfs${var.suffix}"
  protocol                   = "NFS"
  type_name                  = "HDD"
  file_unit_recovery_enabled = false
}

# Valid Kubernetes version for the SKE cluster/nodepool (kubernetes_version is
# Required with pattern ^v\d\.\d{1,2}\.\d{1,2}$, e.g. v1.29.8). Pick the first
# one the catalog offers so we never hard-code a version that gets retired.
data "samsungcloudplatformv2_ske_kubernetes_versions" "all" {}

# Boot image lookup (server_type has no data source — provided via TF_VAR; see #64/#65).
# scp_image_type="standard" excludes GPU images: without it, ids[0] is a GPU image
# ("UBUNTU 24.04 GPU", scp_image_type=gpu_standard) that the standard server type
# s1v1m2 rejects with an opaque "Image ID is not valid". The plural data source
# returns only ids (no name/type), so this trap is invisible to users — see issue
# filed on the provider repo.
data "samsungcloudplatformv2_virtualserver_images" "linux" {
  os_distro      = "ubuntu"
  status         = "active"
  scp_image_type = "standard"
}

# DIAGNOSTIC: singular data source (same filters, no id) resolves to ids[0] and
# returns full detail — confirms the selected image is non-GPU/standard.
data "samsungcloudplatformv2_virtualserver_image" "first" {
  os_distro      = "ubuntu"
  status         = "active"
  scp_image_type = "standard"
}

output "vpc_id" {
  value = samsungcloudplatformv2_vpc_vpc.prereq.id
}

output "subnet_id" {
  value = samsungcloudplatformv2_vpc_subnet.prereq.id
}

output "security_group_id" {
  value = samsungcloudplatformv2_security_group_security_group.prereq.id
}

output "publicip_id" {
  value = samsungcloudplatformv2_vpc_publicip.prereq.id
}

output "publicip_address" {
  value = samsungcloudplatformv2_vpc_publicip.prereq.publicip.ip_address
}

output "keypair_name" {
  value = samsungcloudplatformv2_virtualserver_keypair.prereq.name
}

output "image_id" {
  value = try(data.samsungcloudplatformv2_virtualserver_images.linux.ids[0], "NO_IMAGE_FOUND")
}

output "image_count" {
  value = length(try(data.samsungcloudplatformv2_virtualserver_images.linux.ids, []))
}

# DIAGNOSTIC outputs: full detail of the first ubuntu/active image (= ids[0]).
output "diag_image_name" {
  value = try(data.samsungcloudplatformv2_virtualserver_image.first.image.name, "n/a")
}
output "diag_image_type" {
  value = try(data.samsungcloudplatformv2_virtualserver_image.first.image.scp_image_type, "n/a")
}
output "diag_image_original_type" {
  value = try(data.samsungcloudplatformv2_virtualserver_image.first.image.scp_original_image_type, "n/a")
}
output "diag_image_visibility" {
  value = try(data.samsungcloudplatformv2_virtualserver_image.first.image.visibility, "n/a")
}
output "diag_image_os_version" {
  value = try(data.samsungcloudplatformv2_virtualserver_image.first.image.scp_os_version, "n/a")
}
output "diag_image_min_disk" {
  value = try(data.samsungcloudplatformv2_virtualserver_image.first.image.min_disk, -1)
}
output "diag_image_id" {
  value = try(data.samsungcloudplatformv2_virtualserver_image.first.image.id, "n/a")
}

# SKE prerequisites.
output "filestorage_volume_id" {
  value = samsungcloudplatformv2_filestorage_volume.prereq.id
}
output "kubernetes_version" {
  value = try(data.samsungcloudplatformv2_ske_kubernetes_versions.all.kubernetes_versions[0].kubernetes_version, "NO_K8S_VERSION")
}
output "kubernetes_version_count" {
  value = length(try(data.samsungcloudplatformv2_ske_kubernetes_versions.all.kubernetes_versions, []))
}
