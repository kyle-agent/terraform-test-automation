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

variable "firewall_id" {
  type        = string
  description = "Existing firewall id to attach the rule to. Integration runs override via TF_VAR_firewall_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

# Firewall rule fixture guarding firewall coverage: an inbound ALLOW rule with a
# single TCP service must re-plan cleanly (no spurious update or replacement).
# Required: firewall_id and the firewall_rule_create object (action, direction,
# status, source/destination_address lists, and a service list).
resource "samsungcloudplatformv2_firewall_firewall_rule" "regr" {
  firewall_id = var.firewall_id
  firewall_rule_create = {
    action              = "ALLOW"
    direction           = "INBOUND"
    status              = "ENABLE"
    description         = "regr-test"
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
