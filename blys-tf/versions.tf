terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.42"
    }
  }

  # Uncomment to enable remote state (recommended for production)
  # backend "s3" {
  #   bucket         = "blys-terraform-state"
  #   key            = "prod/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "blys-terraform-locks"
  #   encrypt        = true
  # }
}
