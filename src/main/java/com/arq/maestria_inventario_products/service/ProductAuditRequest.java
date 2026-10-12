package com.arq.maestria_inventario_products.service;

public record ProductAuditRequest(String productId, String productName, int quantity, double price) {
}
