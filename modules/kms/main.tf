data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  partition    = data.aws_partition.current.partition
  region       = data.aws_region.current.region
  account_root = "arn:${local.partition}:iam::${local.account_id}:root"

  use_actions = [
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:ReEncrypt*",
    "kms:GenerateDataKey*",
    "kms:DescribeKey",
  ]

  admin_actions = [
    "kms:Create*",
    "kms:Describe*",
    "kms:Enable*",
    "kms:List*",
    "kms:Put*",
    "kms:Update*",
    "kms:Revoke*",
    "kms:Disable*",
    "kms:Get*",
    "kms:Delete*",
    "kms:TagResource",
    "kms:UntagResource",
    "kms:ScheduleKeyDeletion",
    "kms:CancelKeyDeletion",
    "kms:RotateKeyOnDemand",
  ]
}

# ---------------- Key policy: one per key ----------------
# A key policy is the key's own permission document. Unlike most AWS resources,
# a KMS key is unusable by anyone (even admins) unless its key policy allows it.

data "aws_iam_policy_document" "this" {
  for_each = var.keys

  # 1. The account root: lets IAM policies in this account grant access to the key,
  #    and guarantees the key can never become unmanageable.
  statement {
    sid       = "EnableIamPoliciesInThisAccount"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }
  }

  # 2. Named administrators: manage the key, but can't encrypt or decrypt with it
  dynamic "statement" {
    for_each = length(var.key_administrators) > 0 ? [1] : []
    content {
      sid       = "KeyAdministrators"
      actions   = local.admin_actions
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.key_administrators
      }
    }
  }

  # 3. Named users: use the key, and let AWS services use it on their behalf (grants)
  dynamic "statement" {
    for_each = length(var.key_users) > 0 ? [1] : []
    content {
      sid       = "KeyUsers"
      actions   = local.use_actions
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.key_users
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.key_users) > 0 ? [1] : []
    content {
      sid       = "KeyUsersGrantsForAwsServices"
      actions   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.key_users
      }

      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }

  # 4. Anyone in THIS account, but only THROUGH the listed AWS services (e.g. RDS).
  #    This is the same pattern AWS-managed keys (aws/rds) use.
  dynamic "statement" {
    for_each = length(each.value.via_services) > 0 ? [1] : []
    content {
      sid       = "UseThroughAwsServices"
      actions   = concat(local.use_actions, ["kms:CreateGrant", "kms:ListGrants"])
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = ["*"]
      }

      condition {
        test     = "StringEquals"
        variable = "kms:CallerAccount"
        values   = [local.account_id]
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = [for s in each.value.via_services : "${s}.${local.region}.amazonaws.com"]
      }
    }
  }

  # 5. CloudWatch Logs encrypts log groups itself, so the service needs the key directly
  dynamic "statement" {
    for_each = each.value.allow_cloudwatch_logs ? [1] : []
    content {
      sid       = "CloudWatchLogs"
      actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["logs.${local.region}.amazonaws.com"]
      }

      condition {
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:*"]
      }
    }
  }
}

# ---------------- Keys and aliases ----------------

resource "aws_kms_key" "this" {
  for_each = var.keys

  description             = "${var.name}: ${each.value.description}"
  key_usage               = "ENCRYPT_DECRYPT"
  deletion_window_in_days = each.value.deletion_window_in_days
  enable_key_rotation     = each.value.enable_key_rotation
  rotation_period_in_days = each.value.enable_key_rotation ? each.value.rotation_period_in_days : null
  policy                  = data.aws_iam_policy_document.this[each.key].json

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

# Friendly, stable name: services and people refer to alias/<name>-<purpose>
resource "aws_kms_alias" "this" {
  for_each = var.keys

  name          = "alias/${var.name}-${each.key}"
  target_key_id = aws_kms_key.this[each.key].key_id
}
