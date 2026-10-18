package com.arq.maestria_inventario_audit.web;

import com.arq.maestria_inventario_audit.domain.ProductAuditEvent;
import com.arq.maestria_inventario_audit.service.AuditService;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/audits")
public class ProductAuditController {

    private final AuditService auditService;

    public ProductAuditController(AuditService auditService) {
        this.auditService = auditService;
    }

    @PostMapping("/products")
    @ResponseStatus(HttpStatus.CREATED)
    public ProductAuditEvent recordProductSaved(@RequestBody ProductAuditRequest request) {
        return auditService.recordProductSaved(request);
    }

    @GetMapping("/products/count")
    public long countEvents() {
        return auditService.countEvents();
    }
}
