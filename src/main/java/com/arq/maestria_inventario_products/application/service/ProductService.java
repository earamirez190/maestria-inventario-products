package com.arq.maestria_inventario_products.application.service;


import com.arq.maestria_inventario_products.domain.model.Product;
import com.arq.maestria_inventario_products.domain.repository.ProductRepository;
import com.arq.maestria_inventario_products.domain.strategy.DiscountStrategy;
import com.arq.maestria_inventario_products.domain.strategy.NoDiscountStrategy;
import com.arq.maestria_inventario_products.domain.strategy.WholesaleDiscountStrategy;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;

@Service
public class ProductService {
    private final ProductRepository productRepository;

    public ProductService(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }

    public Product createProduct(Product product) {
        if (product.getPrice() < 0 || product.getQuantity() < 0) {
            throw new IllegalArgumentException("El precio y la cantidad deben ser positivos.");
        }

        DiscountStrategy strategy;
        if (product.getQuantity() >= 100) {
            strategy = new WholesaleDiscountStrategy();
        } else {
            strategy = new NoDiscountStrategy();
        }

        strategy.applyDiscount(product);
        return productRepository.save(product);
    }

    public List<Product> getAllProducts() {
        return productRepository.findAll();
    }

    public Optional<Product> getProductById(String id) {
        return productRepository.findById(id);
    }

}
