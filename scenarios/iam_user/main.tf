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

# Owning account id. account_id is the {account_id} PATH segment of
# POST /v1/accounts/{account_id}/users and is server-side REQUIRED; omitting it
# made the provider send an empty path segment that surfaced as a misleading
# "401 [HMAC] HMAC valid fail" (fork issue #74). The harness injects the real
# test account via TF_VAR_account_id (vars.SCP_ACCOUNT_ID) in every lane.
variable "account_id" {
  type        = string
  description = "Owning account id; injected by the harness via TF_VAR_account_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

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

# The Update API REQUIRES password_reuse_count and rejects 0 ("Input should be
# greater than 0"); create allows omitting it (server default). Set a valid (>0)
# value so the in-place update carries it. See fork #74 follow-up / PRs #101/#102:
# no provider/SDK change can supply this — the config must.
variable "password_reuse_count" {
  type        = number
  description = "Number of previous passwords that cannot be reused (API requires > 0 on update)."
  default     = 2
}

# IAM user fixture: guards idempotency on the user resource. A second apply with
# no config change must produce a clean plan (no destroy+create). group_ids /
# policy_ids are left unset so the fixture validates without referencing real
# ids; integration runs attach them via TF_VAR_*.
resource "samsungcloudplatformv2_iam_user" "regr" {
  account_id           = var.account_id
  user_name            = var.user_name
  description          = var.user_description
  tags                 = var.user_tags
  password_reuse_count = var.password_reuse_count
}
