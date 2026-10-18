package com.arq.maestria_inventario_products.service;

import com.arq.maestria_inventario_products.domain.model.Product;
import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.http.client.SimpleClientHttpRequestFactory;

@Component
@Profile("!data-service")
public class ProductDataServiceClient {

    private static final Logger log = LoggerFactory.getLogger(ProductDataServiceClient.class);

    private final RestClient restClient;
    private final String dataServiceUrl;
    private final boolean enabled;

    public ProductDataServiceClient(
            RestClient.Builder restClientBuilder,
            @Value("${data-service.url:http://localhost:9095}") String dataServiceUrl,
            @Value("${data-service.enabled:false}") boolean enabled,
            @Value("${data-service.connect-timeout-ms:500}") int connectTimeoutMs,
            @Value("${data-service.read-timeout-ms:1000}") int readTimeoutMs) {
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(connectTimeoutMs);
        requestFactory.setReadTimeout(readTimeoutMs);
        this.restClient = restClientBuilder.requestFactory(requestFactory).build();
        this.dataServiceUrl = dataServiceUrl;
        this.enabled = enabled;
    }

    @WithSpan("products.data-service.analytics")
    public void analyzeProduct(Product product) {
        if (!enabled) {
            return;
        }

        try {
            restClient.get()
                    .uri(dataServiceUrl + "/data/analytics/{productId}", product.getId())
                    .retrieve()
                    .toBodilessEntity();
            log.info("Product analytics requested: productId={}", product.getId());
        } catch (RestClientException exception) {
            log.warn("Data service unavailable: productId={}, reason={}",
                    product.getId(), exception.getMessage());
        }
    }
}
