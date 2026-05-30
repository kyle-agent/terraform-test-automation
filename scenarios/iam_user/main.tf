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

variable "user_name" {
  type        = string
  description = "Login name of the IAM user."
  default     = "regr-iam-user"
}

variable "user_description" {
  type        = string
  description = "Free-text description of the IAM user."
  default     = "regression test IAM user"
}

variable "user_tags" {
  type        = map(string)
  description = "Tags applied to the user."
  default = {
    tf = "terraform"
  }
}

# IAM user fixture: guards idempotency on the user resource. A second apply with
# no config change must produce a clean plan (no destroy+create). group_ids /
# policy_ids are left unset so the fixture validates without referencing real
# ids; integration runs attach them via TF_VAR_*.
resource "samsungcloudplatformv2_iam_user" "regr" {
  user_name   = var.user_name
  description = var.user_description
  tags        = var.user_tags
}
