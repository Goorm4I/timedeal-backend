package com.timedeal.order;

import com.timedeal.product.ProductRepository;
import com.timedeal.stock.StockService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

@RestController
@RequiredArgsConstructor
public class OrderController {

    private final OrderService orderService;
    private final StockService stockService;
    private final ProductRepository productRepository;

    /** Step 4. 주문 시작 - Redis 재고 선점 + PENDING 생성 */
    @PostMapping("/api/orders")
    public ResponseEntity<OrderResponse> startOrder(@RequestBody @Valid OrderRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(orderService.startOrder(request));
    }

    /** Step 5. 결제 - PG 호출 + PAID/FAILED */
    @PostMapping("/api/orders/{orderId}/pay")
    public ResponseEntity<OrderResponse> processPayment(@PathVariable Long orderId) {
        return ResponseEntity.ok(orderService.processPayment(orderId));
    }

    /** Step 6. 결제 완료 확인 */
    @GetMapping("/api/orders/{orderId}")
    public ResponseEntity<OrderResponse> getOrder(@PathVariable Long orderId) {
        return ResponseEntity.ok(OrderResponse.from(orderService.getOrder(orderId)));
    }

    /** 재고 초기화 (테스트용) - Redis + DB stock 동시 초기화 */
    @Transactional
    @PostMapping("/api/admin/stock/reset")
    public ResponseEntity<Void> resetStock(@RequestParam Long productId, @RequestParam int stock) {
        stockService.reset(productId, stock);
        productRepository.resetStock(productId, stock);
        return ResponseEntity.ok().build();
    }

    /** 재고 조회 (K6 정합성 검증용) */
    @GetMapping("/api/admin/stock/{productId}")
    public ResponseEntity<StockResponse> getStock(@PathVariable Long productId) {
        return ResponseEntity.ok(new StockResponse(productId, stockService.get(productId)));
    }

    record StockResponse(Long productId, long remaining) {}
}
