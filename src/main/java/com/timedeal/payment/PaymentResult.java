package com.timedeal.payment;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

/**
 * 포트원(PortOne) 스타일 결제 응답
 *
 * 성공: { "code": 0, "response": { "imp_uid": "...", "status": "paid", ... } }
 * 실패: { "code": -1, "message": "잔액 부족", "response": { "fail_reason": "...", ... } }
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class PaymentResult {

    private int code;
    private String message;
    private Response response;

    public boolean isSuccess() {
        return code == 0 && response != null && "paid".equals(response.status);
    }

    // imp_uid를 paymentId로 사용
    public String getPaymentId() {
        return response != null ? response.impUid : null;
    }

    public String getFailReason() {
        return response != null ? response.failReason : null;
    }

    public String getPgProvider() {
        return response != null ? response.pgProvider : null;
    }

    public String getCardName() {
        return response != null ? response.cardName : null;
    }

    @Data
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Response {

        @JsonProperty("imp_uid")
        private String impUid;

        @JsonProperty("merchant_uid")
        private String merchantUid;

        @JsonProperty("pg_provider")
        private String pgProvider;

        @JsonProperty("pg_tid")
        private String pgTid;

        @JsonProperty("card_name")
        private String cardName;

        @JsonProperty("card_number")
        private String cardNumber;

        @JsonProperty("status")
        private String status;

        @JsonProperty("fail_reason")
        private String failReason;

        @JsonProperty("pg_code")
        private String pgCode;

        @JsonProperty("category")
        private String category;

        @JsonProperty("amount")
        private Integer amount;

        @JsonProperty("receipt_url")
        private String receiptUrl;
    }
}
