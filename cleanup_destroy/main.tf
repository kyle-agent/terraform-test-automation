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

# Leaked test VPCs (created by this automation's dependent-probe run 26797061130,
# whose teardown failed because the vpc_cidr resource is non-idempotent — see
# provider bug #60). Imported and destroyed by the cleanup-destroy workflow.
# demosvc1 is a pre-existing account VPC and is intentionally NOT listed.
resource "samsungcloudplatformv2_vpc_vpc" "leak1" {
  name = "rpv26797061130"
  cidr = "192.168.0.0/24"
}

resource "samsungcloudplatformv2_vpc_vpc" "leak2" {
  name = "rpv226797061130"
  cidr = "192.169.0.0/24"
}
