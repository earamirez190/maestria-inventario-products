package com.arq.maestria_inventario_products.application.service;

import com.arq.maestria_inventario_products.domain.model.Product;
import com.arq.maestria_inventario_products.domain.repository.ProductRepository;
import com.arq.maestria_inventario_products.service.ProductService;
import com.arq.maestria_inventario_products.service.ProductAuditClient;
import com.arq.maestria_inventario_products.service.ProductDataServiceClient;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class ProductServiceTest {

    private ProductRepository productRepository;
    private ProductAuditClient productAuditClient;
    private ProductDataServiceClient productDataServiceClient;
    private ProductService productService;

    @BeforeEach
    void setUp() {
        productRepository = Mockito.mock(ProductRepository.class);
        productAuditClient = Mockito.mock(ProductAuditClient.class);
        productDataServiceClient = Mockito.mock(ProductDataServiceClient.class);
        productService = new ProductService(productRepository, productAuditClient, productDataServiceClient);
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

    @Test
    void shouldRequestAnalyticsWithoutChangingSavedProductResponse() {
        Product savedProduct = new Product();
        savedProduct.setId("product-123");
        savedProduct.setName("Mouse");
        savedProduct.setQuantity(5);
        savedProduct.setPrice(20.5);
        when(productRepository.save(savedProduct)).thenReturn(savedProduct);

        Product response = productService.saveProduct(savedProduct, null);

        assertSame(savedProduct, response);
        verify(productDataServiceClient).analyzeProduct(savedProduct);
    }
}
