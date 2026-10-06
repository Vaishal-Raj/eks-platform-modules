data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition

  # One association per (entry, policy): cluster-wide or limited to namespaces
  access_policy_arn_prefix = "arn:${local.partition}:eks::aws:cluster-access-policy"
}

# ---------------- IAM role the EKS control plane runs as ----------------

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-eks-cluster"
  description        = "EKS control plane role for ${var.name}"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# The cluster role must be able to use the KMS key that encrypts Kubernetes Secrets
data "aws_iam_policy_document" "cluster_kms" {
  count = var.encrypt_secrets ? 1 : 0

  statement {
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ListGrants", "kms:DescribeKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "cluster_kms" {
  count = var.encrypt_secrets ? 1 : 0

  name   = "eks-secrets-encryption"
  role   = aws_iam_role.cluster.id
  policy = data.aws_iam_policy_document.cluster_kms[0].json
}

# ---------------- Control plane logs (created first: our retention + key) ----------------

resource "aws_cloudwatch_log_group" "this" {
  count = length(var.enabled_log_types) > 0 ? 1 : 0

  # EKS writes to exactly this name
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = var.tags
}

# ---------------- The cluster ----------------

resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  # false: vpc-cni / coredns / kube-proxy are installed as MANAGED add-ons (eks-addons module)
  bootstrap_self_managed_addons = var.bootstrap_self_managed_addons
  deletion_protection           = var.deletion_protection
  enabled_cluster_log_types     = var.enabled_log_types

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.additional_security_group_ids

    # Private endpoint is always on: nodes have no internet, so they register through it
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : null
  }

  # Access entries only (no aws-auth ConfigMap)
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin
  }

  # Envelope-encrypt Kubernetes Secrets in etcd with our key
  dynamic "encryption_config" {
    for_each = var.encrypt_secrets ? [1] : []
    content {
      resources = ["secrets"]
      provider {
        key_arn = var.kms_key_arn
      }
    }
  }

  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = var.service_ipv4_cidr
  }

  upgrade_policy {
    support_type = var.support_type
  }

  tags = merge(var.tags, { Name = var.name })

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_iam_role_policy.cluster_kms,
    aws_cloudwatch_log_group.this,
  ]

  lifecycle {
    precondition {
      condition     = !var.endpoint_public_access || length(var.public_access_cidrs) > 0
      error_message = "endpoint_public_access = true needs public_access_cidrs (e.g. your office/VPN CIDR). Refusing to open the API to 0.0.0.0/0 by default."
    }
  }
}

# ---------------- IRSA: OIDC provider (pods assume IAM roles) ----------------
# Same idea as the GitHub OIDC provider: IAM trusts tokens signed by this cluster.

resource "aws_iam_openid_connect_provider" "this" {
  count = var.create_oidc_provider ? 1 : 0

  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]

  tags = merge(var.tags, { Name = "${var.name}-eks-irsa" })
}

# ---------------- Access entries: who may use the cluster ----------------

resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"

  tags = var.tags
}

resource "aws_eks_access_policy_association" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.this[each.key].principal_arn
  policy_arn    = "${local.access_policy_arn_prefix}/${each.value.policy}"

  access_scope {
    type       = length(each.value.namespaces) == 0 ? "cluster" : "namespace"
    namespaces = length(each.value.namespaces) == 0 ? null : each.value.namespaces
  }
}
