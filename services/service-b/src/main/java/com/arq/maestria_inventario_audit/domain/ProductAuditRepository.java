package com.arq.maestria_inventario_audit.domain;

import org.springframework.data.jpa.repository.JpaRepository;

public interface ProductAuditRepository extends JpaRepository<ProductAuditEvent, String> {
}
