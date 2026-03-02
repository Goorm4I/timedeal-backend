output "alb_dns" {
  description = "ALB DNS 주소 (K6 BASE_URL로 사용)"
  value       = "http://${module.alb.dns_name}"
}

output "mockpg_ip" {
  description = "Mock PG EC2 Private IP"
  value       = module.ec2_pg.private_ip
}

output "spring_instance_id" {
  description = "Spring Boot EC2 인스턴스 ID (SSM 접속용)"
  value       = module.ec2_app.instance_id
}

output "k6_instance_ids" {
  description = "K6 EC2 인스턴스 ID 목록 (SSM 접속용)"
  value       = module.ec2_k6.instance_ids
}

output "s3_bucket_name" {
  description = "S3 버킷명 (아티팩트 + K6 결과)"
  value       = module.s3.bucket_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL 엔드포인트"
  value       = module.rds.endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "ElastiCache Redis 엔드포인트"
  value       = module.elasticache.endpoint
  sensitive   = true
}

output "ssm_connect_spring" {
  description = "Spring Boot SSM 접속 명령어"
  value       = "aws ssm start-session --target ${module.ec2_app.instance_id} --region ap-northeast-2"
}

output "ssm_connect_k6_0" {
  description = "K6[0] SSM 접속 명령어"
  value       = "aws ssm start-session --target ${module.ec2_k6.instance_ids[0]} --region ap-northeast-2"
}
