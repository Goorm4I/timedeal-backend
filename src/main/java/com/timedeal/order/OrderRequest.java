package com.timedeal.order;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import lombok.Data;

@Data
public class OrderRequest {
    
    @NotNull(message = "상품 ID는 필수입니다")
    private Long productId;
    
    @NotNull(message = "사용자 ID는 필수입니다")
    private Long userId;
    
    @NotNull(message = "주문 금액은 필수입니다")
    @Positive(message = "주문 금액은 0보다 커야 합니다")
    private Integer amount;
    
    private String idempotencyKey;
}