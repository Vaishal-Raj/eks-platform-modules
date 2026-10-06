variable "name" {
  description = "Name prefix for the test resources (also the cluster name)"
  type        = string
  default     = "eks-full"
}

variable "vpc_cidr" {
  description = "Test VPC CIDR (kept away from client ranges and the other examples)"
  type        = string
  default     = "10.93.0.0/16"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version (list them: aws eks describe-cluster-versions --query 'clusterVersions[].clusterVersion')"
  type        = string
  default     = "1.35"
}

variable "admin_cidr" {
  description = "YOUR public IP as /32, allowed to reach the public API endpoint. Get it with: curl -s https://checkip.amazonaws.com"
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a CIDR such as 203.0.113.10/32, and not 0.0.0.0/0."
  }
}
