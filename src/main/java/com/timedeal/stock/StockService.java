package com.timedeal.stock;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class StockService {
    
    private final StockRepository stockRepository;
    
    public boolean decrease(Long productId) {
        return stockRepository.decrease(productId);
    }
    
    public void increase(Long productId) {
        stockRepository.increase(productId);
    }
    
    public void reset(Long productId, int stock) {
        stockRepository.reset(productId, stock);
    }

    public long get(Long productId) {
        return stockRepository.get(productId);
    }
}