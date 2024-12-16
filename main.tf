provider "aws" {
  region = "us-east-1"
}

module "ecs" {
  source = "./modules/ecs"
}

module "flask-echo" {
  source = "./modules/flask-echo"

  cluster_id         = module.ecs.cluster_id
  vpc_id             = module.ecs.vpc_id
  private_subnet_ids = module.ecs.private_subnet_ids
  container_image    = "thatthep/flask-echo:main"
} 