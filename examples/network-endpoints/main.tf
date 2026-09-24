provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "poc-gvr"
      Purpose   = "module-example"
      ManagedBy = "terraform"
    }
  }
}

module "network" {
  source           = "../../modules/network"
  name             = var.name
  vpc_cidr         = var.vpc_cidr
  exclude_zone_ids = ["use1-az3"]
}

module "vpc_endpoints" {
  source          = "../../modules/vpc-endpoints"
  name            = var.name
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnet_ids
  allowed_cidrs   = module.network.private_subnet_cidrs
  route_table_ids = [module.network.private_route_table_id]
}