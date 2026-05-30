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

variable "policy_name" {
  type        = string
  description = "Name of the IAM policy."
  default     = "regr-iam-policy"
}

variable "policy_description" {
  type        = string
  description = "Free-text description of the IAM policy."
  default     = "regression test IAM policy"
}

variable "policy_resource" {
  type        = list(string)
  description = "Resource SRNs the policy statement applies to. Integration runs override via TF_VAR_policy_resource."
  default     = ["*"]
}

variable "policy_tags" {
  type        = map(string)
  description = "Tags applied to the policy."
  default = {
    tf = "terraform"
  }
}

# IAM policy fixture: guards that a customer-managed policy with a single
# read-only Allow statement re-plans cleanly. The policy_version block carries a
# minimal-but-valid policy document (version + one statement with effect/action/
# resource); the computed `policy` block must not force replacement.
resource "samsungcloudplatformv2_iam_policy" "regr" {
  policy_name = var.policy_name
  description = var.policy_description
  tags        = var.policy_tags

  policy_version = {
    policy_document = {
      version = "2024-10-01"
      statement = [
        {
          sid      = "regrReadOnly"
          effect   = "Allow"
          action   = ["iam:Get*", "iam:List*"]
          resource = var.policy_resource
        }
      ]
    }
  }
}
