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

# regr:no-validate
# This fixture is intentionally partial: the resource block omits required
# arguments (filled via TF_VAR_* / imported state in the integration variant),
# so `terraform validate` would correctly reject it with "Missing required
# argument". The schema sweep (tests/schema) skips it via the marker above.
#
# Empty placeholder used by Chapter 1 #6 import smoke.
# The test runs `terraform import <addr> <id>` against this dir; the resource
# block itself is not strictly required for `import` to invoke the provider's
# ImportState plumbing, but we keep one minimal block per supported resource
# so subsequent `terraform plan` can be added in the integration variant.
resource "samsungcloudplatformv2_multinodegpucluster_gpunode" "target" {
  # Fields intentionally left for the test's TF_VAR_* injection.
  # The integration variant fills these from the imported state.
}
