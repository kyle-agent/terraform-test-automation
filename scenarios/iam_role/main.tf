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

variable "role_name" {
  type        = string
  description = "Name of the IAM role."
  default     = "regr-iam-role"
}

variable "role_description" {
  type        = string
  description = "Free-text description of the IAM role."
  default     = "regression test IAM role"
}

variable "max_session_duration" {
  type        = number
  description = "Maximum assumed-role session duration in seconds."
  default     = 3600
}

variable "trusted_account_id" {
  type        = string
  description = "Account id trusted to assume the role. Integration runs override via TF_VAR_trusted_account_id."
  default     = "000000000000"
}

variable "role_tags" {
  type        = map(string)
  description = "Tags applied to the role."
  default = {
    tf = "terraform"
  }
}

# SELF-CONTAINED: create a real customer-managed IAM policy in this fixture and
# attach it to the role via policy_ids. Previously policy_ids held a zero-UUID
# placeholder, which the API rejected with "No Policy found with ID 0000...0000".
# The policy document mirrors the iam_policy scenario's known-good fixture.
resource "samsungcloudplatformv2_iam_policy" "regr" {
  policy_name = "regr-iam-role-policy"
  description = "regression test IAM policy for iam_role"
  tags = {
    tf = "terraform"
  }

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

# IAM role fixture: guards that a role with an assume-role trust policy (one
# Allow statement scoped to a trusted account principal) re-plans cleanly. The
# trusted account is a placeholder; integration supplies the real value via
# TF_VAR_trusted_account_id. policy_ids references the policy created above so
# the role attaches a real, existing policy.
resource "samsungcloudplatformv2_iam_role" "regr" {
  name                 = var.role_name
  description          = var.role_description
  max_session_duration = var.max_session_duration
  policy_ids           = [samsungcloudplatformv2_iam_policy.regr.id]
  tags                 = var.role_tags

  assume_role_policy_document = {
    version = "2024-07-01"
    statement = [
      {
        sid       = "regrAssumeRole"
        effect    = "Allow"
        action    = ["sts:AssumeRole"]
        resource  = ["*"]
        condition = {}
        principal = {
          principal_map = {
            Account = [var.trusted_account_id]
          }
        }
      }
    ]
  }
}
