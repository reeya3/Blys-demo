provider "aws" {
  region = var.aws_region
}

module "networking" {
  source   = "../../modules/networking"
  name     = var.name
  vpc_cidr = var.vpc_cidr
  az_count = 2
}

module "security" {
  source   = "../../modules/security"
  name     = var.name
  vpc_id   = module.networking.vpc_id
  app_port = var.app_port
}

module "secrets" {
  source      = "../../modules/secrets"
  name        = var.name
  secret_path = "blys/app/secret"
}

module "iam" {
  source         = "../../modules/iam"
  name           = var.name
  log_group_name = "/ecs/${var.name}-cluster/${var.name}-app"
  ecr_repo_name  = "blys-app"
  secret_arn     = module.secrets.secret_arn
}

module "compute" {
  source = "../../modules/compute"

  name               = "${var.name}-app"
  cluster_name       = "${var.name}-cluster"
  aws_region         = var.aws_region
  vpc_id             = module.networking.vpc_id
  public_subnet_ids  = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
  alb_sg_id          = module.security.alb_sg_id
  ecs_sg_id          = module.security.ecs_sg_id
  execution_role_arn = module.iam.ecs_task_execution_role_arn
  app_secret_arn     = module.secrets.secret_arn
  container_image    = var.container_image
  app_port           = var.app_port
  desired_count      = var.desired_count
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
}
