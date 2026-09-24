output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "AZ names used, in order"
  value       = local.azs
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = [for s in aws_subnet.private : s.id]
}

output "private_subnet_cidrs" {
  description = "Private subnet CIDRs"
  value       = [for s in aws_subnet.private : s.cidr_block]
}

output "private_subnet_ids_by_az" {
  description = "Map of AZ -> private subnet ID"
  value       = { for az, s in aws_subnet.private : az => s.id }
}

output "isolated_subnet_ids" {
  description = "Isolated subnet IDs"
  value       = [for s in aws_subnet.isolated : s.id]
}

output "isolated_subnet_cidrs" {
  description = "Isolated subnet CIDRs"
  value       = [for s in aws_subnet.isolated : s.cidr_block]
}

output "private_route_table_id" {
  description = "Private route table ID (attach gateway endpoints here)"
  value       = aws_route_table.private.id
}

output "isolated_route_table_id" {
  description = "Isolated route table ID"
  value       = aws_route_table.isolated.id
}
