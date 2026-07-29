terraform {
  required_providers {
    aws = {
      source  = "hc-registry.website.k2.cloud/c2devel/rockitcloud"
      version = "~> 25.2"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}