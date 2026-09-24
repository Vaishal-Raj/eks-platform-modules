Reusable Terraform modules for the EKS platform. No environment values live here.

| Module | Purpose |
|---|---|
| `modules/network` | VPC, private + isolated subnets, route tables |

Usage (always pin a tag):

    source = "git::https://github.com/Vaishal-Raj/eks-platform-modules.git//modules/network?ref=v0.1.0"
