package com.arq.maestria_inventario_products.application.service;

import com.arq.maestria_inventario_products.domain.model.Product;
import com.arq.maestria_inventario_products.domain.model.ProductBuilder;
import com.arq.maestria_inventario_products.domain.repository.ProductRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;

class ProductServiceTest {

    private ProductRepository productRepository;
    private ProductService productService;

    @BeforeEach
    void setUp() {

        productRepository = Mockito.mock(ProductRepository.class);
        productService = new ProductService(productRepository);
    }

    @Test
    void shouldThrowException_WhenPriceIsNegative() {
        // Creamos un producto inválido usando el Builder
        Product invalidProduct = new ProductBuilder()
                .name("Invalido")
                .quantity(10)
                .price(-5.0)
                .build();

        IllegalArgumentException exception = assertThrows(IllegalArgumentException.class, () -> {
            productService.createProduct(invalidProduct);
        });

        assertEquals("El precio y la cantidad deben ser positivos.", exception.getMessage());
    }
}