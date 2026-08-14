package com.arq.maestria_inventario_products.application.service;

import com.arq.maestria_inventario_products.domain.model.Product;
import com.arq.maestria_inventario_products.domain.repository.ProductRepository;
import com.arq.maestria_inventario_products.service.ProductService;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertEquals;

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
        Product invalidProduct = new Product();
        invalidProduct.setName("Invalido");
        invalidProduct.setQuantity(10);
        invalidProduct.setPrice(-5.0);

        IllegalArgumentException exception = assertThrows(
            IllegalArgumentException.class,
            () -> productService.saveProduct(invalidProduct, null)
        );

        assertEquals("El precio y la cantidad deben ser positivos.", exception.getMessage());
    }
}
