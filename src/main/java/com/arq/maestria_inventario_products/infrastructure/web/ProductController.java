package com.arq.maestria_inventario_products.infrastructure.web;


import com.arq.maestria_inventario_products.application.service.ProductService;
import com.arq.maestria_inventario_products.domain.model.Product;
import com.arq.maestria_inventario_products.infrastructure.web.dto.ProductRequest;
import com.arq.maestria_inventario_products.infrastructure.web.dto.ProductResponse;
import com.arq.maestria_inventario_products.infrastructure.web.mapper.ProductMapper;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/products")
public class ProductController {

    private final ProductService productService;

    public ProductController(ProductService productService) {
        this.productService = productService;
    }

    @PostMapping
    public ResponseEntity<ProductResponse> createProduct(@RequestBody ProductRequest request) {
        try {
            Product productDomain = ProductMapper.toDomain(request);

            Product createdProduct = productService.createProduct(productDomain);

            ProductResponse response = ProductMapper.toResponse(createdProduct);

            return new ResponseEntity<>(response, HttpStatus.CREATED);
        } catch (IllegalArgumentException e) {
            // Manejo básico de errores si la regla de negocio falla
            return ResponseEntity.badRequest().build();
        }
    }

    @GetMapping
    public ResponseEntity<List<ProductResponse>> getAllProducts() {
        List<ProductResponse> responses = productService.getAllProducts().stream()
                .map(ProductMapper::toResponse)
                .collect(Collectors.toList());
        return ResponseEntity.ok(responses);
    }

    @GetMapping("/{id}")
    public ResponseEntity<ProductResponse> getProductById(@PathVariable String id) {
        return productService.getProductById(id)
                .map(ProductMapper::toResponse)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }
}
