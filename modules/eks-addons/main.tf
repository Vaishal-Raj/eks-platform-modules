# EKS managed add-ons: components AWS packages, tests and versions per Kubernetes release.
#
# Call this module TWICE, because of ordering:
#   1. before the node group: vpc-cni, kube-proxy  (nodes need pod networking to become Ready)
#   2. after the node group:  coredns, metrics-server, ...  (they run as pods, so they need nodes)

# For add-ons without a pinned version: ask AWS which version fits this Kubernetes version
data "aws_eks_addon_version" "this" {
  for_each = { for name, a in var.addons : name => a if a.version == null }

  addon_name         = each.key
  kubernetes_version = var.kubernetes_version
  most_recent        = var.use_latest_versions
}

resource "aws_eks_addon" "this" {
  for_each = var.addons

  cluster_name  = var.cluster_name
  addon_name    = each.key
  addon_version = each.value.version != null ? each.value.version : data.aws_eks_addon_version.this[each.key].version

  service_account_role_arn = each.value.service_account_role_arn
  configuration_values     = each.value.configuration_values

  # First install: replace any self-managed copy. Updates: as configured.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = each.value.resolve_conflicts

  tags = var.tags

  timeouts {
    create = "30m"
    update = "30m"
    delete = "20m"
  }
}
