package com.arq.maestria_inventario_products.infrastructure.web;

import com.arq.maestria_inventario_products.domain.model.Product;
import com.arq.maestria_inventario_products.domain.repository.ProductRepository;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class DataServiceControllerTest {

    private final ProductRepository productRepository = mock(ProductRepository.class);
    private final DataServiceController controller = new DataServiceController(productRepository);

    @Test
    void shouldReturnAnalyticsForProduct() {
        Product product = new Product("Mouse", 5, 20.5);
        product.setId("product-123");
        when(productRepository.findById("product-123")).thenReturn(Optional.of(product));

        DataServiceController.ProductAnalyticsResponse response =
                controller.getProductAnalytics("product-123");

        assertEquals("SELECT", response.operation());
        assertEquals("product", response.table());
        assertEquals("product-123", response.productId());
        assertEquals("analytics", response.queryType());
        assertEquals("Mouse", response.name());
        assertEquals(5, response.quantity());
        assertEquals(20.5, response.price());
        verify(productRepository).findById("product-123");
    }

    @Test
    void shouldReturnNotFoundWhenProductDoesNotExist() {
        when(productRepository.findById("missing")).thenReturn(Optional.empty());

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.getProductAnalytics("missing"));

        assertEquals(404, exception.getStatusCode().value());
    }
}
