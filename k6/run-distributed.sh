#!/bin/bash
# K6 분산 부하 테스트 스크립트
# K6-0 (master) : setup + teardown 실행 (재고 초기화 + 결과 검증)
# K6-1/K6-2 (worker): --no-setup --no-teardown (독립 부하만 생성)

BASE_URL=${BASE_URL:-"http://your-alb-dns.ap-northeast-2.elb.amazonaws.com"}
PG_URL=${PG_URL:-"https://mock-pg-1046420547293.us-central1.run.app"}
S3_BUCKET=${S3_BUCKET:-"timedeal-xxxx"}
INSTANCE_INDEX=${INSTANCE_INDEX:-0}   # EC2 인스턴스 번호 (0=master, 1/2=worker)

VUS=${VUS:-400}
STOCK=${STOCK:-100}
SCENARIO=${SCENARIO:-realistic}

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULT_FILE="k6-result-${SCENARIO}-vu${VUS}-node${INSTANCE_INDEX}-${TIMESTAMP}.json"

echo "=== K6 분산 부하 테스트 시작 (인스턴스 $INSTANCE_INDEX) ==="
echo "Target: $BASE_URL | VUs: $VUS | Scenario: $SCENARIO | Stock: $STOCK"
echo "Role: $([ $INSTANCE_INDEX -eq 0 ] && echo 'MASTER (setup+teardown)' || echo 'WORKER (no-setup, no-teardown)')"

# K6-0(master)만 setup/teardown 실행, K6-1/K6-2는 부하만 생성
if [ "$INSTANCE_INDEX" -eq 0 ]; then
  k6 run \
    --out "json=${RESULT_FILE}" \
    -e BASE_URL="$BASE_URL" \
    -e PG_URL="$PG_URL" \
    -e VUS="$VUS" \
    -e STOCK="$STOCK" \
    -e SCENARIO="$SCENARIO" \
    timedeal-test.js
else
  k6 run \
    --no-setup \
    --no-teardown \
    --out "json=${RESULT_FILE}" \
    -e BASE_URL="$BASE_URL" \
    -e PG_URL="$PG_URL" \
    -e VUS="$VUS" \
    -e STOCK="$STOCK" \
    -e SCENARIO="$SCENARIO" \
    timedeal-test.js
fi

echo "=== S3 업로드: s3://${S3_BUCKET}/k6-results/${RESULT_FILE} ==="
aws s3 cp "${RESULT_FILE}" "s3://${S3_BUCKET}/k6-results/${RESULT_FILE}" --region ap-northeast-2

echo "=== 완료 ==="
