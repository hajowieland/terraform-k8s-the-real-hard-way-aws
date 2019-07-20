provider "aws" {
  version = ">=2.14"
  region  = var.aws_region
  profile = var.aws_profile
}