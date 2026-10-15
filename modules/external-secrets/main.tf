# External Secrets Operator (ESO): copies secrets from AWS Secrets Manager into Kubernetes Secrets.
#
# Passwords never go into Git, Helm values or Terraform variables. The app only says WHICH secret it wants:
#
#   Secrets Manager  rds!db-…  {"username":"admin","password":"…"}   (RDS generates and rotates it)
#        ▲  GetSecretValue (IRSA role: ONLY the secrets in secret_arns; KMS decrypt only via Secrets Manager)
#        │  through the secretsmanager + sts VPC endpoints (no NAT)
#   ESO controller ◄── ClusterSecretStore "aws-secrets-manager"   (this module)
#        │         ◄── ExternalSecret "db" in the app's namespace (the app's Helm chart, M3/M4)
#        ▼
#   Kubernetes Secret "db" ──► pod env DB_PASSWORD

data "aws_region" "current" {}

locals {
  read_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid    = "ReadOnlyTheseSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:ListSecretVersionIds",
        ]
        Resource = var.secret_arns
      }],
      # Secrets encrypted with a customer-managed key: decrypt, but only when Secrets Manager asks
      length(var.kms_key_arns) > 0 ? [{
        Sid      = "DecryptOnlyThroughSecretsManager"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = var.kms_key_arns
        Condition = {
          StringEquals = { "kms:ViaService" = "secretsmanager.${data.aws_region.current.region}.amazonaws.com" }
        }
      }] : [],
    )
  })

  # The same image runs the controller, the webhook and the cert-controller
  image_values = var.image_repository == null ? [] : [yamlencode({
    image          = { repository = var.image_repository }
    webhook        = { image = { repository = var.image_repository } }
    certController = { image = { repository = var.image_repository } }
  })]

  values = {
    installCRDs  = true
    replicaCount = var.replica_count

    serviceAccount = {
      create      = true
      name        = var.service_account_name
      annotations = { "eks.amazonaws.com/role-arn" = module.irsa.role_arn }
    }

    # Read-only platform: never write back to Secrets Manager (the IAM policy doesn't allow it either)
    processPushSecret        = false
    processClusterPushSecret = false
  }
}

# ---------------- IRSA role: only the controller's ServiceAccount can assume it ----------------

module "irsa" {
  source = "../irsa-role"

  name              = "${var.name}-external-secrets"
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider     = var.oidc_provider

  service_accounts = [
    { namespace = var.namespace, name = var.service_account_name },
  ]

  inline_policies = {
    "read-secrets" = local.read_policy
  }

  tags = var.tags
}

# ---------------- The operator (CRDs, controller, webhook, cert-controller) ----------------

resource "helm_release" "this" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true

  values = concat(
    [yamlencode(local.values)],
    local.image_values,
    var.extra_values,
  )

  # Wait until the pods (and the webhook) are Ready; roll back automatically if they never are
  wait    = true
  atomic  = true
  timeout = 600

  lifecycle {
    precondition {
      condition     = length(var.secret_arns) > 0
      error_message = "secret_arns is empty: the operator would have nothing it is allowed to read."
    }
  }
}

# ---------------- ClusterSecretStore (a tiny local chart) ----------------
# A second release, AFTER the operator: its CRD and validating webhook must exist first.
# (kubernetes_manifest can't be used here: it needs the CRD already at plan time.)

resource "helm_release" "cluster_secret_store" {
  count = var.create_cluster_secret_store ? 1 : 0

  name      = "cluster-secret-store"
  chart     = "${path.module}/charts/cluster-secret-store"
  namespace = var.namespace

  values = [yamlencode({
    name       = var.cluster_secret_store_name
    region     = data.aws_region.current.region
    namespaces = var.store_allowed_namespaces
  })]

  depends_on = [helm_release.this]
}
