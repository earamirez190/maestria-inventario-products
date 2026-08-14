package com.arq.maestria_inventario_products.infrastructure.web;

import com.arq.maestria_inventario_products.domain.model.Product;
import com.arq.maestria_inventario_products.domain.strategy.DiscountStrategy;
import com.arq.maestria_inventario_products.domain.strategy.NoDiscountStrategy;
import com.arq.maestria_inventario_products.domain.strategy.PercentageDiscountStrategy;
import com.arq.maestria_inventario_products.domain.strategy.WholesaleDiscountStrategy;
import com.arq.maestria_inventario_products.service.ProductService;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/products")
public class ProductController {

    private final ProductService productService;

    public ProductController(ProductService productService) {
        this.productService = productService;
    }

    @GetMapping
    public List<Product> getAllProducts() {
        return productService.getAllProducts();
    }
    
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Product saveProduct(
            @RequestBody Product product,
            @RequestParam(name = "discountPercentage", required = false) Double discountPercentage,
            @RequestParam(name = "wholesale", required = false, defaultValue = "false") boolean wholesale) {
        
        DiscountStrategy strategy = new NoDiscountStrategy();

        if (wholesale || product.getQuantity() >= 100) {
            strategy = new WholesaleDiscountStrategy();
        } else if (discountPercentage != null && discountPercentage > 0) {
            strategy = new PercentageDiscountStrategy(discountPercentage);
        }

        return productService.saveProduct(product, strategy);
    }
}
