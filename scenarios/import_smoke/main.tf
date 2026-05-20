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

# Empty placeholder used by Chapter 1 #6 import smoke.
# The test runs `terraform import <addr> <id>` against this dir; the resource
# block itself is not strictly required for `import` to invoke the provider's
# ImportState plumbing, but we keep one minimal block per supported resource
# so subsequent `terraform plan` can be added in the integration variant.
resource "samsungcloudplatformv2_multinodegpucluster_gpunode" "target" {
  # Fields intentionally left for the test's TF_VAR_* injection.
  # The integration variant fills these from the imported state.
}
