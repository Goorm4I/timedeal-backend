variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "프로젝트명 (리소스 태깅용)"
  type        = string
  default     = "timedeal"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "Public Subnet CIDR 목록 (ALB, K6용)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "Private Subnet CIDR 목록 (Spring, RDS, Redis, MockPG용)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "availability_zones" {
  description = "사용 가용영역"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "db_password" {
  description = "RDS PostgreSQL 비밀번호"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "RDS 사용자명"
  type        = string
  default     = "timedeal"
}

variable "db_name" {
  description = "데이터베이스 이름"
  type        = string
  default     = "timedeal"
}

variable "rds_multi_az" {
  description = "RDS Multi-AZ 활성화 (true: 운영환경, false: 테스트환경)"
  type        = bool
  default     = false
}

variable "initial_stock" {
  description = "타임딜 상품 초기 재고"
  type        = number
  default     = 100
}

variable "k6_instance_count" {
  description = "K6 EC2 인스턴스 수"
  type        = number
  default     = 3
}
