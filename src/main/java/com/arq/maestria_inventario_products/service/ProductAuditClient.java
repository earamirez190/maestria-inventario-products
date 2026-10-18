package com.arq.maestria_inventario_products.service;

import com.arq.maestria_inventario_products.domain.model.Product;
import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.springframework.context.annotation.Profile;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

@Component
@Profile("!data-service")
public class ProductAuditClient {

    private static final Logger log = LoggerFactory.getLogger(ProductAuditClient.class);

    private final RestClient restClient;
    private final String auditServiceUrl;
    private final boolean enabled;

    public ProductAuditClient(
            RestClient.Builder restClientBuilder,
            @Value("${product-audit.url:http://localhost:9091}") String auditServiceUrl,
            @Value("${product-audit.enabled:false}") boolean enabled) {
        this.restClient = restClientBuilder.build();
        this.auditServiceUrl = auditServiceUrl;
        this.enabled = enabled;
    }

    @WithSpan("products.audit")
    public void auditProductSaved(Product product) {
        if (!enabled) {
            return;
        }

        ProductAuditRequest request = new ProductAuditRequest(
                product.getId(), product.getName(), product.getQuantity(), product.getPrice());

        try {
            restClient.post()
                    .uri(auditServiceUrl + "/api/audits/products")
                    .body(request)
                    .retrieve()
                    .toBodilessEntity();
            log.info("Product audit sent: productId={}", product.getId());
        } catch (RestClientException exception) {
            log.warn("Product audit service unavailable: productId={}, reason={}",
                    product.getId(), exception.getMessage());
        }
    }
}
