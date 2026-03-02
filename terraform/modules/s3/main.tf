resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "timedeal" {
  bucket        = "${var.project_name}-${random_id.suffix.hex}"
  force_destroy = true  # terraform destroy 시 오브젝트까지 삭제

  tags = { Name = "${var.project_name}-bucket" }
}

resource "aws_s3_bucket_versioning" "timedeal" {
  bucket = aws_s3_bucket.timedeal.id
  versioning_configuration { status = "Disabled" }
}

resource "aws_s3_bucket_public_access_block" "timedeal" {
  bucket = aws_s3_bucket.timedeal.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── 앱 스크립트 사전 업로드 (EC2 user_data에서 다운로드) ──────
# Mock PG 서버
resource "aws_s3_object" "mockpg_server" {
  bucket = aws_s3_bucket.timedeal.bucket
  key    = "scripts/server.js"
  source = "${path.root}/../mock-pg/server.js"
  etag   = filemd5("${path.root}/../mock-pg/server.js")
}

# K6 메인 테스트 스크립트
resource "aws_s3_object" "k6_test" {
  bucket = aws_s3_bucket.timedeal.bucket
  key    = "scripts/timedeal-test.js"
  source = "${path.root}/../k6/timedeal-test.js"
  etag   = filemd5("${path.root}/../k6/timedeal-test.js")
}

# K6 업로드 스크립트
resource "aws_s3_object" "k6_upload" {
  bucket = aws_s3_bucket.timedeal.bucket
  key    = "scripts/run-and-upload.sh"
  source = "${path.root}/../k6/run-and-upload.sh"
  etag   = filemd5("${path.root}/../k6/run-and-upload.sh")
}

# K6 분산 실행 스크립트
resource "aws_s3_object" "k6_distributed" {
  bucket = aws_s3_bucket.timedeal.bucket
  key    = "scripts/run-distributed.sh"
  source = "${path.root}/../k6/run-distributed.sh"
  etag   = filemd5("${path.root}/../k6/run-distributed.sh")
}
