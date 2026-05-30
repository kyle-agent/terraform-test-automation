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

# Promoted regression fixture: a VPN tunnel with full IKE phase1/phase2 IPsec
# parameters. vpn_gateway_id / pre_shared_key default to placeholders and are
# overridable via TF_VAR_*; schema-valid defaults keep validate green offline.

variable "tunnel_name" {
  description = "VPN tunnel name."
  type        = string
  default     = "regr-vpn-tunnel"
}

variable "vpn_gateway_id" {
  description = "VPN gateway UUID this tunnel terminates on."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "peer_gateway_ip" {
  description = "Remote (peer) gateway public IP address."
  type        = string
  default     = "10.0.0.20"
}

variable "pre_shared_key" {
  description = "IPsec pre-shared key for the tunnel."
  type        = string
  sensitive   = true
  default     = "regr-pre-shared-key"
}

variable "remote_subnets" {
  description = "Remote (peer) subnets reachable through the tunnel."
  type        = list(string)
  default     = ["10.0.0.0/24"]
}

resource "samsungcloudplatformv2_vpn_vpn_tunnel" "regr" {
  name           = var.tunnel_name
  vpn_gateway_id = var.vpn_gateway_id
  description    = "Regression VPN tunnel fixture"

  phase1 = {
    ike_version                  = 2
    peer_gateway_ip              = var.peer_gateway_ip
    phase1_diffie_hellman_groups = [14]
    phase1_encryptions           = ["aes256"]
    phase1_life_time             = 86400
    pre_shared_key               = var.pre_shared_key
    dpd_retry_interval           = 30
  }

  phase2 = {
    perfect_forward_secrecy      = "ENABLE"
    phase2_diffie_hellman_groups = [14]
    phase2_encryptions           = ["aes256"]
    phase2_life_time             = 3600
    remote_subnets               = var.remote_subnets
  }

  tags = {
    env = "regression"
  }
}
