output "security_group_id" {
  description = "ID of the endpoints' security group (sg-vpce)"
  value       = aws_security_group.this.id
}

output "interface_endpoint_ids" {
  description = "Map of service -> interface endpoint ID"
  value       = { for svc, ep in aws_vpc_endpoint.interface : svc => ep.id }
}

output "interface_endpoint_dns" {
  description = "Map of service -> endpoint DNS entries (useful when private DNS is off)"
  value       = { for svc, ep in aws_vpc_endpoint.interface : svc => ep.dns_entry[*].dns_name }
}

output "s3_endpoint_id" {
  description = "S3 gateway endpoint ID, or null if disabled"
  value       = one(aws_vpc_endpoint.s3[*].id)
}