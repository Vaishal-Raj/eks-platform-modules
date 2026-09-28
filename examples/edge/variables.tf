variable "name" {
  description = "Name prefix for the test resources"
  type        = string
  default     = "edge-example"
}

variable "vpc_cidr" {
  description = "Test VPC CIDR (kept away from client ranges and the other examples)"
  type        = string
  default     = "10.97.0.0/16"
}
