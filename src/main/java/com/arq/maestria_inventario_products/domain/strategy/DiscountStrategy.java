package com.arq.maestria_inventario_products.domain.strategy;

import com.arq.maestria_inventario_products.domain.model.Product;

public interface DiscountStrategy {
    void applyDiscount(Product product);
}