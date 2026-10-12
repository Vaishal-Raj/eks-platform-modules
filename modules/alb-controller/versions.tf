terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    # The caller configures this provider to reach the cluster's API (see examples/eks)
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
  }
}
