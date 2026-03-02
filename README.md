# Timedeal Backend - 고동시성 타임딜 시스템

Redis 재고 게이트 → PG 결제 → PostgreSQL 확정의 3단계 구조로
수천 명 동시 주문을 처리하는 타임딜 백엔드.

---

## 빠른 시작 (로컬 실행)

> 사전 준비: [Docker Desktop](https://www.docker.com/products/docker-desktop/) 설치

```bash
# 1. 클론
git clone https://github.com/Goorm4I/timedeal-backend.git
cd timedeal-backend

# 2. 모든 서비스 한 번에 실행 (PostgreSQL + Redis + Mock PG + Spring Boot)
docker compose up --build

# 3. 실행 확인 (http://localhost:8080/actuator/health → {"status":"UP"})
curl http://localhost:8080/actuator/health
```

> 처음 실행 시 Maven 빌드 + Docker 이미지 빌드로 3~5분 소요됩니다.

### 실행 서비스

| 서비스 | 포트 | 설명 |
|--------|------|------|
| Spring Boot | 8080 | 타임딜 API |
| PostgreSQL | 5432 | 주문/상품 DB |
| Redis | 6379 | 재고 게이트 |
| Mock PG | 3000 | 결제 PG 시뮬레이터 (PortOne 모방) |

---

## API 명세

### 주문 플로우 (3단계)

```
Step 4. POST /api/orders          주문 시작 (Redis 재고 선점 + PENDING 생성)
Step 5. POST /api/orders/{id}/pay 결제 (PG 호출 + PAID/FAILED)
Step 6. GET  /api/orders/{id}     결제 완료 확인
```

#### Step 4. 주문 시작

```bash
curl -X POST http://localhost:8080/api/orders \
  -H "Content-Type: application/json" \
  -d '{"productId": 1, "userId": 42}'
```

응답 (201 Created):
```json
{"orderId": 1001, "status": "PENDING", "productId": 1, "userId": 42}
```

재고 소진 시 (409 Conflict):
```json
{"error": "SOLD_OUT", "message": "재고가 소진되었습니다."}
```

#### Step 5. 결제

```bash
curl -X POST http://localhost:8080/api/orders/1001/pay
```

응답 (200 OK):
```json
{"orderId": 1001, "status": "PAID", "productId": 1, "userId": 42}
```

#### Step 6. 주문 조회

```bash
curl http://localhost:8080/api/orders/1001
```

### 테스트용 API

```bash
# 재고 초기화 (K6 테스트 전 필수)
curl -X POST "http://localhost:8080/api/admin/stock/reset?productId=1&stock=100"

# 현재 재고 조회
curl http://localhost:8080/api/admin/stock/1

# Mock PG 시나리오 변경 (결제 지연/실패율 조정)
curl -X PUT http://localhost:3000/scenario \
  -H "Content-Type: application/json" \
  -d '{"scenario": "realistic"}'

# Mock PG 통계 확인
curl http://localhost:3000/stats
```

#### Mock PG 시나리오

| 시나리오 | PG 지연 | 실패율 |
|---------|---------|--------|
| `optimistic` | 200~300ms | 2% |
| `realistic` | 300~800ms | 8% |
| `peak` | 500~1500ms | 15% |
| `worst` | 800~3000ms | 20% |

---

## K6 부하 테스트 (로컬)

> 사전 준비: [K6 설치](https://grafana.com/docs/k6/latest/set-up/install-k6/)

```bash
# 재고 초기화
curl -X POST "http://localhost:8080/api/admin/stock/reset?productId=1&stock=100"

# 200명 동시 주문 테스트 (realistic 시나리오)
k6 run \
  -e VUS=200 \
  -e STOCK=100 \
  -e SCENARIO=realistic \
  k6/timedeal-test.js
```

주요 메트릭:
- `step4_latency_ms` — 주문 시작 레이턴시 (Redis + DB INSERT)
- `step5_latency_ms` — 결제 레이턴시 (PG 포함)
- `step4_sold_out` — 재고 소진으로 탈락한 요청 수
- `step5_paid` / `step5_pay_failed` — 결제 성공/실패 수

정합성 검증 (K6 완료 후):
```bash
# Redis 재고 == DB 재고 == 초기재고 - 결제성공건수 이어야 함
curl http://localhost:8080/api/admin/stock/1
```

---

## 주문 플로우 (트랜잭션 분기)

```
[수천 명 동시 요청]
         │
         ▼
Step 4. POST /api/orders
  @Transactional {
    [Redis] DECR stock: 100 → 99   ← 선착순 게이트 (원자적)
    [DB]    INSERT order PENDING
  } → commit → orderId 반환
         │
    ┌────┴────┐
 통과(N명)  탈락(수천명)
    │         │
    │       409 SOLD_OUT 즉시 반환
    ▼
Step 5. POST /api/orders/{orderId}/pay
  [DB] SELECT FOR UPDATE → PAYING  ← 중복 요청 직렬화
         │
    PG 호출 (DB 커넥션 없이)
    orderId = PG 멱등성 키
         │
    ┌────┴────┐
  성공      실패
    │         │
  @Tx {     [Redis] INCR stock  ← 재고 복구
  PAID 저장  @Tx { FAILED 저장 }
  stock-1
  }
    │
  200 PAID 반환
```

---

## 재고 정합성 구조

```
              Redis stock          DB stock (products.stock)
초기              100                      100
주문시작(DECR)     99                      100   ← DB는 아직 그대로
결제성공           99                       99   ← @Tx 안에서 동시 차감
결제실패(INCR)    100                      100   ← Redis만 복구, DB 불변

정합성 공식:
  Redis stock == DB stock == 초기재고 - COUNT(PAID orders)
```

---

## 전체 아키텍처 (AWS)

```
┌──────────────────────────────── ap-northeast-2 (Seoul) ───────────────────┐
│                                                                            │
│  ┌──────────────── Public Subnet ──────────────────┐                      │
│  │                                                  │                      │
│  │  [IGW] → ALB (t3.small)  K6 EC2 ×3 (t3.micro)  │                      │
│  │                           VU 300명/대 = 총 900명 │                      │
│  └───────────────────┬──────────────────────────────┘                      │
│                      │                                                      │
│  ┌──────────────── Private Subnet ─────────────────┐                      │
│  │                                                  │                      │
│  │  Spring Boot EC2 (t3.medium)                     │                      │
│  │  Tomcat 400 threads | HikariCP pool 50           │                      │
│  │         │                  │               │     │                      │
│  │  ElastiCache Redis  RDS PostgreSQL    Mock PG    │                      │
│  │  (재고 게이트)       (주문/상품 DB)   EC2 :3000  │                      │
│  │                                                  │                      │
│  └──────────────────────────────────────────────────┘                      │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## 기술 스택

| 레이어 | 기술 |
|--------|------|
| Backend | Spring Boot 3.5, Java 17 |
| DB | PostgreSQL 15 |
| Cache | Redis 7 |
| 부하 테스트 | K6 |
| IaC | Terraform (AWS) |
| Mock PG | Node.js (PortOne 응답 모방) |

---

## 프로젝트 구조

```
timedeal-backend/
├── src/main/java/com/timedeal/
│   ├── config/          WebConfig, RedisConfig, GlobalExceptionHandler
│   ├── order/           OrderController, OrderService, OrderRepository, Order(Entity)
│   ├── payment/         PaymentService, PaymentClient (Mock PG 호출)
│   ├── product/         Product(Entity), ProductRepository
│   ├── stock/           StockService (Redis DECR/INCR)
│   └── idempotency/     IdempotencyService (중복 결제 방지)
├── mock-pg/             결제 PG 시뮬레이터 (Node.js)
├── k6/                  K6 부하 테스트 스크립트
├── terraform/           AWS 인프라 코드
├── scripts/             배포·테스트 자동화 스크립트
├── docker-compose.yml   로컬 개발 환경 (PostgreSQL + Redis + Mock PG + App)
└── Dockerfile           Spring Boot 컨테이너 이미지
```
