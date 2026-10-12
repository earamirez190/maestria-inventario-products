package com.arq.maestria_inventario_audit.web;

public record ProductAuditRequest(String productId, String productName, int quantity, double price) {
}
