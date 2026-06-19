terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "eks-iac-tfstate-rd95"
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "eks-iac-tf-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
}
