# Provider configuration for Cognito resources
# ConnectX Pattern: No backend, only provider

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider configuration is inherited from parent module
# No explicit provider block needed here
