# ============================================================
# VPC
# ============================================================
module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  public_subnets     = var.public_subnets
  private_subnets    = var.private_subnets
  availability_zones = var.availability_zones
}

# ============================================================
# IAM (EC2 공통 Role: SSM + CloudWatch + S3)
# ============================================================
module "iam" {
  source = "./modules/iam"

  project_name   = var.project_name
  s3_bucket_name = module.s3.bucket_name
}

# ============================================================
# S3 (아티팩트 + K6 결과)
# ============================================================
module "s3" {
  source = "./modules/s3"

  project_name = var.project_name
}

# ============================================================
# Security Groups
# ============================================================
module "security_groups" {
  source = "./modules/security_groups"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
}

# ============================================================
# RDS - PostgreSQL 15
# ============================================================
module "rds" {
  source = "./modules/rds"

  project_name       = var.project_name
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  multi_az           = var.rds_multi_az
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.security_groups.rds_sg_id]
}

# ============================================================
# ElastiCache - Redis 7
# ============================================================
module "elasticache" {
  source = "./modules/elasticache"

  project_name       = var.project_name
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.security_groups.redis_sg_id]
}

# ============================================================
# Mock PG (Node.js, PortOne 모방)
# ============================================================
module "ec2_pg" {
  source = "./modules/ec2_pg"

  project_name         = var.project_name
  subnet_id            = module.vpc.private_subnet_ids[0]
  security_group_ids   = [module.security_groups.mockpg_sg_id]
  iam_instance_profile = module.iam.instance_profile_name
  s3_bucket            = module.s3.bucket_name
}

# ============================================================
# Spring Boot 앱 서버
# ============================================================
module "ec2_app" {
  source = "./modules/ec2_app"

  project_name         = var.project_name
  subnet_id            = module.vpc.private_subnet_ids[0]
  security_group_ids   = [module.security_groups.spring_sg_id]
  iam_instance_profile = module.iam.instance_profile_name

  db_host      = module.rds.endpoint
  db_name      = var.db_name
  db_username  = var.db_username
  db_password  = var.db_password
  redis_host   = module.elasticache.endpoint
  mockpg_host  = module.ec2_pg.private_ip
  s3_bucket    = module.s3.bucket_name
  initial_stock = var.initial_stock
}

# ============================================================
# ALB
# ============================================================
module "alb" {
  source = "./modules/alb"

  project_name      = var.project_name
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.security_groups.alb_sg_id
  target_instance_id = module.ec2_app.instance_id
}

# ============================================================
# K6 부하 생성기 (Public Subnet, count=3)
# ============================================================
module "ec2_k6" {
  source = "./modules/ec2_k6"

  project_name         = var.project_name
  instance_count       = var.k6_instance_count
  subnet_ids           = module.vpc.public_subnet_ids
  security_group_ids   = [module.security_groups.k6_sg_id]
  iam_instance_profile = module.iam.instance_profile_name

  alb_dns      = module.alb.dns_name
  mockpg_ip    = module.ec2_pg.private_ip
  s3_bucket    = module.s3.bucket_name
  stock        = var.initial_stock
}
