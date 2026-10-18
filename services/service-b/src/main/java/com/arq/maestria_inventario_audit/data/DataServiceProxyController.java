package com.arq.maestria_inventario_audit.data;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/data")
public class DataServiceProxyController {

    private final DataServiceClient client;

    public DataServiceProxyController(DataServiceClient client) {
        this.client = client;
    }

    @GetMapping("/products")
    public JsonNode getProducts(@RequestParam(defaultValue = "all") String category) {
        return client.getProducts(category);
    }
}
