package com.timedeal.product;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface ProductRepository extends JpaRepository<Product, Long> {

    /**
     * DB Atomic UPDATE - 락 없이 원자적 재고 차감.
     *
     * WHERE stock > 0 조건으로 음수 방지.
     * 반환값: 업데이트된 행 수 (0이면 재고 없음 = 정합성 오류)
     *
     * PostgreSQL 실행 쿼리:
     *   UPDATE products SET stock = stock - 1 WHERE id = ? AND stock > 0
     */
    @Modifying
    @Query("UPDATE Product p SET p.stock = p.stock - 1 WHERE p.id = :id AND p.stock > 0")
    int decrementStock(@Param("id") Long productId);

    /**
     * 결제 실패/취소 시 DB 재고 복구 (Redis INCR과 함께 호출).
     * 단, 현재 구조에서 DB stock은 PAID 시에만 차감하므로
     * FAILED 시엔 DB stock 변경 불필요 — Redis만 복구.
     */
    @Modifying
    @Query("UPDATE Product p SET p.stock = p.stock + 1 WHERE p.id = :id")
    int incrementStock(@Param("id") Long productId);

    /** 테스트용 전체 재고 초기화 */
    @Modifying
    @Query("UPDATE Product p SET p.stock = :stock WHERE p.id = :id")
    int resetStock(@Param("id") Long productId, @Param("stock") int stock);
}
