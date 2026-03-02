const express = require('express');
const app = express();
app.use(express.json());

// PG 수준 멱등성
const processedOrders = new Map();

// 시나리오별 설정
const SCENARIOS = {
  optimistic: { min: 200,  max: 300,  failRate: 0.02, timeoutRate: 0.00 },
  realistic:  { min: 300,  max: 800,  failRate: 0.08, timeoutRate: 0.01 },
  peak:       { min: 500,  max: 1500, failRate: 0.15, timeoutRate: 0.03 },
  worst:      { min: 800,  max: 3000, failRate: 0.20, timeoutRate: 0.05 },
};

let config = { ...SCENARIOS.realistic, timeoutMs: 6000 };
let stats = { total: 0, success: 0, failed: 0, timeout: 0, latencies: [], failReasons: {} };

// ── 포트원 스타일 데이터 ───────────────────────────────────────

const PG_PROVIDERS = ['kcp', 'inicis', 'toss', 'nice', 'kakao'];

const CARDS = [
  { code: '361', name: '신한카드',  number: '4111-11**-****-1111' },
  { code: '381', name: '국민카드',  number: '5301-21**-****-8832' },
  { code: '041', name: '우리카드',  number: '9410-04**-****-5521' },
  { code: '071', name: '현대카드',  number: '4324-11**-****-9901' },
  { code: '051', name: '삼성카드',  number: '5413-00**-****-3317' },
  { code: '011', name: '농협카드',  number: '9490-22**-****-0044' },
  { code: '091', name: 'BC카드',    number: '4101-33**-****-7788' },
  { code: '031', name: '하나카드',  number: '5678-44**-****-2290' },
];

// 포트원 실패 시나리오 - 카테고리별 분류
const FAIL_SCENARIOS = [
  // 잔액/한도 관련 (가장 흔함)
  { category: 'BALANCE',  failReason: 'INSUFFICIENT_BALANCE',    message: '잔액이 부족합니다',            pgCode: 'F001', weight: 30 },
  { category: 'BALANCE',  failReason: 'DAILY_LIMIT_EXCEEDED',     message: '1일 결제한도를 초과했습니다',  pgCode: 'F002', weight: 20 },
  { category: 'BALANCE',  failReason: 'MONTHLY_LIMIT_EXCEEDED',   message: '월 결제한도를 초과했습니다',   pgCode: 'F003', weight: 10 },

  // 카드 상태 관련
  { category: 'CARD',     failReason: 'CARD_SUSPENDED',           message: '정지된 카드입니다',            pgCode: 'F010', weight: 8 },
  { category: 'CARD',     failReason: 'CARD_EXPIRED',             message: '유효기간이 만료된 카드입니다', pgCode: 'F011', weight: 5 },
  { category: 'CARD',     failReason: 'INVALID_CARD_NUMBER',      message: '유효하지 않은 카드번호입니다', pgCode: 'F012', weight: 3 },
  { category: 'CARD',     failReason: 'OVERSEAS_BLOCKED',         message: '해외결제가 차단된 카드입니다', pgCode: 'F013', weight: 5 },

  // 보안/이상거래
  { category: 'SECURITY', failReason: 'FRAUD_DETECTED',           message: '이상거래가 감지되었습니다',    pgCode: 'F020', weight: 5 },
  { category: 'SECURITY', failReason: 'WRONG_PASSWORD',           message: '비밀번호가 일치하지 않습니다', pgCode: 'F021', weight: 4 },

  // 네트워크/시스템
  { category: 'NETWORK',  failReason: 'CARD_COMPANY_TIMEOUT',     message: '카드사 응답 시간 초과',        pgCode: 'F030', weight: 5 },
  { category: 'NETWORK',  failReason: 'CARD_COMPANY_MAINTENANCE', message: '카드사 시스템 점검 중입니다',  pgCode: 'F031', weight: 3 },
  { category: 'NETWORK',  failReason: 'PG_INTERNAL_ERROR',        message: 'PG사 내부 오류가 발생했습니다',pgCode: 'F032', weight: 2 },
];

// 가중치 기반 랜덤 실패 선택
function pickFailScenario() {
  const total = FAIL_SCENARIOS.reduce((sum, s) => sum + s.weight, 0);
  let rand = Math.random() * total;
  for (const s of FAIL_SCENARIOS) {
    rand -= s.weight;
    if (rand <= 0) return s;
  }
  return FAIL_SCENARIOS[0];
}

function randomCard() {
  return CARDS[Math.floor(Math.random() * CARDS.length)];
}

function randomPgProvider() {
  return PG_PROVIDERS[Math.floor(Math.random() * PG_PROVIDERS.length)];
}

function now() {
  return Math.floor(Date.now() / 1000);
}

// ── 결제 엔드포인트 ───────────────────────────────────────────

app.post('/pay', async (req, res) => {
  const { orderId, amount } = req.body;

  // PG 수준 멱등성
  if (orderId && processedOrders.has(String(orderId))) {
    return res.json(processedOrders.get(String(orderId)));
  }

  stats.total++;
  const start = Date.now();

  // 타임아웃 시나리오
  if (Math.random() < config.timeoutRate) {
    stats.timeout++;
    await new Promise(r => setTimeout(r, config.timeoutMs));
    return res.status(504).json({
      code: -1,
      message: 'PG사 응답 없음 (Gateway Timeout)',
      response: null,
    });
  }

  // PG 지연 시뮬레이션
  const delay = config.min + Math.random() * (config.max - config.min);
  await new Promise(r => setTimeout(r, delay));
  stats.latencies.push(Date.now() - start);

  const card = randomCard();
  const pgProvider = randomPgProvider();
  const merchantUid = `order_${orderId}`;

  // 결제 실패
  if (Math.random() < config.failRate) {
    stats.failed++;
    const scenario = pickFailScenario();

    // 실패 사유 통계
    stats.failReasons[scenario.failReason] = (stats.failReasons[scenario.failReason] || 0) + 1;

    const failResponse = {
      code: -1,
      message: scenario.message,
      response: {
        merchant_uid:  merchantUid,
        pg_provider:   pgProvider,
        card_name:     card.name,
        card_code:     card.code,
        status:        'failed',
        fail_reason:   scenario.failReason,
        pg_code:       scenario.pgCode,
        category:      scenario.category,
        amount:        amount,
        failed_at:     now(),
      },
    };

    return res.status(400).json(failResponse);
  }

  // 결제 성공 - 포트원 스타일 응답
  stats.success++;
  const impUid = `imp_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const pgTid  = `${pgProvider.toUpperCase()}${Date.now()}`;

  const successResponse = {
    code: 0,
    message: null,
    response: {
      imp_uid:      impUid,
      merchant_uid: merchantUid,
      pg_provider:  pgProvider,
      pg_tid:       pgTid,
      pay_method:   'card',
      card_code:    card.code,
      card_name:    card.name,
      card_number:  card.number,
      card_quota:   0,       // 일시불
      status:       'paid',
      amount:       amount,
      currency:     'KRW',
      paid_at:      now(),
      receipt_url:  `https://portone.io/receipt/${impUid}`,
    },
  };

  if (orderId) processedOrders.set(String(orderId), successResponse);
  res.json(successResponse);
});

// ── 관리 API ──────────────────────────────────────────────────

app.put('/scenario', (req, res) => {
  const { scenario } = req.body;
  if (!SCENARIOS[scenario]) {
    return res.status(400).json({ error: `가능한 시나리오: ${Object.keys(SCENARIOS).join(', ')}` });
  }
  config = { ...SCENARIOS[scenario], timeoutMs: config.timeoutMs };
  res.json({ message: `시나리오 변경: ${scenario}`, config });
});

app.put('/config', (req, res) => {
  Object.assign(config, req.body);
  res.json({ config });
});

app.get('/stats', (req, res) => {
  const sorted = [...stats.latencies].sort((a, b) => a - b);
  const avg = sorted.length ? Math.round(sorted.reduce((a, b) => a + b, 0) / sorted.length) : 0;
  const p95 = sorted.length ? sorted[Math.floor(sorted.length * 0.95)] : 0;

  res.json({
    total:       stats.total,
    success:     stats.success,
    failed:      stats.failed,
    timeout:     stats.timeout,
    successRate: stats.total > 0 ? ((stats.success / stats.total) * 100).toFixed(1) + '%' : '0%',
    avgLatency:  avg + 'ms',
    p95Latency:  p95 + 'ms',
    failReasons: stats.failReasons,   // 실패 사유 분포
    config,
  });
});

app.post('/stats/reset', (req, res) => {
  stats = { total: 0, success: 0, failed: 0, timeout: 0, latencies: [], failReasons: {} };
  processedOrders.clear();
  res.json({ message: '초기화 완료' });
});

// Cloud Run을 위해 PORT 환경 변수 사용 (로컬은 3000, Cloud Run은 8080)
const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Mock PG (PortOne style) on http://localhost:${port}`);
  console.log('시나리오: optimistic | realistic | peak | worst');
});
