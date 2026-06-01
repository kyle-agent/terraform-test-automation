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
  description = "Name of the virtual server keypair."
  default     = "regr-keypair"
}

# Per-run-unique suffix injected by the test harness (TF_VAR_name_suffix) so a
# leaked keypair from a prior run can't collide with this run's create.
variable "name_suffix" {
  type        = string
  description = "Per-run unique suffix appended to resource names."
  default     = ""
}

# Virtual server keypair fixture.
# Guards against idempotency regressions on the keypair resource: re-running
# plan/apply with no config change must be a clean no-op with no replacement.
# The keypair's public/private key material is Computed; if it is not stabilized
# with UseStateForUnknown(), a second plan would churn (-/+) the resource.
resource "samsungcloudplatformv2_virtualserver_keypair" "keypair" {
  name = "${var.name}${var.name_suffix}"
  tags = {
    "regr" : "terraform"
  }
}
