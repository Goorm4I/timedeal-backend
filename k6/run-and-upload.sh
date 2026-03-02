#!/bin/bash
# K6 실행 → 결과 S3 업로드 → Claude가 분석

BASE_URL=${BASE_URL:-"http://localhost:8080"}
PG_URL=${PG_URL:-"http://localhost:3000"}
S3_BUCKET=${S3_BUCKET:-"timedeal-k6-results"}
VUS=${VUS:-200}
STOCK=${STOCK:-100}
SCENARIO=${SCENARIO:-realistic}

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULT_FILE="k6-result-${SCENARIO}-vu${VUS}-${TIMESTAMP}.json"

echo "=== K6 시작: $SCENARIO / VU $VUS / 재고 $STOCK ==="

k6 run \
  --out "json=${RESULT_FILE}" \
  -e BASE_URL=$BASE_URL \
  -e PG_URL=$PG_URL \
  -e VUS=$VUS \
  -e STOCK=$STOCK \
  -e SCENARIO=$SCENARIO \
  k6/timedeal-test.js

echo "=== S3 업로드: s3://${S3_BUCKET}/${RESULT_FILE} ==="
aws s3 cp ${RESULT_FILE} s3://${S3_BUCKET}/${RESULT_FILE}

echo "=== 완료. Claude에게 분석 요청하세요: ==="
echo "s3://${S3_BUCKET}/${RESULT_FILE}"
