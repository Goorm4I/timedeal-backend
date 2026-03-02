#!/bin/bash
# ============================================================
# K6 분산 부하 테스트 실행
# 3개 K6 EC2에 SSM으로 동시 실행 명령 전송
# ============================================================
set -euo pipefail

REGION="ap-northeast-2"
SCENARIO=${1:-realistic}
VUS=${2:-300}
STOCK=${3:-100}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../terraform"

echo "=== K6 분산 테스트 시작 ==="
echo "시나리오: $SCENARIO | VU/대: $VUS | 재고: $STOCK"

# terraform output에서 인스턴스 ID 목록 조회
K6_IDS=$(terraform output -json k6_instance_ids | jq -r '.[]')
ALB_DNS=$(terraform output -raw alb_dns)

if [ -z "$K6_IDS" ]; then
    echo "[ERROR] K6 인스턴스 ID 없음. terraform apply 완료 후 실행하세요."
    exit 1
fi

echo "ALB: $ALB_DNS"
echo "K6 인스턴스:"

# ── 재고 초기화 ───────────────────────────────────────────────
echo ""
echo "[1/2] 재고 리셋: POST $ALB_DNS/api/admin/stock/reset?productId=1&stock=$STOCK"
curl -s -X POST "$ALB_DNS/api/admin/stock/reset?productId=1&stock=$STOCK" | python3 -m json.tool || true

# ── 모든 K6 EC2에 동시 실행 ────────────────────────────────────
echo ""
echo "[2/2] K6 실행 명령 전송..."

COMMAND_IDS=()
for INSTANCE_ID in $K6_IDS; do
    echo "  → $INSTANCE_ID"
    CMD_ID=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"bash /opt/k6/run.sh $SCENARIO $VUS $STOCK\"]" \
        --timeout-seconds 1800 \
        --region "$REGION" \
        --output text \
        --query "Command.CommandId")
    COMMAND_IDS+=("$INSTANCE_ID:$CMD_ID")
    echo "    명령 ID: $CMD_ID"
done

echo ""
echo "=== K6 실행 중 (약 2~5분 소요) ==="
echo ""
echo "진행 상태 확인:"
for PAIR in "${COMMAND_IDS[@]}"; do
    IIDS="${PAIR%%:*}"
    CIDS="${PAIR##*:}"
    echo "  aws ssm get-command-invocation --command-id $CIDS --instance-id $IIDS --region $REGION --query StatusDetails"
done

echo ""
echo "완료 후 결과 분석:"
S3_BUCKET=$(terraform output -raw s3_bucket_name)
echo "  aws s3 ls s3://$S3_BUCKET/k6-results/"
echo "  aws s3 cp s3://$S3_BUCKET/k6-results/<파일명> . && cat <파일명> | jq '.metrics'"
