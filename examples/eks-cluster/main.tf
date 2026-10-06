provider "aws" {
  region = "us-east-1"

  # Tags added by the organization's Cloud Custodian (an SCP forbids deleting them)
  ignore_tags {
    keys         = ["Owner"]
    key_prefixes = ["c7n-"]
  }

  default_tags {
    tags = {
      Project   = "poc-gvr"
      Purpose   = "module-example"
      ManagedBy = "terraform"
    }
  }
}

# Who is running Terraform? The session context turns an assumed-role sts ARN into the
# underlying IAM ROLE ARN, which is what an EKS access entry needs.
data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

module "network" {
  source = "../../modules/network"

  name             = var.name
  vpc_cidr         = var.vpc_cidr
  exclude_zone_ids = ["use1-az3"] # EKS has no control plane capacity there

  # The AWS Load Balancer Controller finds internal-ALB subnets by this tag (M3)
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "kms" {
  source = "../../modules/kms"

  name = var.name

  keys = {
    eks = {
      description             = "EKS Kubernetes Secrets envelope encryption"
      deletion_window_in_days = 7 # throwaway test
    }
    logs = {
      description             = "CloudWatch Logs"
      allow_cloudwatch_logs   = true
      deletion_window_in_days = 7
    }
  }
}

module "eks_cluster" {
  source = "../../modules/eks-cluster"

  name               = var.name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.network.private_subnet_ids

  # Private endpoint is always on; public only from your IP, so kubectl works from the laptop
  endpoint_public_access = true
  public_access_cidrs    = [var.admin_cidr]

  encrypt_secrets  = true
  kms_key_arn      = module.kms.key_arns["eks"]
  logs_kms_key_arn = module.kms.key_arns["logs"]

  # Explicit access: you (the role running Terraform) get cluster admin
  access_entries = {
    admin = {
      principal_arn = data.aws_iam_session_context.current.issuer_arn
      policy        = "AmazonEKSClusterAdminPolicy"
    }
  }
}
