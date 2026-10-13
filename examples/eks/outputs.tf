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

output "alb_dns_name" {
  description = "Internal ALB (reachable only inside the VPC, e.g. from a pod)"
  value       = module.alb.alb_dns_name
}

output "target_group_arn" {
  value = module.alb.target_group_arn
}

output "alb_controller_role_arn" {
  value = module.alb_controller.role_arn
}

# terraform output -raw test_app_manifest | kubectl apply -f -
output "test_app_manifest" {
  description = "Test app (agnhost via the ECR cache) + Service + TargetGroupBinding to the ALB's target group"
  value = templatefile("${path.module}/test-app.yaml.tftpl", {
    image            = "${module.ecr.pull_through_cache_urls["k8s"]}/e2e-test-images/agnhost:2.53"
    target_group_arn = module.alb.target_group_arn
  })
}

output "external_secrets_role_arn" {
  value = module.external_secrets.role_arn
}

# terraform output -raw test_external_secret_manifest | kubectl apply -f -
output "test_external_secret_manifest" {
  description = "ExternalSecret in default: copies the demo secret into the Kubernetes Secret demo-db"
  value = templatefile("${path.module}/test-external-secret.yaml.tftpl", {
    store_name  = module.external_secrets.cluster_secret_store_name
    secret_name = aws_secretsmanager_secret.demo.name
  })
}
