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

variable "server_group_name" {
  type        = string
  description = "Name of the server group. Integration overrides via TF_VAR_server_group_name."
  default     = "regr-server-group"
}

# Name and policy are immutable in the provider (Update rejects changes), so
# tags are the only in-place-updatable attribute. The capability matrix update
# stage mutates this map to exercise tag.UpdateTags.
variable "tags" {
  type        = map(string)
  description = "Resource tags (the only in-place-updatable attribute of a server group)."
  default     = { "regr" = "terraform" }
}

# Virtual server placement group fixture.
# Guards the affinity/anti-affinity server group: required name plus a valid
# placement policy enum, so members spread across distinct hosts.
resource "samsungcloudplatformv2_virtualserver_server_group" "regr" {
  name   = var.server_group_name
  policy = "anti-affinity"

  tags = var.tags
}
