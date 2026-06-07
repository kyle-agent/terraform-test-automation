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

variable "name" {
  type        = string
  description = "Name of the security group."
  default     = "regr-sg-01"
}

# Per-run-unique suffix injected by the test harness (TF_VAR_name_suffix) so a
# leaked resource from a prior run can't collide with this run's create.
variable "name_suffix" {
  type        = string
  description = "Per-run unique suffix appended to resource names."
  default     = ""
}

variable "description" {
  type        = string
  description = "Free-text description of the security group."
  default     = "regression test sg"
}

variable "loggable" {
  type        = bool
  description = "Whether traffic against this security group is loggable."
  default     = false
}

variable "security_group_tags" {
  type        = map(string)
  description = "Tags applied to the security group."
  default = {
    tf = "terraform"
  }
}

# Standalone security group fixture (NOT the security group rule).
# Guards against idempotency regressions on the security group resource itself:
# a second `terraform apply` with no config change must produce a clean plan
# (no-op, no destroy+create replacement). If an attribute is plumbed as
# Computed + RequiresReplace() without UseStateForUnknown() — the same class of
# bug seen on the rule resource — this fixture would surface it.
resource "samsungcloudplatformv2_security_group_security_group" "securitygroup" {
  name        = "${var.name}${var.name_suffix}"
  description = var.description
  loggable    = var.loggable
  tags        = var.security_group_tags
}
