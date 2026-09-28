provider "aws" {
  region = "us-east-1"

  # Tags added by the organization's Cloud Custodian (an SCP forbids deleting them)
  ignore_tags {
    keys         = ["Owner"]
    key_prefixes = ["c7n-"]
  }

  default_tags {
    tags = {
      Project   = "poc-gvr"
      Purpose   = "module-example"
      ManagedBy = "terraform"
    }
  }
}

module "kms" {
  source = "../../modules/kms"

  name = "kms-example"

  keys = {
    # For the rds module: RDS storage, snapshots, and the RDS-managed master password
    rds = {
      description             = "RDS storage, snapshots and the managed master secret"
      via_services            = ["rds", "secretsmanager"]
      deletion_window_in_days = 7 # shortest wait, since this is a throwaway test
    }

    # For log groups (VPC flow logs, WAF logs, EKS control plane logs, app logs)
    logs = {
      description             = "CloudWatch Logs"
      allow_cloudwatch_logs   = true
      deletion_window_in_days = 7
    }
  }
}

# Proof that the "logs" key policy works: CloudWatch Logs can only create this
# encrypted log group if the key policy lets the service use the key.
resource "aws_cloudwatch_log_group" "encrypted" {
  name              = "/kms-example/encrypted"
  retention_in_days = 1
  kms_key_id        = module.kms.key_arns["logs"]
}
