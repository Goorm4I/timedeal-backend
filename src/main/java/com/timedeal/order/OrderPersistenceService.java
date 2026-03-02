package com.timedeal.order;

import com.timedeal.payment.PaymentResult;
import com.timedeal.product.ProductRepository;
import jakarta.persistence.EntityNotFoundException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Service
@RequiredArgsConstructor
public class OrderPersistenceService {

    private final OrderRepository orderRepository;
    private final ProductRepository productRepository;

    /** Step 4: PENDING 저장 */
    @Transactional
    public Order createPending(OrderRequest request) {
        return orderRepository.save(
            Order.builder()
                .productId(request.getProductId())
                .userId(request.getUserId())
                .amount(request.getAmount())
                .status(OrderStatus.PENDING)
                .build()
        );
    }

    /**
     * Step 5 진입: SELECT FOR UPDATE + PAYING 마킹.
     * 동시 중복 요청을 DB 레벨에서 직렬화.
     */
    @Transactional
    public Order markPayingIfPending(Long orderId) {
        Order order = orderRepository.findByIdWithLock(orderId)
                .orElseThrow(() -> new EntityNotFoundException("주문 없음: " + orderId));

        if (order.getStatus() != OrderStatus.PENDING) {
            return null; // 이미 처리 중 or 완료 → 중복 요청
        }

        order.setStatus(OrderStatus.PAYING);
        return orderRepository.save(order);
    }

    /**
     * Step 5 성공: 하나의 @Transactional 안에서
     *   1. PAID 주문 저장
     *   2. DB stock 원자적 차감 (WHERE stock > 0)
     *
     * Redis(이미 차감됨) + DB stock 동기화 완성.
     * 둘 다 같은 트랜잭션이므로 DB stock 차감 실패 시 PAID 저장도 롤백.
     */
    @Transactional
    public Order confirmPaid(Long orderId, PaymentResult result) {
        Order order = getOrThrow(orderId);
        order.setStatus(OrderStatus.PAID);
        order.setPaymentId(result.getPaymentId());
        orderRepository.save(order);

        // DB Atomic UPDATE: stock - 1 (WHERE stock > 0)
        int affected = productRepository.decrementStock(order.getProductId());
        if (affected == 0) {
            // Redis는 통과했는데 DB stock이 0 → 정합성 오류
            log.error("[정합성 오류] Redis 재고는 있었으나 DB stock=0. productId={}", order.getProductId());
            throw new IllegalStateException("재고 정합성 오류: DB stock 차감 실패");
        }

        return order;
    }

    /** Step 5 실패: FAILED 저장. DB stock은 건드리지 않음 (Redis INCR로만 복구). */
    @Transactional
    public Order markFailed(Long orderId) {
        Order order = getOrThrow(orderId);
        order.setStatus(OrderStatus.FAILED);
        return orderRepository.save(order);
    }

    private Order getOrThrow(Long orderId) {
        return orderRepository.findById(orderId)
                .orElseThrow(() -> new EntityNotFoundException("주문 없음: " + orderId));
    }
}
