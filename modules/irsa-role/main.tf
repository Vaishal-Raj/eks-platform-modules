# IRSA (IAM Roles for Service Accounts): a pod gets AWS permissions without any stored keys.
#
#   pod (ServiceAccount <namespace>/<name>)
#     │ token signed by the cluster's OIDC issuer, projected into the pod
#     ▼
#   STS AssumeRoleWithWebIdentity ─► IAM checks this trust policy:
#     • the token comes from THIS cluster's OIDC provider        (Federated principal)
#     • aud = sts.amazonaws.com                                   (meant for AWS STS)
#     • sub = system:serviceaccount:<namespace>:<name>            (exactly this ServiceAccount)
#     ▼
#   short-lived credentials for that pod only
#
# Same mechanism as the GitHub OIDC roles (docs/oidc.md), with a ServiceAccount instead of a workflow job.

locals {
  subjects = [for sa in var.service_accounts : "system:serviceaccount:${sa.namespace}:${sa.name}"]

  # Built with jsonencode (not a data source) so the exact trust policy is visible in plans and tests
  trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowServiceAccountsOfThisCluster"
        Effect    = "Allow"
        Action    = "sts:AssumeRoleWithWebIdentity"
        Principal = { Federated = var.oidc_provider_arn }
        Condition = {
          StringEquals = {
            "${var.oidc_provider}:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "${var.oidc_provider}:sub" = local.subjects
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "this" {
  name                 = var.name
  description          = "IRSA role for ${join(", ", local.subjects)}"
  assume_role_policy   = local.trust_policy
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary_arn

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = var.policy_arns

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "this" {
  for_each = var.inline_policies

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}
