#!/bin/bash
# ============================================================
# 로컬 → AWS 배포 스크립트
# 1. mvn 빌드
# 2. S3 업로드 (JAR + K6 스크립트)
# 3. Spring Boot EC2에서 자동 재시작
# ============================================================
set -euo pipefail

REGION="ap-northeast-2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Timedeal 배포 시작 ==="

# ── S3 버킷명 조회 (terraform output) ────────────────────────
cd "$PROJECT_DIR/terraform"
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null)
SPRING_INSTANCE_ID=$(terraform output -raw spring_instance_id 2>/dev/null)

if [ -z "$S3_BUCKET" ]; then
    echo "[ERROR] terraform output s3_bucket_name 없음. terraform apply 완료 후 실행하세요."
    exit 1
fi

echo "[1/4] S3 버킷: $S3_BUCKET"
echo "[1/4] Spring EC2: $SPRING_INSTANCE_ID"

# ── Maven 빌드 ────────────────────────────────────────────────
cd "$PROJECT_DIR"
echo "[2/4] Maven 빌드 중..."
mvn clean package -DskipTests -q

JAR_FILE=$(ls target/timedeal-backend-*.jar | head -1)
if [ ! -f "$JAR_FILE" ]; then
    echo "[ERROR] JAR 파일 없음: target/timedeal-backend-*.jar"
    exit 1
fi
echo "[2/4] 빌드 완료: $JAR_FILE"

# ── S3 업로드 ─────────────────────────────────────────────────
echo "[3/4] S3 업로드..."
aws s3 cp "$JAR_FILE" "s3://$S3_BUCKET/artifacts/app.jar" --region "$REGION"
aws s3 cp "k6/timedeal-test.js"   "s3://$S3_BUCKET/scripts/timedeal-test.js"  --region "$REGION"
aws s3 cp "k6/run-and-upload.sh"  "s3://$S3_BUCKET/scripts/run-and-upload.sh" --region "$REGION"
echo "[3/4] 업로드 완료"

# ── EC2에서 배포 (SSM) ───────────────────────────────────────
echo "[4/4] EC2 재배포 중 (SSM)..."
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$SPRING_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters commands=["sudo /opt/timedeal/deploy.sh"] \
    --region "$REGION" \
    --output text \
    --query "Command.CommandId")

echo "[4/4] SSM 명령 전송: $COMMAND_ID"
echo "      상태 확인: aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id $SPRING_INSTANCE_ID --region $REGION"

# 10초 후 상태 확인
sleep 15
STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$SPRING_INSTANCE_ID" \
    --region "$REGION" \
    --query "StatusDetails" \
    --output text 2>/dev/null || echo "확인 중...")

echo "[4/4] 배포 상태: $STATUS"

echo ""
echo "=== 배포 완료 ==="
echo "ALB URL: $(terraform -chdir=terraform output -raw alb_dns 2>/dev/null || echo '확인 중')"
echo ""
echo "헬스 체크: curl http://$(cd terraform && terraform output -raw alb_dns 2>/dev/null)/actuator/health"
