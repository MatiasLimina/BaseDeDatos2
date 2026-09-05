-- ---------------------------------------------------------------------
-- Vista 1: vw_productos_vigentes
-- Requisito 1 — Productos activos con nombre de categoría
--
-- Propósito: Expone el catálogo operativo filtrando baja lógica en
--   producto (activo = TRUE) y en categoría (categoria.activo = TRUE).
--   El filtro está embebido en la vista para que sea invariante
--   independientemente de cómo se consulte.
-- Columnas expuestas: id, nombre, precio, stock,
--   nombre_categoria (JOIN con categoria), created_at
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_productos_vigentes AS
SELECT
    p.id,
    p.nombre,
    p.precio,
    p.stock,
    c.nombre   AS nombre_categoria,
    p.created_at
FROM producto p
JOIN categoria c ON p.categoria_id = c.id
WHERE p.activo      = TRUE
  AND c.activo      = TRUE;


-- ---------------------------------------------------------------------
-- Vista 2: vw_pedidos_cliente
-- Requisito 2 — Pedidos con datos identificativos del cliente
--
-- Criterio de seguridad aplicado:
--   Se omiten intencionalmente las siguientes columnas de la tabla
--   cliente para que roles con SELECT sobre esta vista no puedan
--   acceder a datos de contacto personales:
--     - cliente.email      (dato personal de contacto)
--     - cliente.telefono   (dato personal de contacto)
--     - cliente.created_at (metadato interno)
--   Si en el futuro se agrega una columna cliente.contrasena (u otra
--   columna de autenticación), NO debe incluirse aquí.
--
-- Columnas expuestas: pedido_id, fecha, forma_pago,
--   cliente_id, nombre, apellido, activo
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_pedidos_cliente AS
SELECT
    p.id            AS pedido_id,
    p.fecha,
    p.forma_pago,
    c.id            AS cliente_id,
    c.nombre,
    c.apellido,
    c.activo
  -- Excluidos deliberadamente por criterio de seguridad:
  --   - c.email: dato de contacto personal sensible.
  --   - c.telefono: dato de contacto personal sensible.
  --   - c.created_at: metadato de auditoría interno.
  --   Si a futuro se agrega una columna de autenticación (ej. contrasena VARCHAR),
  --   permanecerá excluida sin requerir ajuste de permisos sobre la vista.
  -- Motivo de seguridad: otorgar SELECT sobre esta vista a roles con permisos
  -- restringidos sin exponer información de contacto ni autenticación del cliente.
FROM pedido p
JOIN cliente c ON p.cliente_id = c.id;


-- ---------------------------------------------------------------------
-- Vista 3: vw_detalle_pedido
-- Requisito 3 — Detalle de pedido con nombre legible del producto
--
-- Propósito: Encapsula el JOIN entre pedido_detalle y producto para
--   que los consumidores (aplicación, generador de comprobantes) puedan
--   filtrar por pedido_id sin conocer claves foráneas ni hacer JOINs.
-- Columnas expuestas: pedido_id, nombre_producto, cantidad,
--   precio_unitario, subtotal
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_detalle_pedido AS
SELECT
    pd.pedido_id,
    pr.nombre       AS nombre_producto,
    pd.cantidad,
    pd.precio_unitario,
    pd.subtotal
FROM pedido_detalle pd
JOIN producto pr ON pd.producto_id = pr.id;


-- =====================================================================
-- Verificación de equivalencia (Requisito 4)
--
-- Para cada vista se ejecutan dos consultas EXCEPT simétricas.
-- Si ambas retornan 0 filas la vista es equivalente a su consulta
-- manual. Ejecutar estos bloques después de crear las vistas y de
-- tener datos cargados (seed.sql).
-- =====================================================================

-- ----------------------------
-- Equivalencia Vista 1
-- ----------------------------

-- Dirección 1 → 2: filas en la vista que no están en la consulta manual
(
    SELECT id, nombre, precio, stock, nombre_categoria, created_at
    FROM vw_productos_vigentes
)
EXCEPT
(
    SELECT p.id, p.nombre, p.precio, p.stock, c.nombre, p.created_at
    FROM producto p
    JOIN categoria c ON p.categoria_id = c.id
    WHERE p.activo = TRUE AND c.activo = TRUE
);
-- Resultado esperado: 0 filas

-- Dirección 2 → 1: filas en la consulta manual que no están en la vista
(
    SELECT p.id, p.nombre, p.precio, p.stock, c.nombre, p.created_at
    FROM producto p
    JOIN categoria c ON p.categoria_id = c.id
    WHERE p.activo = TRUE AND c.activo = TRUE
)
EXCEPT
(
    SELECT id, nombre, precio, stock, nombre_categoria, created_at
    FROM vw_productos_vigentes
);
-- Resultado esperado: 0 filas


-- ----------------------------
-- Equivalencia Vista 2
-- ----------------------------

-- Dirección 1 → 2
(
    SELECT pedido_id, fecha, forma_pago, cliente_id, nombre, apellido, activo
    FROM vw_pedidos_cliente
)
EXCEPT
(
    SELECT p.id, p.fecha, p.forma_pago, c.id, c.nombre, c.apellido, c.activo
    FROM pedido p
    JOIN cliente c ON p.cliente_id = c.id
);
-- Resultado esperado: 0 filas

-- Dirección 2 → 1
(
    SELECT p.id, p.fecha, p.forma_pago, c.id, c.nombre, c.apellido, c.activo
    FROM pedido p
    JOIN cliente c ON p.cliente_id = c.id
)
EXCEPT
(
    SELECT pedido_id, fecha, forma_pago, cliente_id, nombre, apellido, activo
    FROM vw_pedidos_cliente
);
-- Resultado esperado: 0 filas


-- ----------------------------
-- Equivalencia Vista 3
-- ----------------------------

-- Dirección 1 → 2
(
    SELECT pedido_id, nombre_producto, cantidad, precio_unitario, subtotal
    FROM vw_detalle_pedido
)
EXCEPT
(
    SELECT pd.pedido_id, pr.nombre, pd.cantidad, pd.precio_unitario, pd.subtotal
    FROM pedido_detalle pd
    JOIN producto pr ON pd.producto_id = pr.id
);
-- Resultado esperado: 0 filas

-- Dirección 2 → 1
(
    SELECT pd.pedido_id, pr.nombre, pd.cantidad, pd.precio_unitario, pd.subtotal
    FROM pedido_detalle pd
    JOIN producto pr ON pd.producto_id = pr.id
)
EXCEPT
(
    SELECT pedido_id, nombre_producto, cantidad, precio_unitario, subtotal
    FROM vw_detalle_pedido
);
-- Resultado esperado: 0 filas
