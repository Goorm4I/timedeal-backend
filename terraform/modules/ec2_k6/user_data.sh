#!/bin/bash
# K6 부하 생성기 EC2 초기화
# Terraform templatefile()로 렌더링됨
set -euo pipefail
exec > /var/log/user-data.log 2>&1

echo "[init] K6 EC2 초기화 시작 (인스턴스 ${instance_index}): $(date)"

# ── K6 설치 ────────────────────────────────────────────────────
dnf update -y
dnf install -y wget git

# K6 공식 RPM 저장소
cat > /etc/yum.repos.d/k6.repo << 'REPOEOF'
[k6]
name=k6
baseurl=https://dl.k6.io/rpm/stable
enabled=1
gpgcheck=0
REPOEOF

dnf install -y k6

echo "[init] K6 버전: $(k6 version)"

# ── AWS CLI (AL2023 기본 탑재, 버전 확인) ─────────────────────
echo "[init] AWS CLI: $(aws --version)"

# ── K6 스크립트 디렉토리 ───────────────────────────────────────
mkdir -p /opt/k6
chown -R ec2-user:ec2-user /opt/k6

# ── S3에서 K6 스크립트 다운로드 ───────────────────────────────
S3_BUCKET="${s3_bucket}"
echo "[init] K6 스크립트 다운로드"
aws s3 cp "s3://$S3_BUCKET/scripts/timedeal-test.js"   /opt/k6/timedeal-test.js   --region ap-northeast-2
aws s3 cp "s3://$S3_BUCKET/scripts/run-and-upload.sh"  /opt/k6/run-and-upload.sh  --region ap-northeast-2
chmod +x /opt/k6/run-and-upload.sh
chown -R ec2-user:ec2-user /opt/k6

echo "[init] K6 스크립트 준비 완료"

# ── 실행 래퍼 스크립트 ─────────────────────────────────────────
cat > /opt/k6/run.sh << 'RUNEOF'
#!/bin/bash
# K6 실행 → 결과 S3 업로드
# 사용: bash /opt/k6/run.sh [scenario] [vus] [stock]

SCENARIO=$${1:-realistic}
VUS=$${2:-300}
STOCK=$${3:-100}
BASE_URL="http://${alb_dns}"
PG_URL="http://${mockpg_ip}:3000"
S3_BUCKET="${s3_bucket}"

echo "=== K6 시작: $SCENARIO / VU $VUS / 재고 $STOCK ==="
cd /opt/k6

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULT_FILE="k6-result-$SCENARIO-vu$VUS-instance${instance_index}-$TIMESTAMP.json"

k6 run \
  --out "json=/opt/k6/$RESULT_FILE" \
  -e BASE_URL="$BASE_URL" \
  -e PG_URL="$PG_URL" \
  -e VUS="$VUS" \
  -e STOCK="$STOCK" \
  -e SCENARIO="$SCENARIO" \
  /opt/k6/timedeal-test.js

echo "=== S3 업로드: s3://$S3_BUCKET/k6-results/$RESULT_FILE ==="
aws s3 cp "/opt/k6/$RESULT_FILE" "s3://$S3_BUCKET/k6-results/$RESULT_FILE" --region ap-northeast-2

echo "=== 완료 ==="
echo "분석 명령: aws s3 cp s3://$S3_BUCKET/k6-results/$RESULT_FILE . && cat $RESULT_FILE | jq '.metrics'"
RUNEOF
chmod +x /opt/k6/run.sh
chown ec2-user:ec2-user /opt/k6/run.sh

echo "[init] 완료: $(date)"
echo ""
echo "=== K6 실행 방법 ==="
echo "SSM 접속 후: bash /opt/k6/run.sh [scenario] [vus] [stock]"
echo "예시: bash /opt/k6/run.sh realistic 300 100"
