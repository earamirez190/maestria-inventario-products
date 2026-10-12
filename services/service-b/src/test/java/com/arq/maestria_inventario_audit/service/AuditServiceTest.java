package com.arq.maestria_inventario_audit.service;

import com.arq.maestria_inventario_audit.domain.ProductAuditRepository;
import com.arq.maestria_inventario_audit.web.ProductAuditRequest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AuditServiceTest {

    @Mock
    private ProductAuditRepository repository;

    @InjectMocks
    private AuditService auditService;

    @Test
    void shouldPersistProductSavedEvent() {
        ProductAuditRequest request = new ProductAuditRequest("product-1", "Mouse", 4, 25.0);
        when(repository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        var savedEvent = auditService.recordProductSaved(request);

        assertEquals("product-1", savedEvent.getProductId());
        assertEquals("PRODUCT_SAVED", savedEvent.getEventType());
        verify(repository).save(any());
    }
}
