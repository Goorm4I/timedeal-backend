data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "spring" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.medium"
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.iam_instance_profile

  # SSH 키 없이 SSM으로만 접속
  # key_name 미설정

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    db_host     = var.db_host
    db_name     = var.db_name
    db_username = var.db_username
    db_password = var.db_password
    redis_host  = var.redis_host
    mockpg_host = var.mockpg_host
    s3_bucket   = var.s3_bucket
  }))

  # EBS: root volume
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
  }

  # user_data 변경 시 인스턴스 재생성
  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project_name}-spring-app" }
}
