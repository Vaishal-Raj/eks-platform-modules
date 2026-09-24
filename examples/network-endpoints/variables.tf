variable "region" {
  description = "Region to test in"
  type        = string
  default     = "us-east-1"
}
variable "name" {
  description = "Name prefix for the test resources"
  type        = string
  default     = "modules-example"
}

variable "vpc_cidr" {
  description = "Test VPC CIDR (kept away from real client ranges)"
  type        = string
  default     = "10.99.0.0/16"
}