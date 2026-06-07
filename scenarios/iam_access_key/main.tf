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

variable "access_key_description" {
  type        = string
  description = "Human-readable description for the access key."
  default     = "regr-access-key"
}

variable "access_key_type" {
  type        = string
  description = "Access key type. Integration runs may override via TF_VAR_access_key_type."
  default     = "PERMANENT"
}

# IAM access key fixture: guards that an access key for the calling identity can
# be declared with an explicit type/description/enabled flag and re-plans cleanly
# (the secret_key/access_key outputs are Computed and must not force replacement).
resource "samsungcloudplatformv2_iam_access_key" "regr" {
  access_key_type = var.access_key_type
  description     = var.access_key_description
  is_enabled      = true
}
