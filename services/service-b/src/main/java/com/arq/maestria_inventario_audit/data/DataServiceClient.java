package com.arq.maestria_inventario_audit.data;

import com.fasterxml.jackson.databind.JsonNode;
import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
public class DataServiceClient {

    private final RestClient restClient;
    private final String dataServiceUrl;
    private final long chaosLatencyMs;

    public DataServiceClient(
            RestClient.Builder restClientBuilder,
            @Value("${data-service.url:http://localhost:8002}") String dataServiceUrl,
            @Value("${chaos.latency-ms:0}") long chaosLatencyMs) {
        this.restClient = restClientBuilder.build();
        this.dataServiceUrl = dataServiceUrl;
        this.chaosLatencyMs = chaosLatencyMs;
    }

    @WithSpan("data-service.products")
    public JsonNode getProducts(String category) {
        if (chaosLatencyMs > 0) {
            try {
                Thread.sleep(chaosLatencyMs);
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException("Chaos latency experiment interrupted", interrupted);
            }
        }
        return restClient.get()
                .uri(uriBuilder -> uriBuilder
                        .path(dataServiceUrl + "/data/products")
                        .queryParam("category", category == null || category.isBlank() ? "all" : category)
                        .build())
                .retrieve()
                .body(JsonNode.class);
    }
}
