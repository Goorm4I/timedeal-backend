package com.timedeal.idempotency;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.Optional;

@Service
@RequiredArgsConstructor
public class IdempotencyService {
    
    private final StringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper;
    
    public boolean isProcessed(String key) {
        return Boolean.TRUE.equals(redisTemplate.hasKey("idem:" + key));
    }
    
    public Optional<String> getResult(String key) {
        return Optional.ofNullable(redisTemplate.opsForValue().get("idem:" + key));
    }
    
    public void markProcessing(String key) {
        redisTemplate.opsForValue().set("idem:" + key, "PROCESSING", Duration.ofMinutes(5));
    }
    
    public void saveResult(String key, Object result) {
        try {
            String json = objectMapper.writeValueAsString(result);
            redisTemplate.opsForValue().set("idem:" + key, json, Duration.ofHours(1));
        } catch (JsonProcessingException e) {
            throw new RuntimeException(e);
        }
    }
}