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
  description = "Existing IAM group id to bind policies to. Integration runs override via TF_VAR_group_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "policy_ids" {
  type        = list(string)
  description = "IAM policy ids to attach to the group. Integration runs override via TF_VAR_policy_ids."
  default     = ["00000000-0000-0000-0000-000000000000"]
}

# IAM group policy binding fixture: guards that attaching a set of policies to a
# group re-plans cleanly (the computed group_policy_bindings list must not force
# a spurious update). ids are placeholders (zero-UUID); integration supplies the
# real group_id / policy_ids via TF_VAR_*.
resource "samsungcloudplatformv2_iam_group_policy_bindings" "regr" {
  group_id   = var.group_id
  policy_ids = var.policy_ids
}
