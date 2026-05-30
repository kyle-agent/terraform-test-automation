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

# AUTO-GENERATED minimal coverage fixture (scripts/gen_scenarios.py).
# Validated against the real provider schema. Exercised in dry-run by the
# tests/schema validate sweep; extend with integration assertions to promote.

resource "samsungcloudplatformv2_vpn_vpn_tunnel" "regr" {
  name = "regr"
  phase1 = {
      dpd_retry_interval = 1
      ike_version = 1
      peer_gateway_ip = "10.0.0.10"
      phase1_diffie_hellman_groups = [1]
      phase1_encryptions = ["regr"]
      phase1_life_time = 1
      pre_shared_key = "regr"
    }
  phase2 = {
      perfect_forward_secrecy = "ENABLE"
      phase2_diffie_hellman_groups = [1]
      phase2_encryptions = ["regr"]
      phase2_life_time = 1
      remote_subnets = ["10.0.0.0/24"]
    }
  vpn_gateway_id = "00000000-0000-0000-0000-000000000000"
}
