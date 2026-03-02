package com.timedeal.payment;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.time.Duration;

@Slf4j
@Service
@RequiredArgsConstructor
public class PaymentService {

    private final PaymentClient paymentClient;

    @Value("${payment.pg.timeout}")
    private int timeout;

    public PaymentResult pay(Long orderId, int amount) {
        PaymentResult result = paymentClient.requestPayment(orderId, amount, Duration.ofMillis(timeout));

        if (!result.isSuccess()) {
            // 실패 로그 - 카테고리별로 보기 좋게
            log.warn("[PG 결제 실패] orderId={} | 사유={} | 메시지={} | PG={}",
                    orderId,
                    result.getFailReason(),
                    result.getMessage(),
                    result.getPgProvider()
            );
            throw new PaymentException(result.getFailReason(), result.getMessage());
        }

        log.info("[PG 결제 성공] orderId={} | impUid={} | 카드={} | PG={}",
                orderId,
                result.getPaymentId(),
                result.getCardName(),
                result.getPgProvider()
        );

        return result;
    }
}
