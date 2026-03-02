package com.timedeal.stock;

import lombok.RequiredArgsConstructor;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Repository;

@Repository
@RequiredArgsConstructor
public class StockRepository {
    
    private final StringRedisTemplate redisTemplate;
    
    public boolean decrease(Long productId) {
        String key = "stock:" + productId;
        Long stock = redisTemplate.opsForValue().decrement(key);
        if (stock < 0) {
            redisTemplate.opsForValue().increment(key);
            return false;
        }
        return true;
    }
    
    public void increase(Long productId) {
        redisTemplate.opsForValue().increment("stock:" + productId);
    }
    
    public void reset(Long productId, int stock) {
        redisTemplate.opsForValue().set("stock:" + productId, String.valueOf(stock));
    }

    public long get(Long productId) {
        String value = redisTemplate.opsForValue().get("stock:" + productId);
        return value == null ? -1 : Long.parseLong(value);
    }
}