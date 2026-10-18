package com.arq.maestria_inventario_audit.service;

import com.arq.maestria_inventario_audit.domain.ProductAuditEvent;
import com.arq.maestria_inventario_audit.domain.ProductAuditRepository;
import com.arq.maestria_inventario_audit.web.ProductAuditRequest;
import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

@Service
public class AuditService {

    private static final Logger log = LoggerFactory.getLogger(AuditService.class);

    private final ProductAuditRepository repository;

    public AuditService(ProductAuditRepository repository) {
        this.repository = repository;
    }

    @WithSpan("audit.persist")
    public ProductAuditEvent recordProductSaved(ProductAuditRequest request) {
        ProductAuditEvent event = new ProductAuditEvent(
                request.productId(), request.productName(), request.quantity(), request.price());
        ProductAuditEvent savedEvent = repository.save(event);
        log.info("Product audit persisted: eventId={}, productId={}, eventType={}",
                savedEvent.getId(), savedEvent.getProductId(), savedEvent.getEventType());
        return savedEvent;
    }

    public long countEvents() {
        return repository.count();
    }
}
