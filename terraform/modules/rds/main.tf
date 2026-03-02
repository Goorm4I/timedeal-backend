resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

resource "aws_db_parameter_group" "postgres15" {
  name   = "${var.project_name}-pg15"
  family = "postgres15"

  # max_connections는 RDS가 인스턴스 크기에 맞게 자동 계산 (static 파라미터라 제외)
  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"  # 1초 이상 쿼리 로깅
    apply_method = "immediate"
  }

  tags = { Name = "${var.project_name}-pg15-params" }
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-postgres"

  engine               = "postgres"
  engine_version       = "15"
  instance_class       = "db.t3.medium"
  allocated_storage    = 20
  storage_type         = "gp2"
  storage_encrypted    = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = var.security_group_ids
  parameter_group_name   = aws_db_parameter_group.postgres15.name

  multi_az               = var.multi_az
  publicly_accessible    = false
  skip_final_snapshot    = true  # terraform destroy 시 스냅샷 없이 삭제
  deletion_protection    = false

  backup_retention_period = 0  # 테스트 환경: 자동 백업 비활성화

  tags = { Name = "${var.project_name}-postgres" }
}
