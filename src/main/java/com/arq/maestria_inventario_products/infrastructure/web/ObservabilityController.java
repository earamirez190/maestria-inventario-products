package com.arq.maestria_inventario_products.infrastructure.web;

import com.arq.maestria_inventario_products.service.DataServiceProxyClient;
import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/observability")
public class ObservabilityController {

    private final DataServiceProxyClient dataServiceClient;

    public ObservabilityController(DataServiceProxyClient dataServiceClient) {
        this.dataServiceClient = dataServiceClient;
    }

    @GetMapping("/data/products")
    public JsonNode getProducts(@RequestParam(defaultValue = "all") String category) {
        return dataServiceClient.getProducts(category);
    }
}
