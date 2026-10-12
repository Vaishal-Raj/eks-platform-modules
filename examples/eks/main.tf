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

# Helm talks to the cluster's API (public endpoint, allowed only from admin_cidr).
# exec = a fresh token on every run via "aws eks get-token" (no kubeconfig file needed).
provider "helm" {
  kubernetes = {
    host                   = module.eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name, "--region", "us-east-1"]
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

# 3a. Internal ALB + empty IP target group (the controller fills it with pod IPs).
#     It may only send traffic to the private subnets, where the pods live.
module "alb" {
  source = "../../modules/alb"

  name                = var.name
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.private_subnet_ids
  target_port         = 8080
  target_egress_cidrs = module.network.private_subnet_cidrs
}

# Send every request to the target group (the module's default action is a fixed response)
resource "aws_lb_listener_rule" "forward_all" {
  listener_arn = module.alb.listener_arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = module.alb.target_group_arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

# 3b. ECR pull-through cache: no NAT, so public images (the controller, the test app)
#     are pulled through ECR, which fetches them from upstream once
module "ecr" {
  source = "../../modules/ecr"

  name = var.name # cache rules only (defaults: ecr-public, k8s, quay); no app repositories
}

# 4. sg-node: added to every node (pods -> VPC endpoints on 443, -> S3 gateway)
module "security_groups" {
  source = "../../modules/security-groups"

  name                    = var.name
  vpc_id                  = module.network.vpc_id
  vpce_security_group_ids = [module.vpc_endpoints.security_group_id]
  alb_security_group_ids  = [module.alb.security_group_id] # ALB -> pods on 8080
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

  # First pull of a cached image creates its ECR repository: the node role needs that right
  additional_policy_jsons = {
    ecr-pull-through-cache = module.ecr.pull_through_cache_policy_json
  }

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

# 10. AWS Load Balancer Controller: keeps the target group in sync with pod IPs (TargetGroupBinding).
#     Least-privilege mode: it can only register/deregister targets in THIS target group.
module "alb_controller" {
  source = "../../modules/alb-controller"

  name              = var.name
  cluster_name      = module.eks_cluster.cluster_name
  vpc_id            = module.network.vpc_id
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_provider     = module.eks_cluster.oidc_provider

  target_group_arns = [module.alb.target_group_arn]

  # public.ecr.aws/eks/aws-load-balancer-controller, through the ECR cache
  image_repository = "${module.ecr.pull_through_cache_urls["ecr-public"]}/eks/aws-load-balancer-controller"

  # Its pods need nodes + CoreDNS; the IRSA token exchange goes through the STS endpoint
  depends_on = [module.addons_after_nodes]
}
