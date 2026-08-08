package com.arq.maestria_inventario_products.domain.strategy;

import com.arq.maestria_inventario_products.domain.model.Product;


public class PercentageDiscountStrategy implements DiscountStrategy {

    private final double percentage;

    public PercentageDiscountStrategy(double percentage) {
        this.percentage = percentage;
    }

    @Override
    public void applyDiscount(Product product) {
        double discount = product.getPrice() * (percentage / 100);
        product.setPrice(product.getPrice() - discount);
    }
}
 