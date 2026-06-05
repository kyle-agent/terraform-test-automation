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

# Promoted regression fixture: a GSLB with a round-robin algorithm, an HTTP
# health check and a weighted backend resource. Inputs overridable via TF_VAR_*;
# schema-valid defaults keep `terraform validate` green offline.

variable "gslb_name" {
  description = "GSLB display name."
  type        = string
  default     = "regr-gslb"
}

variable "gslb_algorithm" {
  description = "Load-balancing algorithm enum (e.g. ROUND_ROBIN, RATIO)."
  type        = string
  default     = "ROUND_ROBIN"
}

variable "env_usage" {
  description = "Environment usage enum for the GSLB (e.g. PUBLIC, PRIVATE)."
  type        = string
  default     = "PUBLIC"
}

variable "backend_destination" {
  description = "Backend destination IP/host for the GSLB resource."
  type        = string
  default     = "10.0.0.10"
}

resource "samsungcloudplatformv2_gslb_gslb" "regr" {
  gslb_create = {
    algorithm   = var.gslb_algorithm
    env_usage   = var.env_usage
    name        = var.gslb_name
    description = "Regression GSLB fixture"

    health_check = {
      protocol                   = "HTTP"
      service_port               = 80
      send_string                = "GET / HTTP/1.0\r\n\r\n"
      health_check_interval      = 5
      health_check_probe_timeout = 6
      timeout                    = 10
    }

    resources = [
      {
        description = "Primary regression backend"
        destination = var.backend_destination
        region      = "kr-west1"
        weight      = 100
      }
    ]
  }

  tags = {
    env = "regression"
  }
}
