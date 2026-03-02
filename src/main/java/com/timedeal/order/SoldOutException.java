package com.timedeal.order;

public class SoldOutException extends RuntimeException {
    public SoldOutException(String message) {
        super(message);
    }
}