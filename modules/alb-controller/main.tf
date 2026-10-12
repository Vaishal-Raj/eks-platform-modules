# AWS Load Balancer Controller: connects Kubernetes to load balancers.
#
# In this platform Terraform owns the internal ALB, listener and target group (alb module).
# The controller's only job is TargetGroupBinding: keep the target group's list of pod IPs
# in sync with a Kubernetes Service, so CloudFront -> WAF -> ALB -> pods works.
#
#   Service "api" (pods 10.0.3.17, 10.0.18.42 …)
#        │  TargetGroupBinding (created by the app's Helm chart, M3/M4)
#        ▼
#   controller ──IRSA──► elasticloadbalancing:RegisterTargets / DeregisterTargets  (ONLY these target groups)
#        ▼
#   target group client-a-dev-tg  ◄── internal ALB ◄── CloudFront VPC origin

data "aws_region" "current" {}

locals {
  # Least privilege for TargetGroupBinding: read what it needs, write only to our target groups.
  # Describe*/Get* actions can't be limited to specific resources in IAM, so they stay on "*".
  # They are the read-only EC2/ELB actions of AWS's published policy (it reads VPCs, subnets,
  # security groups, ENIs, route tables… on startup and on every reconcile).
  target_group_binding_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOnly"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:Describe*",
          "ec2:Describe*",
          "ec2:GetSecurityGroupsForVpc",
          "ec2:GetCoipPoolUsage",
        ]
        Resource = "*"
      },
      {
        Sid      = "RegisterPodIpsInOurTargetGroupsOnly"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
        Resource = var.target_group_arns
      },
    ]
  })

  full_policy = file("${path.module}/policies/aws-published-v3.6.0.json")

  values = {
    clusterName  = var.cluster_name
    region       = data.aws_region.current.region
    vpcId        = var.vpc_id # pods can't read it from EC2 metadata (IMDS hop limit 1)
    replicaCount = var.replica_count

    serviceAccount = {
      create      = true
      name        = var.service_account_name
      annotations = { "eks.amazonaws.com/role-arn" = module.irsa.role_arn }
    }

    enableServiceMutatorWebhook = var.enable_service_mutator_webhook
  }

  image_values = var.image_repository == null ? {} : { image = { repository = var.image_repository } }
}

# ---------------- IRSA role: only this controller's ServiceAccount can assume it ----------------

module "irsa" {
  source = "../irsa-role"

  name              = "${var.name}-alb-controller"
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider     = var.oidc_provider

  service_accounts = [
    { namespace = var.namespace, name = var.service_account_name },
  ]

  inline_policies = {
    "alb-controller" = var.policy_mode == "full" ? local.full_policy : local.target_group_binding_policy
  }

  tags = var.tags
}

# ---------------- Helm release ----------------

resource "helm_release" "this" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = var.namespace

  values = concat(
    [yamlencode(merge(local.values, local.image_values))],
    var.extra_values,
  )

  # Wait until the controller pods are Ready; roll back automatically if they never are
  wait    = true
  atomic  = true
  timeout = 600

  lifecycle {
    precondition {
      condition     = var.policy_mode == "full" || length(var.target_group_arns) > 0
      error_message = "policy_mode = target-group-binding needs target_group_arns (the alb module's target_group_arn)."
    }
  }
}
