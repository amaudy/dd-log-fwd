terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.81.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "./modules/vpc"
}

module "ecs" {
  source = "./modules/ecs"
}

module "flask-echo" {
  source = "./modules/flask-echo"

  cluster_id         = module.ecs.cluster_id
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  container_image    = "058264373862.dkr.ecr.us-east-1.amazonaws.com/generic/repo:9c3ce071"
} 