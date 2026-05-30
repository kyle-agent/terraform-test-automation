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

# Promoted regression fixture: a resource group scoped to a region with a tag
# selector. Inputs overridable via TF_VAR_*; schema-valid defaults keep
# `terraform validate` green offline.

variable "group_name" {
  description = "Resource group display name."
  type        = string
  default     = "regr-resource-group"
}

variable "region" {
  description = "SCP region the resource group is scoped to."
  type        = string
  default     = "kr-west1"
}

variable "resource_types" {
  description = "Resource type strings included in the group."
  type        = list(string)
  default     = ["compute:virtualserver"]
}

resource "samsungcloudplatformv2_resourcemanager_resource_group" "regr" {
  name           = var.group_name
  description    = "Regression resource group fixture"
  region         = var.region
  resource_types = var.resource_types

  group_definition_tags = {
    env = "regression"
  }

  tags = {
    env = "regression"
  }
}
