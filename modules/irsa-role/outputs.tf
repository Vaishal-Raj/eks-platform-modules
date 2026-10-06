output "role_arn" {
  description = "IAM role ARN: put it on the ServiceAccount (annotation eks.amazonaws.com/role-arn) or in an add-on's service_account_role_arn"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "IAM role name"
  value       = aws_iam_role.this.name
}

output "service_account_annotation" {
  description = "Annotation to put on the Kubernetes ServiceAccount (e.g. in Helm values)"
  value       = { "eks.amazonaws.com/role-arn" = aws_iam_role.this.arn }
}

output "trusted_subjects" {
  description = "ServiceAccounts allowed to assume the role (system:serviceaccount:<namespace>:<name>)"
  value       = local.subjects
}
