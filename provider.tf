provider "aws" {
  region = "eu-west-2"

  allowed_account_ids = ["652656942006"]

  default_tags {
    tags = {
      Project = "backup-recovery"
    }
  }
}