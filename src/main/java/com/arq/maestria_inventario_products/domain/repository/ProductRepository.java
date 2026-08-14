package com.arq.maestria_inventario_products.domain.repository;

import com.arq.maestria_inventario_products.domain.model.Product;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProductRepository extends JpaRepository<Product, String> {
}
