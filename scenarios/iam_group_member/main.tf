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
  type        = string
  description = "Per-run unique suffix appended to resource names."
  default     = ""
}

# IAM group membership fixture. iam_group and iam_user are both self-contained
# (already green), so this fixture creates both prerequisites in-line and binds
# the user into the group. A second apply with no config change must re-plan
# cleanly (the computed membership list must not force a spurious update).
resource "samsungcloudplatformv2_iam_group" "regr" {
  name        = "regr-gm-grp${var.name_suffix}"
  description = "regression-test group for membership"
}

resource "samsungcloudplatformv2_iam_user" "regr" {
  user_name   = "regr-gm-user${var.name_suffix}"
  description = "regression-test user for membership"
}

resource "samsungcloudplatformv2_iam_group_member" "regr" {
  group_id = samsungcloudplatformv2_iam_group.regr.id
  user_id  = samsungcloudplatformv2_iam_user.regr.id
}
