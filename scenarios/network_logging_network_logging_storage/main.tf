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

# Per-run-unique suffix injected by the harness (TF_VAR_name_suffix).
variable "name_suffix" {
  type    = string
  default = ""
}

variable "network_logging_resource_type" {
  type        = string
  description = "Resource type whose traffic is logged. One of FIREWALL, SECURITY_GROUP, NAT."
  default     = "FIREWALL"
}

locals {
  bucket = "regrnetlog${var.name_suffix}"
}

# The OBS bucket the network-logging storage delivers logs to.
#
# SCP Object Storage is S3-compatible, but the terraform aws_s3_bucket resource does
# NOT work against it: its post-create Read fans out to GetBucketPolicy / ACL / CORS /
# lifecycle and only tolerates AWS's exact "not configured" error codes, while OBS
# answers GetBucketPolicy with a generic 404 ("Policy does not exist") that the
# provider surfaces as a hard error. So we drive the bucket lifecycle with a tiny
# boto3 S3 client (scripts/obs_bucket.py) via local-exec instead -- create on apply,
# delete on destroy. Credentials + endpoint come from the process environment
# (TF_VAR_obs_access_key / _secret_key / _endpoint), so the destroy-time provisioner
# needs no variable references. OBS_BUCKET_SCRIPT is the absolute path to the helper.
resource "terraform_data" "bucket" {
  input = local.bucket

  provisioner "local-exec" {
    command = "python3 \"$OBS_BUCKET_SCRIPT\" create \"${self.input}\""
  }
  provisioner "local-exec" {
    when    = destroy
    command = "python3 \"$OBS_BUCKET_SCRIPT\" delete \"${self.input}\""
  }
}

# Minimal network-logging-storage fixture; both attributes are required.
resource "samsungcloudplatformv2_network_logging_network_logging_storage" "regr" {
  bucket_name   = local.bucket
  resource_type = var.network_logging_resource_type
  depends_on    = [terraform_data.bucket]
}
