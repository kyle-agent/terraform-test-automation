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

variable "group_name" {
  type        = string
  description = "Name of the IAM group."
  default     = "regr-iam-group"
}

variable "group_description" {
  type        = string
  description = "Free-text description of the IAM group."
  default     = "regression test IAM group"
}

variable "group_tags" {
  type        = map(string)
  description = "Tags applied to the group."
  default = {
    tf = "terraform"
  }
}

# IAM group fixture: guards idempotency on the group resource itself. A second
# apply with no config change must produce a clean plan (no destroy+create).
# policy_ids / user_ids are left unset so the fixture validates without
# referencing real ids; integration runs attach them via TF_VAR_*.
resource "samsungcloudplatformv2_iam_group" "regr" {
  name        = var.group_name
  description = var.group_description
  tags        = var.group_tags
}
