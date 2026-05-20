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

variable "security_group_id" {
  type        = string
  description = "Existing security group id to attach the rule to."
}

# Minimal rule used to detect Chapter 1 #2 (2-A) regression.
# If id is plumbed with RequiresReplace() without UseStateForUnknown(),
# a second `terraform apply` (no config change) will plan -/+ replacement.
resource "samsungcloudplatformv2_security_group_security_group_rule" "regression" {
  security_group_id = var.security_group_id
  ethertype         = "IPv4"
  direction         = "ingress"
  protocol          = "TCP"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "10.0.0.0/24"
  description       = "regression-test"
}
