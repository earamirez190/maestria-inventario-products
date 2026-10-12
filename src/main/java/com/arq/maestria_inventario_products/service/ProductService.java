package com.arq.maestria_inventario_products.service;

import com.arq.maestria_inventario_products.domain.model.Product;
import com.arq.maestria_inventario_products.domain.repository.ProductRepository;
import com.arq.maestria_inventario_products.domain.strategy.DiscountStrategy;
import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class ProductService {

    private static final Logger log = LoggerFactory.getLogger(ProductService.class);

    private final ProductRepository repository;
    private final ProductAuditClient auditClient;

    public ProductService(ProductRepository repository, ProductAuditClient auditClient) {
        this.repository = repository;
        this.auditClient = auditClient;
    }

    @WithSpan("products.save")
    public Product saveProduct(Product product, DiscountStrategy strategy) {
        if (product.getPrice() <= 0 || product.getQuantity() <= 0) {
            throw new IllegalArgumentException("El precio y la cantidad deben ser positivos.");
        }

        if (strategy != null) {
            strategy.applyDiscount(product);
        }

        Product savedProduct = repository.save(product);
        log.info("Product saved: id={}, name={}, quantity={}",
                savedProduct.getId(), savedProduct.getName(), savedProduct.getQuantity());
        auditClient.auditProductSaved(savedProduct);
        return savedProduct;
    }

    @WithSpan("products.list")
    public List<Product> getAllProducts() {
        List<Product> products = repository.findAll();
        log.info("Products listed: count={}", products.size());
        return products;
    }
}
