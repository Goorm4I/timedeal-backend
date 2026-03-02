package com.timedeal.product;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDateTime;

@Entity
@Table(name = "products")
@Getter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Product {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String name;
    private Integer price;
    private Integer initialStock;  // 초기 재고 (변경 불가, Redis 재건 기준)
    private Integer stock;         // 현재 DB 재고 (결제 성공 시 -1)

    @UpdateTimestamp
    private LocalDateTime updatedAt;
}
