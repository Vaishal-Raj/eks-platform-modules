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

data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

# 1. Network: private subnets for nodes and pods (no NAT)
module "network" {
  source = "../../modules/network"

  name             = var.name
  vpc_cidr         = var.vpc_cidr
  exclude_zone_ids = ["use1-az3"]

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# 2. VPC endpoints: with no NAT, this is how nodes reach ECR (images), S3 (image layers),
#    EC2 (vpc-cni assigns pod IPs), STS (IRSA) and CloudWatch Logs
module "vpc_endpoints" {
  source = "../../modules/vpc-endpoints"

  name            = var.name
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnet_ids
  allowed_cidrs   = module.network.private_subnet_cidrs
  route_table_ids = [module.network.private_route_table_id]
}

# 3. KMS: Kubernetes Secrets + control plane logs
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

# 4. sg-node: added to every node (pods -> VPC endpoints on 443, -> S3 gateway)
module "security_groups" {
  source = "../../modules/security-groups"

  name                    = var.name
  vpc_id                  = module.network.vpc_id
  vpce_security_group_ids = [module.vpc_endpoints.security_group_id]
  create_rds_sg           = false
  create_cache_sg         = false
}

# 5. Control plane
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  name                   = var.name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = module.network.private_subnet_ids
  endpoint_public_access = true
  public_access_cidrs    = [var.admin_cidr]

  encrypt_secrets  = true
  kms_key_arn      = module.kms.key_arns["eks"]
  logs_kms_key_arn = module.kms.key_arns["logs"]

  access_entries = {
    admin = { principal_arn = data.aws_iam_session_context.current.issuer_arn }
  }
}

# 6. Add-ons nodes need BEFORE they can become Ready: pod networking + Service routing
module "addons_before_nodes" {
  source = "../../modules/eks-addons"

  cluster_name       = module.eks_cluster.cluster_name
  kubernetes_version = module.eks_cluster.cluster_version

  addons = {
    "vpc-cni"    = {}
    "kube-proxy" = {}
  }

  # The VPC endpoints must exist first: vpc-cni calls the EC2 API through them
  depends_on = [module.vpc_endpoints]
}

# 7. Worker nodes (EC2) in the private subnets
module "node_group" {
  source = "../../modules/eks-node-group"

  name                          = "${var.name}-default"
  cluster_name                  = module.eks_cluster.cluster_name
  subnet_ids                    = module.network.private_subnet_ids
  cluster_security_group_id     = module.eks_cluster.cluster_security_group_id
  additional_security_group_ids = [module.security_groups.node_security_group_id]

  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND" # SPOT is cheaper for dev, but can be interrupted

  scaling = {
    min_size     = 1
    max_size     = 3
    desired_size = 2
  }

  labels = {
    role = "general"
  }

  depends_on = [module.addons_before_nodes]
}

# 8. IRSA role for the EBS CSI driver: ONLY its controller's ServiceAccount may assume it,
#    and it may only do what AmazonEBSCSIDriverPolicy allows (create/attach/delete EBS volumes)
module "ebs_csi_irsa" {
  source = "../../modules/irsa-role"

  name              = "${var.name}-ebs-csi"
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_provider     = module.eks_cluster.oidc_provider

  service_accounts = [
    { namespace = "kube-system", name = "ebs-csi-controller-sa" },
  ]

  policy_arns = {
    ebs = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }
}

# 9. Add-ons that run as pods, so they need nodes first
module "addons_after_nodes" {
  source = "../../modules/eks-addons"

  cluster_name       = module.eks_cluster.cluster_name
  kubernetes_version = module.eks_cluster.cluster_version

  addons = {
    "coredns"        = {}
    "metrics-server" = {}

    # Persistent volumes on EBS. Its pods call the EC2 API with the IRSA role above
    # (token exchange via the STS endpoint, EC2 calls via the ec2 endpoint: no NAT)
    "aws-ebs-csi-driver" = {
      service_account_role_arn = module.ebs_csi_irsa.role_arn
    }
  }

  depends_on = [module.node_group]
}
