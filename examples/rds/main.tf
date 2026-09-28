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

# 1. Network: RDS goes in the isolated subnets
module "network" {
  source = "../../modules/network"

  name             = var.name
  vpc_cidr         = var.vpc_cidr
  exclude_zone_ids = ["use1-az3"]
}

# 2. Customer-managed keys: rds (storage + master password), logs (exported MySQL logs)
module "kms" {
  source = "../../modules/kms"

  name = var.name

  keys = {
    rds = {
      description             = "RDS storage, snapshots and the managed master secret"
      via_services            = ["rds", "secretsmanager"]
      deletion_window_in_days = 7 # throwaway test
    }
    logs = {
      description             = "CloudWatch Logs"
      allow_cloudwatch_logs   = true
      deletion_window_in_days = 7
    }
  }
}

# 3. Security groups: sg-rds accepts 3306 from sg-node only
module "security_groups" {
  source = "../../modules/security-groups"

  name            = var.name
  vpc_id          = module.network.vpc_id
  create_cache_sg = false
}

# 4. MySQL
module "rds" {
  source = "../../modules/rds"

  name               = var.name
  subnet_ids         = module.network.isolated_subnet_ids
  security_group_ids = [module.security_groups.rds_security_group_id]
  kms_key_arn        = module.kms.key_arns["rds"]
  logs_kms_key_arn   = module.kms.key_arns["logs"]

  engine_version        = "8.4"
  instance_class        = "db.t4g.micro"
  backup_retention_days = 1

  # Throwaway test settings: never use these for a real client
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true
}
