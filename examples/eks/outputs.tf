output "cluster_name" {
  value = module.eks_cluster.cluster_name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region us-east-1 --name ${module.eks_cluster.cluster_name}"
}

output "node_group_name" {
  value = module.node_group.node_group_name
}

output "node_role_arn" {
  value = module.node_group.node_role_arn
}

output "addon_versions" {
  value = merge(module.addons_before_nodes.addon_versions, module.addons_after_nodes.addon_versions)
}

output "ebs_csi_role_arn" {
  value = module.ebs_csi_irsa.role_arn
}
