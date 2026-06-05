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

variable "policy_ids" {
  type        = list(string)
  description = "IAM policy ids attached to the role. The API requires this as a JSON list; integration runs override via TF_VAR_policy_ids."
  default     = ["00000000000000000000000000000000"]
}

variable "role_tags" {
  type        = map(string)
  description = "Tags applied to the role."
  default = {
    tf = "terraform"
  }
}

# IAM role fixture: guards that a role with an assume-role trust policy (one
# Allow statement scoped to a trusted account principal) re-plans cleanly. The
# trusted account is a placeholder; integration supplies the real value via
# TF_VAR_trusted_account_id. policy_ids are left unset to avoid referencing real
# policy ids during offline validation.
resource "samsungcloudplatformv2_iam_role" "regr" {
  name                 = var.role_name
  description          = var.role_description
  max_session_duration = var.max_session_duration
  policy_ids           = var.policy_ids
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
