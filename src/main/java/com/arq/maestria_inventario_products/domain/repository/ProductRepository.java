package com.arq.maestria_inventario_products.domain.repository;


import com.arq.maestria_inventario_products.domain.model.Product;

import java.util.List;
import java.util.Optional;

public interface ProductRepository {
    Product save(Product product);
    Optional<Product> findById(String id);
    List<Product> findAll();
    void delete(String id);
}