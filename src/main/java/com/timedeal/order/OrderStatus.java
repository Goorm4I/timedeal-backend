package com.timedeal.order;

public enum OrderStatus {
    PENDING,    // 재고 확보, 결제 대기
    PAYING,     // 결제 중
    PAID,       // 결제 완료
    CONFIRMED,  // 주문 확정
    FAILED,     // 실패
    CANCELLED   // 취소
}