package com.timedeal.payment;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestTemplate;

import java.time.Duration;

@Component
public class PaymentClient {

    private final RestTemplate restTemplate;

    @Value("${payment.pg.url}")
    private String pgUrl;

    public PaymentClient(@Value("${payment.pg.timeout}") int timeoutMs) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(3000);        // 연결 타임아웃 3초
        factory.setReadTimeout(timeoutMs);      // 응답 대기 타임아웃 (application.yml 설정값)
        this.restTemplate = new RestTemplate(factory);
    }

    public PaymentResult requestPayment(Long orderId, int amount, Duration duration) {
        PaymentRequest request = new PaymentRequest(orderId, amount);
        try {
            return restTemplate.postForObject(pgUrl + "/pay", request, PaymentResult.class);
        } catch (ResourceAccessException e) {
            // 타임아웃 또는 연결 실패
            throw new PaymentException("PG_TIMEOUT", "결제 응답 시간 초과: " + e.getMessage());
        } catch (Exception e) {
            throw new PaymentException("PG_ERROR", "결제 오류: " + e.getMessage());
        }
    }
}
