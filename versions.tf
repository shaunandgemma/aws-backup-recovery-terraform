terraform {
  required_version = "~> 1.16.0"

  cloud {
    organization = "shaun-estcourt-labs"

    workspaces {
      name = "aws-backup-recovery-lab"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}