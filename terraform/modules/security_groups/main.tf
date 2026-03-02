# ──────────────────────────────────────────────────────────────
# ALB SG: 인터넷 → ALB (:80)
# ──────────────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB: HTTP from internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# ──────────────────────────────────────────────────────────────
# Spring Boot SG: ALB + K6 → Spring (:8080)
# ──────────────────────────────────────────────────────────────
resource "aws_security_group" "spring" {
  name        = "${var.project_name}-spring-sg"
  description = "Spring Boot: from ALB and K6"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "From K6"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.k6.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-spring-sg" }
}

# ──────────────────────────────────────────────────────────────
# Redis SG: Spring → Redis (:6379)
# ──────────────────────────────────────────────────────────────
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "Redis: from Spring only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From Spring"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.spring.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-redis-sg" }
}

# ──────────────────────────────────────────────────────────────
# RDS SG: Spring → RDS (:5432)
# ──────────────────────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "RDS PostgreSQL: from Spring only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From Spring"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.spring.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-rds-sg" }
}

# ──────────────────────────────────────────────────────────────
# Mock PG SG: Spring → MockPG (:3000)
# ──────────────────────────────────────────────────────────────
resource "aws_security_group" "mockpg" {
  name        = "${var.project_name}-mockpg-sg"
  description = "Mock PG: from Spring only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From Spring"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.spring.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-mockpg-sg" }
}

# SG rule 별도 리소스로 추가 (인라인 ingress 수정 시 SG 교체 방지)
resource "aws_security_group_rule" "mockpg_from_k6" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.k6.id
  security_group_id        = aws_security_group.mockpg.id
  description              = "From K6 (scenario setup and stats)"
}

# ──────────────────────────────────────────────────────────────
# K6 SG: 인터넷에서 직접 K6 운영
# SSM은 아웃바운드만 필요 (인바운드 불필요)
# ──────────────────────────────────────────────────────────────
resource "aws_security_group" "k6" {
  name        = "${var.project_name}-k6-sg"
  description = "K6 Load Generator: outbound only"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-k6-sg" }
}
