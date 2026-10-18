package com.arq.maestria_inventario_products.infrastructure.web;

import com.arq.maestria_inventario_products.domain.model.Product;
import com.arq.maestria_inventario_products.domain.repository.ProductRepository;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/data")
@Profile("data-service")
public class DataServiceController {

    private final ProductRepository productRepository;

    public DataServiceController(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }

    @GetMapping("/analytics/{productId}")
    @WithSpan("data-service.product.analytics")
    public ProductAnalyticsResponse getProductAnalytics(@PathVariable String productId) {
        Span.current()
                .setAttribute("db.operation", "SELECT")
                .setAttribute("db.sql.table", "product")
                .setAttribute("product.id", productId)
                .setAttribute("query.type", "analytics");

        Product product = productRepository.findById(productId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Product not found"));

        return new ProductAnalyticsResponse(
                "SELECT", "product", product.getId(), "analytics",
                product.getName(), product.getQuantity(), product.getPrice());
    }

    public record ProductAnalyticsResponse(
            String operation,
            String table,
            String productId,
            String queryType,
            String name,
            int quantity,
            double price) {
    }
}
