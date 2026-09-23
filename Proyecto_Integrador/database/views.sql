-- =====================================================================
-- Base de Datos II — Trabajo Práctico Unidad 3 (Food Store)
-- Archivo: views.sql
-- Integrantes: Matías Limina, Nicolás Monjelardi, Lautaro Agüero
-- Motor: PostgreSQL 16+
-- Repositorio: https://github.com/MatiasLimina/BaseDeDatos2.git
-- =====================================================================

-- ---------------------------------------------------------------------
-- Vista 1: vw_productos_vigentes
-- Requisito 1 — Productos activos con nombre de categoría
--
-- Propósito: Expone el catálogo operativo filtrando baja lógica en
--   producto (activo = TRUE) y en categoría (categoria.activo = TRUE).
--   El filtro está embebido en la vista para garantizar consistencia.
-- Columnas: id, nombre, precio, stock, nombre_categoria, created_at
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
WHERE p.activo = TRUE
  AND c.activo = TRUE;


-- ---------------------------------------------------------------------
-- Vista 2: vw_pedidos_cliente
-- Requisito 2 y 4 — Pedidos con datos identificativos y criterio de seguridad
--
-- Criterio de seguridad aplicado (Principio de menor privilegio):
--   Se omiten deliberadamente las columnas de contacto y auditoría personal:
--     - cliente.email      (dato personal de contacto)
--     - cliente.telefono   (dato personal de contacto)
--     - cliente.created_at (metadato interno)
--   Permite otorgar SELECT a roles operativos o de auditoría sin exponer
--   información privada ni claves/credenciales del cliente.
-- Columnas: pedido_id, fecha, forma_pago, cliente_id, nombre, apellido, activo
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
FROM pedido p
JOIN cliente c ON p.cliente_id = c.id;


-- ---------------------------------------------------------------------
-- Vista 3: vw_detalle_pedido
-- Requisito 3 — Detalle de pedido con nombre legible del producto
--
-- Propósito: Encapsula el JOIN entre pedido_detalle y producto para
--   abstraer la clave foránea y exponer directamente el nombre legible.
-- Columnas: pedido_id, nombre_producto, cantidad, precio_unitario, subtotal
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
-- Verificación de equivalencia (Requisito 4.2.3)
--
-- NOTA METODOLÓGICA IMPORTANTE:
-- El operador EXCEPT de SQL aplica semántica de conjuntos (DISTINCT implícito),
-- eliminando tuplas duplicadas. Por lo tanto, (A EXCEPT B) = 0 y (B EXCEPT A) = 0
-- NO garantizan equivalencia si existen tuplas duplicadas con distinta multiplicidad.
-- Para garantizar equivalencia multiconjunto rigurosa (bag semantics), se complementa
-- la verificación simétrica de EXCEPT con la comparación estricta de COUNT(*).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Equivalencia Vista 1: vw_productos_vigentes
-- ---------------------------------------------------------------------

-- 1. Diferencia simétrica (debe retornar 0 filas en ambas direcciones)
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

-- 2. Validación de cardinalidad estricta (COUNT)
SELECT 
    (SELECT COUNT(*) FROM vw_productos_vigentes) AS count_vista_1,
    (SELECT COUNT(*) FROM producto p JOIN categoria c ON p.categoria_id = c.id WHERE p.activo = TRUE AND c.activo = TRUE) AS count_manual_1,
    CASE 
        WHEN (SELECT COUNT(*) FROM vw_productos_vigentes) = 
             (SELECT COUNT(*) FROM producto p JOIN categoria c ON p.categoria_id = c.id WHERE p.activo = TRUE AND c.activo = TRUE)
        THEN 'EQUIVALENCIA COMPLETA (0 filas EXCEPT y COUNT idéntico)'
        ELSE 'ERROR: DISCREPANCIA EN DUPLICADOS'
    END AS resultado_validacion_v1;


-- ---------------------------------------------------------------------
-- Equivalencia Vista 2: vw_pedidos_cliente
-- ---------------------------------------------------------------------

-- 1. Diferencia simétrica
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

-- 2. Validación de cardinalidad estricta (COUNT)
SELECT 
    (SELECT COUNT(*) FROM vw_pedidos_cliente) AS count_vista_2,
    (SELECT COUNT(*) FROM pedido p JOIN cliente c ON p.cliente_id = c.id) AS count_manual_2,
    CASE 
        WHEN (SELECT COUNT(*) FROM vw_pedidos_cliente) = 
             (SELECT COUNT(*) FROM pedido p JOIN cliente c ON p.cliente_id = c.id)
        THEN 'EQUIVALENCIA COMPLETA (0 filas EXCEPT y COUNT idéntico)'
        ELSE 'ERROR: DISCREPANCIA EN DUPLICADOS'
    END AS resultado_validacion_v2;


-- ---------------------------------------------------------------------
-- Equivalencia Vista 3: vw_detalle_pedido
-- ---------------------------------------------------------------------

-- 1. Diferencia simétrica
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

-- 2. Validación de cardinalidad estricta (COUNT)
SELECT 
    (SELECT COUNT(*) FROM vw_detalle_pedido) AS count_vista_3,
    (SELECT COUNT(*) FROM pedido_detalle pd JOIN producto pr ON pd.producto_id = pr.id) AS count_manual_3,
    CASE 
        WHEN (SELECT COUNT(*) FROM vw_detalle_pedido) = 
             (SELECT COUNT(*) FROM pedido_detalle pd JOIN producto pr ON pd.producto_id = pr.id)
        THEN 'EQUIVALENCIA COMPLETA (0 filas EXCEPT y COUNT idéntico)'
        ELSE 'ERROR: DISCREPANCIA EN DUPLICADOS'
    END AS resultado_validacion_v3;


-- =====================================================================
-- Demostración de Criterio de Seguridad con Roles y GRANT (Consigna §4.2.4)
-- =====================================================================

-- 1. Creación del rol restringido para consultas de reportes (sin superuser ni bypassrls)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'rol_reportes_foodstore') THEN
        CREATE ROLE rol_reportes_foodstore WITH LOGIN PASSWORD 'AuditorPassword2026!';
    END IF;
END $$;

-- 2. Asignación de privilegios: acceso exclusivo de lectura sobre la vista segura
GRANT SELECT ON vw_pedidos_cliente TO rol_reportes_foodstore;

-- 3. Revocación explícita de privilegios sobre las tablas base subyacentes
REVOKE ALL ON cliente FROM rol_reportes_foodstore;
REVOKE ALL ON pedido FROM rol_reportes_foodstore;

-- 4. Bloque de prueba de autorización (Ejecutar para verificar enforcement de permisos):
/*
-- Cambiar al rol restringido:
SET ROLE rol_reportes_foodstore;

-- Prueba A: Lectura exitosa de la vista (solo ve columnas no sensibles)
SELECT pedido_id, nombre, apellido, fecha, forma_pago 
FROM vw_pedidos_cliente 
LIMIT 5;

-- Prueba B: Intento de acceso a la tabla base 'cliente' (debe fallar con error de permisos)
-- SELECT * FROM cliente LIMIT 1;
-- ERROR: permission denied for table cliente

-- Restaurar el rol administrativo de sesión:
RESET ROLE;
*/
