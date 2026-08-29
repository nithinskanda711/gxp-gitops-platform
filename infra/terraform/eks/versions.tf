# NOTE: verify current module and provider versions before your first init.
# These pins were correct at the time of writing and the upstream modules
# publish breaking changes across majors more often than you would like.
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
    tags = local.common_tags
  }
}
