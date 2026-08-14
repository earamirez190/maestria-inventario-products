package com.arq.maestria_inventario_products.service;

import com.arq.maestria_inventario_products.domain.model.Product;
import com.arq.maestria_inventario_products.domain.repository.ProductRepository;
import com.arq.maestria_inventario_products.domain.strategy.DiscountStrategy;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class ProductService {

    private final ProductRepository repository;


    public ProductService(ProductRepository repository) {
        this.repository = repository;
    }

    public Product saveProduct(Product product, DiscountStrategy strategy) {
        if (product.getPrice() <= 0 || product.getQuantity() <= 0) {
            throw new IllegalArgumentException("El precio y la cantidad deben ser positivos.");
        }

        if (strategy != null) {
            strategy.applyDiscount(product);
        }

        return repository.save(product);
    }

    public List<Product> getAllProducts() {
        return repository.findAll();
    }
}
