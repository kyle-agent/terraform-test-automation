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

# Leaked test VPCs found by the read-only cleanup inventory (run 26940226478),
# left ACTIVE because their dependent-probe teardown did not complete (cancelled
# hung run #28, an LB still CREATING blocking subnet deletion (#77), and #60
# vpc_cidr non-idempotency). Imported by id and destroyed by the cleanup-destroy
# workflow. cidr values below are placeholders — import overwrites them from the
# live resource and destroy ignores attributes. demosvc1 (the pre-existing
# account VPC) is intentionally NOT listed and is never touched.
resource "samsungcloudplatformv2_vpc_vpc" "leak_lb" {
  name = "rpv26932747382" # id 12fe48eb49d84badbafe07301798e228 (LB batch run)
  cidr = "10.0.0.0/16"
}

resource "samsungcloudplatformv2_vpc_vpc" "leak_hung" {
  name = "rpv26931772155" # id 2ccff235ab6241508394422210e6364d (hung run #28)
  cidr = "10.1.0.0/16"
}

resource "samsungcloudplatformv2_vpc_vpc" "leak_iam" {
  name = "rpv26930664260" # id aad715dd6171489bbb64527902666c10 (iam_group+subnet run)
  cidr = "10.2.0.0/16"
}

resource "samsungcloudplatformv2_vpc_vpc" "leak_old" {
  name = "rpv26929915009" # id 7e718685f29b42648958b4ab0d0abf7e (earlier run)
  cidr = "10.3.0.0/16"
}
