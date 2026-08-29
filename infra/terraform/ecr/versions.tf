# Verify current provider versions before your first init.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project    = var.project
      Owner      = var.owner
      ManagedBy  = "terraform"
      Repository = "gxp-gitops-platform"
      Stack      = "ecr"
    }
  }
}
