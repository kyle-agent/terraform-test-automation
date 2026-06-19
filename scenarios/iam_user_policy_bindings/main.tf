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

# Owning account id for the in-line iam_user. account_id is the {account_id}
# PATH segment of POST /v1/accounts/{account_id}/users and is server-side
# REQUIRED; omitting it made the user create surface a misleading
# "401 [HMAC] HMAC valid fail" (fork issue #74), which previously blocked this
# scenario. The harness injects the real test account via TF_VAR_account_id
# (vars.SCP_ACCOUNT_ID) in every lane.
variable "account_id" {
  type        = string
  description = "Owning account id; injected by the harness via TF_VAR_account_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

# IAM user policy binding fixture. iam_user (with account_id) and iam_policy are
# both self-contained, so this fixture creates both prerequisites in-line and
# attaches the policy to the user. A second apply with no config change must
# re-plan cleanly (the computed user_policy_bindings list must not force a
# spurious update).
resource "samsungcloudplatformv2_iam_user" "regr" {
  account_id  = var.account_id
  user_name   = "regr-upb-user${var.name_suffix}"
  description = "regression-test user for policy bindings"
}

resource "samsungcloudplatformv2_iam_policy" "regr" {
  policy_name = "regr-upb-pol${var.name_suffix}"
  description = "regression-test policy for user bindings"

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

resource "samsungcloudplatformv2_iam_user_policy_bindings" "regr" {
  user_id    = samsungcloudplatformv2_iam_user.regr.user_id
  policy_ids = [samsungcloudplatformv2_iam_policy.regr.id]
}
