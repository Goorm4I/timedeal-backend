package com.timedeal.order;

import lombok.AllArgsConstructor;
import lombok.Data;

@Data
@AllArgsConstructor
public class OrderResponse {
    private Long orderId;
    private OrderStatus status;
    private String message;

    public static OrderResponse pending(Order order) {
        return new OrderResponse(order.getId(), OrderStatus.PENDING, "주문이 시작되었습니다. 결제를 진행해주세요.");
    }

    public static OrderResponse success(Order order) {
        return new OrderResponse(order.getId(), OrderStatus.PAID, "결제가 완료되었습니다.");
    }

    public static OrderResponse from(Order order) {
        return new OrderResponse(order.getId(), order.getStatus(), order.getStatus().name());
    }

    public static OrderResponse fail(String message) {
        return new OrderResponse(null, null, message);
    }
}
