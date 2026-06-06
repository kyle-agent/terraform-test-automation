terraform {
  required_version = ">= 1.6"
  required_providers {
    samsungcloudplatformv2 = {
      source  = "SamsungSDSCloud/samsungcloudplatformv2"
      version = ">= 0.0.1"
    }
    # SCP Object Storage is S3-compatible, so the standard aws provider creates
    # the bucket the network-logging storage requires (same SCP access/secret key
    # via S3 SigV4 against the object-store endpoint). Pinned to the version the
    # CI provider mirror stages (scripts/setup_provider_mirror.sh, MIRROR_AWS=1).
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
  }
}

provider "samsungcloudplatformv2" {}

# Per-run-unique suffix injected by the harness (TF_VAR_name_suffix).
variable "name_suffix" {
  type    = string
  default = ""
}

# OBS S3 credentials + endpoint. Integration supplies these from the same SCP
# keys (TF_VAR_obs_access_key/secret_key) and region/env; defaults keep offline
# `terraform validate` working.
variable "obs_access_key" {
  type    = string
  default = "offline"
}
variable "obs_secret_key" {
  type    = string
  default = "offline"
}
variable "obs_endpoint" {
  type        = string
  description = "SCP Object Storage S3 endpoint."
  default     = "https://object-store.kr-west1.e.samsungsdscloud.com"
}

variable "network_logging_resource_type" {
  type        = string
  description = "Resource type whose traffic is logged. One of FIREWALL, SECURITY_GROUP, NAT."
  default     = "FIREWALL"
}

# aws provider pointed at SCP Object Storage (S3-compatible). Path-style + all the
# skip_* flags so it talks to OBS instead of real AWS.
# region MUST be us-east-1: for any other region the aws provider adds
# CreateBucketConfiguration.LocationConstraint=<region> to CreateBucket, which OBS
# rejects ("InvalidLocationConstraint"). us-east-1 is the one region the SDK omits
# the constraint for. OBS (like most S3-compatible stores) doesn't enforce the SigV4
# signing region, so signing as us-east-1 against the kr-west1 endpoint still authes.
provider "aws" {
  access_key                  = var.obs_access_key
  secret_key                  = var.obs_secret_key
  region                      = "us-east-1"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  endpoints {
    s3 = var.obs_endpoint
  }
}

# The OBS bucket the network-logging storage delivers logs to (self-contained:
# created here, referenced below, destroyed with the scenario).
resource "aws_s3_bucket" "logs" {
  bucket        = "regrnetlog${var.name_suffix}"
  force_destroy = true # empty + delete on destroy so log objects don't block it
}

# Minimal network-logging-storage fixture; both attributes are required.
resource "samsungcloudplatformv2_network_logging_network_logging_storage" "regr" {
  bucket_name   = aws_s3_bucket.logs.bucket
  resource_type = var.network_logging_resource_type
}
