terraform {
  required_providers {
    aws = {
      source  = "hc-registry.website.k2.cloud/c2devel/rockitcloud"
      version = "~> 25.2"
    }
  }
}

provider "aws" {
  insecure   = false
  access_key = var.access_key
  secret_key = var.secret_key

  region = "ru-msk"
}