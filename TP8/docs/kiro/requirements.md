# Requisitos del Sistema - Tablet Offline y Sincronización (TP8)

## 1. Contexto y Notación
Este documento especifica los requisitos funcionales y de consistencia para la base de datos local SQLite de las tablets comerciales y su posterior sincronización con la base central PostgreSQL.

Los requisitos están formulados utilizando la sintaxis **EARS** (*Easy Approach to Requirements Syntax*), estructurados en torno a las condiciones de disparo y los comportamientos observables del sistema.

---

## 2. Requisitos Funcionales y de Sincronización (EARS)

### REQ-01: Aprobación de pedido sin discrepancias
- **Sintaxis EARS**:
  `WHEN el vendedor simula o sincroniza un pedido borrador cuyos productos cuentan con stock disponible suficiente y sus precios coinciden exactamente con la instantánea central THE SYSTEM SHALL clasificar la simulación como 'SIMULADO_APROBADO' y permitir la inserción definitiva en PostgreSQL sin modificaciones.`
- **Caso de prueba asociado**:
  Se prueba con: C1
- **Evidencia**: `evidencias/caso_c1.txt`
- **Criterio de aceptación**: El pedido pasa directamente a estado aprobado y se descuenta stock en PostgreSQL de forma atómica.

---

### REQ-02: Rechazo por stock central insuficiente
- **Sintaxis EARS**:
  `WHEN el vendedor sincroniza un pedido offline donde al menos un ítem supera el stock disponible en el servidor central al momento de la transacción THE SYSTEM SHALL rechazar la operación en PostgreSQL con estado 'RECHAZADO', registrar el motivo 'Stock insuficiente' y no alterar el stock remanente.`
- **Caso de prueba asociado**:
  Se prueba con: C2
- **Evidencia**: `evidencias/caso_c2.txt`
- **Criterio de aceptación**: Rollback de la reserva o inserción con estado rechazado; ninguna línea descuenta inventario si la orden no puede satisfacerse íntegramente.

---

### REQ-03: Detección de conflicto por aumento de precio central
- **Sintaxis EARS**:
  `WHEN el vendedor evalúa un pedido offline cuyos ítems tienen un precio unitario en el servidor mayor al registrado en la instantánea de la tablet THE SYSTEM SHALL clasificar la simulación como 'CONFLICTO' y requerir confirmación explícita del cliente antes de consolidar la venta.`
- **Caso de prueba asociado**:
  Se prueba con: C3
- **Evidencia**: `evidencias/caso_c3.txt`
- **Criterio de aceptación**: El semáforo local emite advertencia amarilla y no permite sincronización ciega sin aceptación expresa del nuevo total.

---

### REQ-04: Rechazo por producto inactivo o discontinuado
- **Sintaxis EARS**:
  `WHEN el vendedor sincroniza un pedido que incluye un ítem marcado como discontinuado o inactivo en el catálogo maestro del servidor THE SYSTEM SHALL rechazar el pedido en el servidor con estado 'RECHAZADO' y motivo 'Producto discontinuado'.`
- **Caso de prueba asociado**:
  Se prueba con: C4
- **Evidencia**: `evidencias/caso_c4.txt`
- **Criterio de aceptación**: Ningún producto inactivo puede generar órdenes de venta aprobadas en la base central.

---

### REQ-05: Ajuste automático por reducción de precio en servidor
- **Sintaxis EARS**:
  `WHEN el vendedor sincroniza un pedido donde el precio vigente en el servidor es menor al capturado en la tablet offline THE SYSTEM SHALL aplicar automáticamente el precio más bajo en beneficio del cliente, clasificar la simulación como 'SIMULADO_APROBADO' y registrar la venta con el importe menor.`
- **Caso de prueba asociado**:
  Se prueba con: C5
- **Evidencia**: `evidencias/caso_c5.txt`
- **Criterio de aceptación**: Beneficio comercial automático; la factura final en el servidor adopta el precio rebajado sin bloquear el flujo de despacho.

---

### REQ-06: Validación de pedido vacío o sin líneas de detalle
- **Sintaxis EARS**:
  `WHEN el operador ejecuta la evaluación del semáforo sobre un pedido que no contiene ningún ítem asociado THE SYSTEM SHALL rechazar la evaluación emitiendo estado 'RECHAZADO' con el motivo 'Pedido sin ítems'.`
- **Caso de prueba asociado**:
  Se prueba con: C6
- **Evidencia**: `evidencias/caso_c6.txt`
- **Criterio de aceptación**: Evita la transmisión de cabeceras huérfanas sin líneas de venta.

---

### REQ-07: Priorización determinista ante múltiples conflictos
- **Sintaxis EARS**:
  `WHEN un pedido offline presenta simultáneamente ítems con stock agotado e ítems con variaciones de precio THE SYSTEM SHALL priorizar la condición restrictiva clasificando el pedido como 'RECHAZADO' por sobre el estado de 'CONFLICTO'.`
- **Caso de prueba asociado**:
  Se prueba con: C7
- **Evidencia**: `evidencias/caso_c7.txt`
- **Criterio de aceptación**: La falta de stock invalida la orden inmediatamente; las discrepancias de precio quedan en segundo orden sin generar falsas expectativas al cliente.
