const express = require('express');
const app = express();
app.use(express.json());

// ── 스토어 ─────────────────────────────────────────────────────
const processedOrders  = new Map();   // orderId → 동기 응답 (멱등성)
const paymentStore     = new Map();   // imp_uid → 결제 결과
const callbackHistories = new Map();  // orderId → callback 이력 배열

// ── 시나리오 설정 ───────────────────────────────────────────────
const SCENARIOS = {
  optimistic: { min: 200,  max: 300,  failRate: 0.02, timeoutRate: 0.00 },
  realistic:  { min: 300,  max: 800,  failRate: 0.08, timeoutRate: 0.01 },
  peak:       { min: 500,  max: 1500, failRate: 0.15, timeoutRate: 0.03 },
  worst:      { min: 800,  max: 3000, failRate: 0.20, timeoutRate: 0.05 },
};

// 콜백 시나리오 프리셋
const CALLBACK_SCENARIOS = {
  stable:    { delayMin: 1000,  delayMax: 2000,  duplicateRate: 0.00, lossRate: 0.00, retryCount: 3, retryDelayMs: 10000 },
  realistic: { delayMin: 2000,  delayMax: 5000,  duplicateRate: 0.02, lossRate: 0.01, retryCount: 3, retryDelayMs: 10000 },
  chaos:     { delayMin: 3000,  delayMax: 10000, duplicateRate: 0.10, lossRate: 0.05, retryCount: 3, retryDelayMs: 5000  },
  nightmare: { delayMin: 5000,  delayMax: 30000, duplicateRate: 0.20, lossRate: 0.10, retryCount: 3, retryDelayMs: 3000  },
};

let config = { ...SCENARIOS.realistic, timeoutMs: 6000 };
let callbackConfig = { ...CALLBACK_SCENARIOS.stable };
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

const FAIL_SCENARIOS = [
  { category: 'BALANCE',  failReason: 'INSUFFICIENT_BALANCE',    message: '잔액이 부족합니다',             pgCode: 'F001', weight: 30 },
  { category: 'BALANCE',  failReason: 'DAILY_LIMIT_EXCEEDED',     message: '1일 결제한도를 초과했습니다',   pgCode: 'F002', weight: 20 },
  { category: 'BALANCE',  failReason: 'MONTHLY_LIMIT_EXCEEDED',   message: '월 결제한도를 초과했습니다',    pgCode: 'F003', weight: 10 },
  { category: 'CARD',     failReason: 'CARD_SUSPENDED',           message: '정지된 카드입니다',             pgCode: 'F010', weight: 8  },
  { category: 'CARD',     failReason: 'CARD_EXPIRED',             message: '유효기간이 만료된 카드입니다',  pgCode: 'F011', weight: 5  },
  { category: 'CARD',     failReason: 'INVALID_CARD_NUMBER',      message: '유효하지 않은 카드번호입니다',  pgCode: 'F012', weight: 3  },
  { category: 'CARD',     failReason: 'OVERSEAS_BLOCKED',         message: '해외결제가 차단된 카드입니다',  pgCode: 'F013', weight: 5  },
  { category: 'SECURITY', failReason: 'FRAUD_DETECTED',           message: '이상거래가 감지되었습니다',     pgCode: 'F020', weight: 5  },
  { category: 'SECURITY', failReason: 'WRONG_PASSWORD',           message: '비밀번호가 일치하지 않습니다',  pgCode: 'F021', weight: 4  },
  { category: 'NETWORK',  failReason: 'CARD_COMPANY_TIMEOUT',     message: '카드사 응답 시간 초과',         pgCode: 'F030', weight: 5  },
  { category: 'NETWORK',  failReason: 'CARD_COMPANY_MAINTENANCE', message: '카드사 시스템 점검 중입니다',   pgCode: 'F031', weight: 3  },
  { category: 'NETWORK',  failReason: 'PG_INTERNAL_ERROR',        message: 'PG사 내부 오류가 발생했습니다', pgCode: 'F032', weight: 2  },
];

// ── 유틸 함수 ──────────────────────────────────────────────────
function pickFailScenario() {
  const total = FAIL_SCENARIOS.reduce((sum, s) => sum + s.weight, 0);
  let rand = Math.random() * total;
  for (const s of FAIL_SCENARIOS) {
    rand -= s.weight;
    if (rand <= 0) return s;
  }
  return FAIL_SCENARIOS[0];
}

function randomCard()       { return CARDS[Math.floor(Math.random() * CARDS.length)]; }
function randomPgProvider() { return PG_PROVIDERS[Math.floor(Math.random() * PG_PROVIDERS.length)]; }
function now()              { return Math.floor(Date.now() / 1000); }
function generateImpUID()   { return `imp_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`; }
function randBetween(min, max) { return min + Math.random() * (max - min); }

function buildSuccessPayload(impUID, orderId, amount) {
  const card       = randomCard();
  const pgProvider = randomPgProvider();
  const pgTid      = `${pgProvider.toUpperCase()}${Date.now()}`;
  return {
    imp_uid:      impUID,
    merchant_uid: `order_${orderId}`,
    pg_provider:  pgProvider,
    pg_tid:       pgTid,
    pay_method:   'card',
    card_code:    card.code,
    card_name:    card.name,
    card_number:  card.number,
    card_quota:   0,
    status:       'paid',
    amount,
    currency:     'KRW',
    paid_at:      now(),
    receipt_url:  `https://portone.io/receipt/${impUID}`,
  };
}

function buildFailPayload(impUID, orderId, amount) {
  const card       = randomCard();
  const pgProvider = randomPgProvider();
  const scenario   = pickFailScenario();
  return {
    imp_uid:      impUID,
    merchant_uid: `order_${orderId}`,
    pg_provider:  pgProvider,
    card_name:    card.name,
    card_code:    card.code,
    status:       'failed',
    fail_reason:  scenario.failReason,
    pg_code:      scenario.pgCode,
    category:     scenario.category,
    amount,
    failed_at:    now(),
    _failMessage: scenario.message,  // 내부 참조용
  };
}

// ── 콜백 전송 (재시도 포함) ────────────────────────────────────
async function sendCallback(url, payload, orderId, attempt = 1) {
  const sentAt     = new Date().toISOString();
  const startTime  = Date.now();
  let httpStatus   = null;
  let status       = 'failed';

  try {
    const res = await fetch(url, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(payload),
      signal:  AbortSignal.timeout(10000),
    });
    httpStatus   = res.status;
    status       = res.ok ? 'success' : 'failed';
  } catch (e) {
    httpStatus = 0;
    status     = 'error';
  }

  const responseTime = Date.now() - startTime;

  // 이력 기록
  const history = callbackHistories.get(orderId) || [];
  history.push({ attempt, sentAt, url, status, httpStatus, responseTime });
  callbackHistories.set(orderId, history);

  console.log(`[Callback] orderId=${orderId} attempt=${attempt} status=${status} httpStatus=${httpStatus} ${responseTime}ms`);

  // 실패 시 재시도
  if (status !== 'success' && attempt < callbackConfig.retryCount) {
    setTimeout(() => sendCallback(url, payload, orderId, attempt + 1), callbackConfig.retryDelayMs);
  }
}

// ── 비동기 콜백 플로우 ─────────────────────────────────────────
function startAsyncCallback(impUID, orderId, amount, callbackUrl) {
  const delay = Math.round(randBetween(callbackConfig.delayMin, callbackConfig.delayMax));

  setTimeout(async () => {
    // 유실 체크
    if (Math.random() < callbackConfig.lossRate) {
      console.log(`[Callback] LOST for orderId=${orderId} impUID=${impUID}`);
      return;
    }

    // 결제 성공/실패 결정 (동기 결제와 동일 로직)
    let payload;
    if (Math.random() < config.failRate) {
      stats.failed++;
      payload = buildFailPayload(impUID, orderId, amount);
      stats.failReasons[payload.fail_reason] = (stats.failReasons[payload.fail_reason] || 0) + 1;
    } else {
      stats.success++;
      payload = buildSuccessPayload(impUID, orderId, amount);
    }

    // 결제 결과 저장
    paymentStore.set(impUID, payload);

    // 1차 전송
    await sendCallback(callbackUrl, payload, orderId, 1);

    // 중복 전송 체크
    if (Math.random() < callbackConfig.duplicateRate) {
      const dupDelay = Math.round(randBetween(100, 500));
      setTimeout(async () => {
        console.log(`[Callback] DUPLICATE for orderId=${orderId}`);
        await sendCallback(callbackUrl, payload, orderId, 0);  // attempt=0 = 중복 표시
      }, dupDelay);
    }
  }, delay);
}

// ── 동기 결제 ─────────────────────────────────────────────────
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
    return res.status(504).json({ code: -1, message: 'PG사 응답 없음 (Gateway Timeout)', response: null });
  }

  // PG 지연 시뮬레이션
  const delay = config.min + Math.random() * (config.max - config.min);
  await new Promise(r => setTimeout(r, delay));
  stats.latencies.push(Date.now() - start);

  const impUID = generateImpUID();

  // 결제 실패
  if (Math.random() < config.failRate) {
    stats.failed++;
    const data = buildFailPayload(impUID, orderId, amount);
    stats.failReasons[data.fail_reason] = (stats.failReasons[data.fail_reason] || 0) + 1;

    const failResponse = {
      code:     -1,
      message:  data._failMessage,
      response: { ...data, _failMessage: undefined },
    };
    return res.status(400).json(failResponse);
  }

  // 결제 성공
  stats.success++;
  const data            = buildSuccessPayload(impUID, orderId, amount);
  paymentStore.set(impUID, data);
  const successResponse = { code: 0, message: null, response: data };

  if (orderId) processedOrders.set(String(orderId), successResponse);
  res.json(successResponse);
});

// ── 비동기 결제 ───────────────────────────────────────────────
app.post('/pay/async', async (req, res) => {
  const { orderId, amount, callbackUrl } = req.body;

  if (!callbackUrl) {
    return res.status(400).json({ code: -1, message: 'callbackUrl 필수', response: null });
  }

  stats.total++;
  const impUID = generateImpUID();

  // 결제 초기 상태 저장 (pending)
  const pending = {
    imp_uid:      impUID,
    merchant_uid: `order_${orderId}`,
    status:       'pending',
    amount,
    requested_at: now(),
  };
  paymentStore.set(impUID, pending);

  // 비동기 콜백 시작
  startAsyncCallback(impUID, String(orderId), amount, callbackUrl);

  res.status(202).json({
    code:    0,
    message: '결제 요청 접수',
    response: {
      imp_uid:      impUID,
      merchant_uid: `order_${orderId}`,
      status:       'pending',
    },
  });
});

// ── 결제 상태 조회 (Polling) ───────────────────────────────────
app.get('/payments/:imp_uid', (req, res) => {
  const { imp_uid } = req.params;
  const result = paymentStore.get(imp_uid);

  if (!result) {
    return res.status(404).json({ code: -1, message: '결제 정보 없음', response: null });
  }

  res.json({ code: 0, response: result });
});

// ── 결제 취소 ─────────────────────────────────────────────────
app.post('/payments/:imp_uid/cancel', (req, res) => {
  const { imp_uid } = req.params;
  const result = paymentStore.get(imp_uid);

  if (!result) {
    return res.status(404).json({ code: -1, message: '결제 정보 없음', response: null });
  }

  if (result.status !== 'paid') {
    return res.status(400).json({ code: -1, message: `취소 불가 상태: ${result.status}`, response: null });
  }

  const cancelledAt = now();
  const updated     = { ...result, status: 'cancelled', cancelled_at: cancelledAt };
  paymentStore.set(imp_uid, updated);

  res.json({
    code:    0,
    message: '결제 취소 완료',
    response: updated,
  });
});

// ── 콜백 수동 트리거 ──────────────────────────────────────────
app.post('/callbacks/trigger', async (req, res) => {
  const { imp_uid, forceStatus, callbackUrl } = req.body;

  if (!imp_uid) {
    return res.status(400).json({ code: -1, message: 'imp_uid 필수' });
  }

  const stored = paymentStore.get(imp_uid);
  if (!stored) {
    return res.status(404).json({ code: -1, message: '결제 정보 없음' });
  }

  const payload = forceStatus
    ? { ...stored, status: forceStatus }
    : stored;

  const targetUrl = callbackUrl || req.body.url;
  if (!targetUrl) {
    return res.status(400).json({ code: -1, message: 'callbackUrl 필수' });
  }

  const orderId = stored.merchant_uid?.replace('order_', '') || imp_uid;
  await sendCallback(targetUrl, payload, orderId, 1);

  res.json({ code: 0, message: '콜백 트리거 완료', payload });
});

// ── 콜백 이력 조회 ────────────────────────────────────────────
app.get('/callbacks/history/:orderId', (req, res) => {
  const { orderId } = req.params;
  const history     = callbackHistories.get(orderId) || [];

  res.json({ orderId, callbacks: history });
});

// ── 콜백 설정 ─────────────────────────────────────────────────
app.put('/callback-config', (req, res) => {
  const { scenario, ...overrides } = req.body;

  if (scenario) {
    if (!CALLBACK_SCENARIOS[scenario]) {
      return res.status(400).json({ error: `가능한 시나리오: ${Object.keys(CALLBACK_SCENARIOS).join(', ')}` });
    }
    callbackConfig = { ...CALLBACK_SCENARIOS[scenario] };
  }

  Object.assign(callbackConfig, overrides);
  res.json({ message: '콜백 설정 변경', callbackConfig });
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
  const avg    = sorted.length ? Math.round(sorted.reduce((a, b) => a + b, 0) / sorted.length) : 0;
  const p95    = sorted.length ? sorted[Math.floor(sorted.length * 0.95)] : 0;

  res.json({
    total:       stats.total,
    success:     stats.success,
    failed:      stats.failed,
    timeout:     stats.timeout,
    successRate: stats.total > 0 ? ((stats.success / stats.total) * 100).toFixed(1) + '%' : '0%',
    avgLatency:  avg + 'ms',
    p95Latency:  p95 + 'ms',
    failReasons: stats.failReasons,
    config,
    callbackConfig,
  });
});

app.post('/stats/reset', (req, res) => {
  stats = { total: 0, success: 0, failed: 0, timeout: 0, latencies: [], failReasons: {} };
  processedOrders.clear();
  paymentStore.clear();
  callbackHistories.clear();
  res.json({ message: '초기화 완료' });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

// Cloud Run을 위해 PORT 환경 변수 사용 (로컬은 3000, Cloud Run은 8080)
const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Mock PG (PortOne style) on http://localhost:${port}`);
  console.log('결제 시나리오: optimistic | realistic | peak | worst');
  console.log('콜백 시나리오: stable | realistic | chaos | nightmare');
});
