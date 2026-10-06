data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition

  # Policies every EKS worker node needs
  base_policies = {
    worker = "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"          # join the cluster
    cni    = "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"               # vpc-cni: assign pod IPs
    ecr    = "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly" # pull images
  }

  ssm_policy = var.enable_ssm ? {
    ssm = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  } : {}

  policies = merge(local.base_policies, local.ssm_policy, var.additional_policy_arns)
}

# ---------------- Node IAM role (what the EC2 instances run as) ----------------

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-node"
  description        = "EKS worker nodes for ${var.cluster_name} / ${var.name}"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.policies

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# e.g. ECR pull-through cache: first pulls must be able to create cache repositories
resource "aws_iam_role_policy" "node" {
  for_each = var.additional_policy_jsons

  name   = each.key
  role   = aws_iam_role.node.id
  policy = each.value
}

# ---------------- Launch template: hardening for every node ----------------

resource "aws_launch_template" "this" {
  name_prefix            = "${var.name}-"
  description            = "EKS nodes ${var.name}: IMDSv2, encrypted gp3 root volume"
  update_default_version = true

  # With a launch template that sets security groups, EKS does NOT add the cluster
  # security group itself, so it must be listed here explicitly.
  vpc_security_group_ids = concat([var.cluster_security_group_id], var.additional_security_group_ids)

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only: blocks a common credential-theft path
    http_put_response_hop_limit = var.imds_hop_limit
  }

  block_device_mappings {
    device_name = startswith(var.ami_type, "BOTTLEROCKET") ? "/dev/xvdb" : "/dev/xvda"

    ebs {
      volume_size           = var.disk_size_gib
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.ebs_kms_key_arn
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-node" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.name}-node" })
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------- The managed node group ----------------

resource "aws_eks_node_group" "this" {
  cluster_name    = var.cluster_name
  node_group_name = var.name
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  version         = var.kubernetes_version

  ami_type       = var.ami_type
  capacity_type  = var.capacity_type
  instance_types = var.instance_types

  scaling_config {
    min_size     = var.scaling.min_size
    max_size     = var.scaling.max_size
    desired_size = var.scaling.desired_size
  }

  update_config {
    max_unavailable_percentage = var.max_unavailable_percentage
  }

  node_repair_config {
    enabled = var.enable_node_repair
  }

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  labels = var.labels

  dynamic "taint" {
    for_each = var.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(var.tags, { Name = var.name })

  # The role needs its policies BEFORE nodes boot, or they can't join the cluster
  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_iam_role_policy.node,
  ]

  lifecycle {
    # A cluster autoscaler (or a person) may change the live count; don't fight it on every apply
    ignore_changes = [scaling_config[0].desired_size]
  }
}
