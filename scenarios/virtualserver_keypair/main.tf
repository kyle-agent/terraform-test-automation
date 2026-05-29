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

# Virtual server keypair fixture.
# Guards against idempotency regressions on the keypair resource: re-running
# plan/apply with no config change must be a clean no-op with no replacement.
# The keypair's public/private key material is Computed; if it is not stabilized
# with UseStateForUnknown(), a second plan would churn (-/+) the resource.
resource "samsungcloudplatformv2_virtualserver_keypair" "keypair" {
  name = var.name
  tags = {
    "regr" : "terraform"
  }
}
