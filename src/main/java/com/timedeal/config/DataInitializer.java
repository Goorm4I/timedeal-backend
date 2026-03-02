package com.timedeal.config;

import com.timedeal.product.Product;
import com.timedeal.product.ProductRepository;
import com.timedeal.stock.StockService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class DataInitializer implements ApplicationRunner {

    private final ProductRepository productRepository;
    private final StockService stockService;

    @Override
    public void run(ApplicationArguments args) {
        // 상품 ID=1 없으면 생성
        if (productRepository.findById(1L).isEmpty()) {
            Product product = Product.builder()
                    .name("타임딜 한정 상품")
                    .price(99000)
                    .initialStock(100)
                    .stock(100)
                    .build();
            productRepository.save(product);
            log.info("[DataInitializer] 타임딜 상품 생성 완료 (id=1, stock=100)");
        }

        // Redis 재고 초기화 (DB stock 기준으로 동기화)
        productRepository.findById(1L).ifPresent(product -> {
            long redisStock = stockService.get(1L);
            if (redisStock < 0) {
                // Redis에 키가 없거나 음수 → DB stock으로 재건
                stockService.reset(1L, product.getStock());
                log.info("[DataInitializer] Redis 재고 초기화: stock={}", product.getStock());
            } else {
                log.info("[DataInitializer] Redis 재고 유지: redisStock={}, dbStock={}", redisStock, product.getStock());
            }
        });
    }
}
