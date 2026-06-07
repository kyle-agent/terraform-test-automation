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

# IAM group policy binding fixture. iam_group and iam_policy are both
# self-contained (already green), so this fixture creates both prerequisites
# in-line and attaches the policy to the group. A second apply with no config
# change must re-plan cleanly (the computed group_policy_bindings list must not
# force a spurious update).
resource "samsungcloudplatformv2_iam_group" "regr" {
  name        = "regr-gpb-grp${var.name_suffix}"
  description = "regression-test group for policy bindings"
}

resource "samsungcloudplatformv2_iam_policy" "regr" {
  policy_name = "regr-gpb-pol${var.name_suffix}"
  description = "regression-test policy for group bindings"

  policy_version = {
    policy_document = {
      version = "2024-10-01"
      statement = [
        {
          sid      = "regrReadOnly"
          effect   = "Allow"
          action   = ["iam:Get*", "iam:List*"]
          resource = ["*"]
        }
      ]
    }
  }
}

resource "samsungcloudplatformv2_iam_group_policy_bindings" "regr" {
  group_id   = samsungcloudplatformv2_iam_group.regr.id
  policy_ids = [samsungcloudplatformv2_iam_policy.regr.id]
}
