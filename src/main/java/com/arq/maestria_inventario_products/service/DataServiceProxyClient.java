package com.arq.maestria_inventario_products.service;

import com.fasterxml.jackson.databind.JsonNode;
import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
public class DataServiceProxyClient {

    private final RestClient restClient;
    private final String proxyUrl;

    public DataServiceProxyClient(
            RestClient.Builder restClientBuilder,
            @Value("${data-service.proxy-url:http://localhost:9091}") String proxyUrl) {
        this.restClient = restClientBuilder.build();
        this.proxyUrl = proxyUrl;
    }

    @WithSpan("products.data-service")
    public JsonNode getProducts(String category) {
        return restClient.get()
                .uri(uriBuilder -> uriBuilder
                        .path(proxyUrl + "/api/data/products")
                        .queryParam("category", category == null || category.isBlank() ? "all" : category)
                        .build())
                .retrieve()
                .body(JsonNode.class);
    }
}
