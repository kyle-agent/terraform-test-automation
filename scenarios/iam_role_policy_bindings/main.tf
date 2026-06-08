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

# SELF-CONTAINED: this fixture creates its own iam_role and iam_policy and binds
# them together, so it no longer depends on an externally-provided role_id /
# policy_ids (previously registry-marked broken: "404 needs own role"). The
# iam_role / iam_policy resource shapes mirror the known-good iam_role scenario.
#
# RISK (provider issue #75): iam_role *create* may itself be provider-broken. This
# fixture is schema-valid and dependency-complete (terraform validate passes), but
# a real apply could still fail at role-create time until #75 is resolved. Real
# apply is exercised later in CI.

resource "samsungcloudplatformv2_iam_policy" "regr" {
  policy_name = "regrrolepol${var.name_suffix}"
  description = "regression-test policy for role bindings"

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

resource "samsungcloudplatformv2_iam_role" "regr" {
  name                 = "regrrole${var.name_suffix}"
  description          = "regression-test role for policy bindings"
  max_session_duration = 3600

  assume_role_policy_document = {
    version = "2024-07-01"
    statement = [
      {
        sid      = "regrAssumeRole"
        effect   = "Allow"
        action   = ["sts:AssumeRole"]
        resource = ["*"]
        principal = {
          principal_map = {
            Account = ["000000000000"]
          }
        }
      }
    ]
  }
}

# IAM role policy binding fixture: attaches the policy created above to the role
# created above. A second apply with no config change must re-plan cleanly (the
# computed role_policy_bindings list must not force a spurious update).
resource "samsungcloudplatformv2_iam_role_policy_bindings" "regr" {
  role_id    = samsungcloudplatformv2_iam_role.regr.id
  policy_ids = [samsungcloudplatformv2_iam_policy.regr.id]
}
