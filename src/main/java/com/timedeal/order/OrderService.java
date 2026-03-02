package com.timedeal.order;

import com.timedeal.idempotency.IdempotencyService;
import com.timedeal.payment.PaymentException;
import com.timedeal.payment.PaymentResult;
import com.timedeal.payment.PaymentService;
import com.timedeal.stock.StockService;
import jakarta.persistence.EntityNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class OrderService {

    private final StockService stockService;
    private final PaymentService paymentService;
    private final OrderPersistenceService orderPersistenceService;
    private final OrderRepository orderRepository;
    private final IdempotencyService idempotencyService;

    /**
     * Step 4. 주문 시작
     * @Transactional OK - PG 없음, Redis DECR + DB PENDING 저장만
     */
    @Transactional
    public OrderResponse startOrder(OrderRequest request) {
        String idempotencyKey = request.getIdempotencyKey();

        if (idempotencyKey != null) {
            if (idempotencyService.isProcessed(idempotencyKey)) {
                String existing = idempotencyService.getResult(idempotencyKey).orElse("처리 중");
                return OrderResponse.fail("이미 처리된 요청입니다: " + existing);
            }
            idempotencyService.markProcessing(idempotencyKey);
        }

        if (!stockService.decrease(request.getProductId())) {
            throw new SoldOutException("재고 소진");
        }

        Order order = orderPersistenceService.createPending(request);
        return OrderResponse.pending(order);
    }

    /**
     * Step 5. 결제
     *
     * 멱등성 처리:
     *   - SELECT FOR UPDATE → 동시 요청 직렬화
     *   - PENDING → PAYING 상태 변경 후 커밋 → 락 플래그
     *   - orderId를 PG 멱등성 키로 전달 → PG 수준 이중 결제 방지
     *
     * @Transactional 없음 - PG 호출 포함
     */
    public OrderResponse processPayment(Long orderId) {
        // SELECT FOR UPDATE → PAYING으로 변경 후 커밋 (동시 중복 요청 차단)
        Order order = orderPersistenceService.markPayingIfPending(orderId);

        if (order == null) {
            // 이미 처리 중이거나 완료된 주문 → 현재 상태 반환
            Order current = orderRepository.findById(orderId)
                    .orElseThrow(() -> new EntityNotFoundException("주문 없음: " + orderId));
            return OrderResponse.from(current);
        }

        // PG 호출 - orderId를 PG 멱등성 키로 사용 (실제 PG는 X-Idempotency-Key 지원)
        try {
            PaymentResult result = paymentService.pay(orderId, order.getAmount());

            Order paid = orderPersistenceService.confirmPaid(orderId, result);
            return OrderResponse.success(paid);

        } catch (PaymentException e) {
            orderPersistenceService.markFailed(orderId);
            stockService.increase(order.getProductId());
            throw e;
        }
    }

    /** Step 6. 결제 완료 확인 */
    public Order getOrder(Long orderId) {
        return orderRepository.findById(orderId)
                .orElseThrow(() -> new EntityNotFoundException("주문 없음: " + orderId));
    }
}
