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

variable "group_id" {
  type        = string
  description = "Existing IAM group id to add the member to. Integration runs override via TF_VAR_group_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "user_id" {
  type        = string
  description = "Existing IAM user id to add as a group member. Integration runs override via TF_VAR_user_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

# IAM group membership fixture: guards that binding a user into a group re-plans
# cleanly. Both ids are placeholders (zero-UUID) so the fixture validates
# offline; integration supplies real group_id / user_id via TF_VAR_*.
resource "samsungcloudplatformv2_iam_group_member" "regr" {
  group_id = var.group_id
  user_id  = var.user_id
}
