data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  registry_url = "${local.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com"
  repo_arn     = "arn:${data.aws_partition.current.partition}:ecr:${data.aws_region.current.region}:${local.account_id}:repository"

  pull_actions = [
    "ecr:BatchGetImage",
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchCheckLayerAvailability",
  ]

  push_actions = [
    "ecr:InitiateLayerUpload",
    "ecr:UploadLayerPart",
    "ecr:CompleteLayerUpload",
    "ecr:PutImage",
  ]

  create_repo_policy = length(var.push_principal_arns) + length(var.pull_principal_arns) > 0
}

# ======================================================================
# App repositories: <name>/<key>
# ======================================================================

resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name                 = "${var.name}/${each.key}"
  image_tag_mutability = each.value.image_tag_mutability
  force_delete         = each.value.force_delete

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.kms_key_arn == null ? "AES256" : "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = merge(var.tags, { Name = "${var.name}/${each.key}" })
}

# Expire leftovers first (untagged), then keep only the newest N images
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = var.repositories

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged images after ${each.value.untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = each.value.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the newest ${each.value.keep_last_images} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = each.value.keep_last_images
        }
        action = { type = "expire" }
      },
    ]
  })
}

# Optional repository policy: who may push / pull (needed for cross-account access)
data "aws_iam_policy_document" "repository" {
  count = local.create_repo_policy ? 1 : 0

  dynamic "statement" {
    for_each = length(var.push_principal_arns) > 0 ? [1] : []
    content {
      sid     = "AllowPush"
      actions = concat(local.pull_actions, local.push_actions)

      principals {
        type        = "AWS"
        identifiers = var.push_principal_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.pull_principal_arns) > 0 ? [1] : []
    content {
      sid     = "AllowPull"
      actions = local.pull_actions

      principals {
        type        = "AWS"
        identifiers = var.pull_principal_arns
      }
    }
  }
}

resource "aws_ecr_repository_policy" "this" {
  for_each = local.create_repo_policy ? var.repositories : {}

  repository = aws_ecr_repository.this[each.key].name
  policy     = data.aws_iam_policy_document.repository[0].json
}

# ======================================================================
# Pull-through cache: mirrors of public registries (no NAT needed)
# ======================================================================
# node --VPC endpoint--> <registry>/<prefix>/<image>
#                          └─ not cached yet? ECR fetches <upstream>/<image> once, stores and scans it

resource "aws_ecr_pull_through_cache_rule" "this" {
  for_each = var.pull_through_cache_rules

  ecr_repository_prefix = each.key
  upstream_registry_url = each.value.upstream_registry_url
  credential_arn        = each.value.credential_arn
}

# Cache repositories are created automatically on first pull. A creation template is the
# only way to give them settings: here, a lifecycle policy so mirrors don't grow forever.
# Tags stay MUTABLE because upstream tags (e.g. "latest", "v1") can move.
# Encryption is AES256: a KMS key or tags in a template would require a custom IAM role.
resource "aws_ecr_repository_creation_template" "cache" {
  for_each = var.pull_through_cache_rules

  prefix               = each.key
  description          = "Settings for ${each.value.upstream_registry_url} pull-through cache repositories"
  applied_for          = ["PULL_THROUGH_CACHE"]
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged images after ${var.cache_untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.cache_untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the newest ${var.cache_keep_last_images} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.cache_keep_last_images
        }
        action = { type = "expire" }
      },
    ]
  })

  depends_on = [aws_ecr_pull_through_cache_rule.this]
}

# ======================================================================
# IAM policy for whoever pulls through the cache (the EKS node role, M3)
# ======================================================================
# The FIRST pull of an image creates its cache repository, so the puller also needs
# ecr:CreateRepository and ecr:BatchImportUpstreamImage on the cache prefixes.

data "aws_iam_policy_document" "cache_pull" {
  count = length(var.pull_through_cache_rules) > 0 ? 1 : 0

  statement {
    sid       = "PullThroughCache"
    actions   = concat(local.pull_actions, ["ecr:BatchImportUpstreamImage", "ecr:CreateRepository"])
    resources = [for prefix in keys(var.pull_through_cache_rules) : "${local.repo_arn}/${prefix}/*"]
  }
}
