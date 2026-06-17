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

variable "firewall_rule_description" {
  type        = string
  description = "Description of the firewall rule (in-place updatable via UpdateFirewallRule; maxLength 100)."
  default     = "regr-test"
}

# Firewall rule fixture guarding firewall coverage: an inbound ALLOW rule with a
# single TCP service must re-plan cleanly (no spurious update or replacement).
# Required: firewall_id and the firewall_rule_create object (action, direction,
# status, source/destination_address lists, and a service list).
#
# SELF-CONTAINED: a firewall_id is needed to attach the rule to, but bare
# firewalls cannot be provisioned directly. Instead we create our own VPC (+
# subnet) and an Internet Gateway with firewall_enabled=true; the IGW
# auto-creates a firewall and exposes its id via the computed firewall_id
# attribute, which we wire into the rule. No externally-provided firewall_id
# is required.
resource "samsungcloudplatformv2_vpc_vpc" "regr" {
  name        = "regrfwvpc${var.name_suffix}"
  cidr        = "192.168.0.0/24"
  description = "regr-test firewall rule vpc"
}

resource "samsungcloudplatformv2_vpc_subnet" "regr" {
  name            = "regrfwsub${var.name_suffix}"
  vpc_id          = samsungcloudplatformv2_vpc_vpc.regr.id
  type            = "GENERAL"
  cidr            = "192.168.0.0/27"
  description     = "regr-test firewall rule subnet"
  dns_nameservers = ["8.8.8.8"]
}

resource "samsungcloudplatformv2_vpc_internet_gateway" "regr" {
  type              = "IGW"
  vpc_id            = samsungcloudplatformv2_vpc_vpc.regr.id
  description       = "regr-test firewall rule igw"
  firewall_enabled  = true
  firewall_loggable = false
}

resource "samsungcloudplatformv2_firewall_firewall_rule" "regr" {
  firewall_id = samsungcloudplatformv2_vpc_internet_gateway.regr.internet_gateway.firewall_id
  firewall_rule_create = {
    action              = "ALLOW"
    direction           = "INBOUND"
    status              = "ENABLE"
    description         = var.firewall_rule_description
    source_address      = ["192.168.1.0/24"]
    destination_address = ["192.168.2.0/24"]
    service = [
      {
        service_type  = "TCP"
        service_value = "443"
      }
    ]
  }
}
