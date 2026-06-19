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
# "401 [HMAC] HMAC valid fail" (fork issue #74), which previously presented as
# the group-member failure here. The harness injects the real test account via
# TF_VAR_account_id (vars.SCP_ACCOUNT_ID) in every lane.
variable "account_id" {
  type        = string
  description = "Owning account id; injected by the harness via TF_VAR_account_id."
  default     = "00000000-0000-0000-0000-000000000000"
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
  account_id  = var.account_id
  user_name   = "regr-gm-user${var.name_suffix}"
  description = "regression-test user for membership"

  # Root cause of the historical "401 [HMAC] HMAC valid fail" here was NOT a
  # signing race but the missing account_id on this user create (fork issue
  # #74) - now supplied above. depends_on is retained only to order group
  # before membership; it has no bearing on the (disproven) race theory.
  depends_on = [samsungcloudplatformv2_iam_group.regr]
}

resource "samsungcloudplatformv2_iam_group_member" "regr" {
  group_id = samsungcloudplatformv2_iam_group.regr.id
  user_id  = samsungcloudplatformv2_iam_user.regr.user_id
}
