/**
 * 타임딜 K6 테스트 - 표준 이커머스 플로우
 *
 * Step 4. POST /api/orders          주문 시작 (Redis 재고 선점 + PENDING)
 * Step 5. POST /api/orders/{id}/pay 결제 (PG 호출 + PAID/FAILED)
 * Step 6. GET  /api/orders/{id}     결제 완료 확인
 */

import http from 'k6/http';
import { check } from 'k6';
import { Counter, Trend } from 'k6/metrics';

const orderStarted    = new Counter('step4_order_started');   // PENDING 생성
const orderSoldOut    = new Counter('step4_sold_out');        // Redis 게이트 탈락
const paymentPaid     = new Counter('step5_paid');            // 결제 성공
const paymentFailed   = new Counter('step5_pay_failed');      // PG 실패 → 재고 복구
const step4Latency    = new Trend('step4_latency_ms');
const step5Latency    = new Trend('step5_latency_ms');

const BASE_URL   = __ENV.BASE_URL   || 'http://localhost:8080';
const PG_URL     = __ENV.PG_URL     || 'http://localhost:3000';
const PRODUCT_ID = __ENV.PRODUCT_ID || 1;
const STOCK      = parseInt(__ENV.STOCK    || '100');
const VUS        = parseInt(__ENV.VUS      || '200');
const SCENARIO   = __ENV.SCENARIO          || 'realistic';

export const options = {
  scenarios: {
    timedeal_rush: {
      executor: 'shared-iterations',
      vus: VUS,
      iterations: VUS,
      maxDuration: '120s',
    },
  },
  thresholds: {
    step4_latency_ms: ['p(95)<3000'],   // 주문 시작 (Redis gate + DB insert, 300VU 기준)
    step5_latency_ms: ['p(95)<8000'],   // 결제 (PG 포함, 300~800ms PG 지연)
  },
};

export function setup() {
  http.put(`${PG_URL}/scenario`,
    JSON.stringify({ scenario: SCENARIO }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  http.post(`${BASE_URL}/api/admin/stock/reset?productId=${PRODUCT_ID}&stock=${STOCK}`);
  http.post(`${PG_URL}/stats/reset`);

  const pg = JSON.parse(http.get(`${PG_URL}/stats`).body);
  console.log(`[SETUP] 시나리오=${SCENARIO} | 재고=${STOCK} | VU=${VUS}`);
  console.log(`[SETUP] PG 지연=${pg.config.min}~${pg.config.max}ms | 실패율=${(pg.config.failRate*100).toFixed(0)}%`);
  return { productId: PRODUCT_ID, initialStock: STOCK };
}

export default function (data) {
  // K6-1/K6-2는 --no-setup으로 실행 → data가 undefined일 수 있음 → env 폴백
  const productId = (data && data.productId != null) ? data.productId : PRODUCT_ID;
  const headers = { 'Content-Type': 'application/json' };

  // ── Step 4. 주문 시작 ─────────────────────────────────────────
  const t4 = Date.now();
  const step4 = http.post(
    `${BASE_URL}/api/orders`,
    JSON.stringify({
      productId: productId,
      userId: Math.floor(Math.random() * 100000) + 1,
      amount: 10000,
      idempotencyKey: `k6-vu${__VU}-iter${__ITER}`,
    }),
    { headers, timeout: '10s' }
  );
  step4Latency.add(Date.now() - t4);

  if (step4.status === 409) {
    // Redis 게이트 탈락 - 재고 소진
    orderSoldOut.add(1);
    check(step4, { 'SOLD_OUT 코드 확인': r => JSON.parse(r.body).code === 'SOLD_OUT' });
    return; // 결제 단계 없음
  }

  if (step4.status !== 201) {
    console.error(`[Step4 ERROR] ${step4.status}: ${step4.body}`);
    return;
  }

  orderStarted.add(1);
  const orderId = JSON.parse(step4.body).orderId;
  check(step4, {
    'Step4: PENDING 상태':  r => JSON.parse(r.body).status === 'PENDING',
    'Step4: orderId 발급':  r => orderId != null,
  });

  // ── Step 5. 결제 ─────────────────────────────────────────────
  const t5 = Date.now();
  const step5 = http.post(
    `${BASE_URL}/api/orders/${orderId}/pay`,
    null,
    { headers, timeout: '15s' }
  );
  step5Latency.add(Date.now() - t5);

  if (step5.status === 200) {
    paymentPaid.add(1);
    check(step5, {
      'Step5: PAID 상태': r => JSON.parse(r.body).status === 'PAID',
    });

    // ── Step 6. 결제 완료 확인 ───────────────────────────────────
    const step6 = http.get(`${BASE_URL}/api/orders/${orderId}`, { headers });
    check(step6, {
      'Step6: DB에 PAID 확인': r => JSON.parse(r.body).status === 'PAID',
    });

  } else if (step5.status === 502) {
    // PG 실패 → Redis 재고 복구됨
    paymentFailed.add(1);
    // 502 응답 형식 확인 (ErrorResponse: {code, message})
    check(step5, {
      'Step5: PG 실패 응답 확인': r => JSON.parse(r.body).code !== undefined,
    });
    // DB에 FAILED 상태 저장 확인 (GET으로 검증)
    const step5fail = http.get(`${BASE_URL}/api/orders/${orderId}`, { headers });
    check(step5fail, {
      'Step5: FAILED 상태 DB 저장': r => JSON.parse(r.body).status === 'FAILED',
    });
  }
}

export function teardown(data) {
  if (!data) return; // K6-1/K6-2 --no-teardown 방어 (실행되면 안 되지만 guard)
  const stock   = JSON.parse(http.get(`${BASE_URL}/api/admin/stock/${data.productId}`).body);
  const pg      = JSON.parse(http.get(`${PG_URL}/stats`).body);

  const remaining = stock.remaining;
  const paid      = pg.success;
  const isOk      = (remaining + paid) === data.initialStock;

  console.log('\n══════════════════════════════════════════════════════');
  console.log(`           타임딜 결과  [시나리오: ${SCENARIO}]`);
  console.log('══════════════════════════════════════════════════════');
  console.log(`초기 재고             : ${data.initialStock}개`);
  console.log(`남은 Redis 재고       : ${remaining}개`);
  console.log('──────────────────────────────────────────────────────');
  console.log(`[Step4] PENDING 생성  : ${pg.total}건`);
  console.log(`[Step5] PAID          : ${pg.success}건`);
  console.log(`[Step5] PG 실패(복구) : ${pg.failed}건`);
  console.log(`[Step5] PG 타임아웃   : ${pg.timeout}건`);
  console.log(`[Step5] PG 평균 응답  : ${pg.avgLatency}`);
  console.log('──────────────────────────────────────────────────────');
  console.log(`[정합성] ${data.initialStock} == ${remaining} + ${paid} → ${isOk ? '✅ PASS' : '❌ FAIL'}`);
  console.log('══════════════════════════════════════════════════════\n');
}
