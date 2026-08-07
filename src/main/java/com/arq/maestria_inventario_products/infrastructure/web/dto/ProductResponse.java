package com.arq.maestria_inventario_products.infrastructure.web.dto;

public class ProductResponse {
    private String id;
    private String name;
    private int quantity;
    private double price;

    public ProductResponse(String id, String name, int quantity, double price) {
        this.id = id;
        this.name = name;
        this.quantity = quantity;
        this.price = price;
    }

    public String getId() {
        return id;
    }
    public String getName() {
        return name;
    }
    public int getQuantity() {
        return quantity;
    }
    public double getPrice() {
        return price;
    }
}
