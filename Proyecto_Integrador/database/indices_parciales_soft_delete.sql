-- =====================================================================
-- Proyecto Integrador: Food Store (Base de Datos II)
-- Archivo: indices_parciales_soft_delete.sql
-- Motor: PostgreSQL 16+
-- Objetivo: Demostración técnica del impacto de Índices Parciales
--           sobre el esquema de Borrado Lógico (Soft Delete - Objetivo 9)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Contexto de Negocio y Arquitectura
-- ---------------------------------------------------------------------
-- En Food Store, el borrado de entidades operativas (producto, cliente, categoria)
-- se gestiona mediante baja lógica (columna `activo BOOLEAN NOT NULL DEFAULT TRUE`).
-- 
-- Problema con Índices Totales Tradicionales:
-- Un índice tradicional sobre `producto(categoria_id, activo)` o `producto(categoria_id, precio)`
-- indexa el 100% de las filas de la tabla, incluyendo productos descatalogados,
-- vencidos o inactivos que raramente o nunca son consultados en las transacciones
-- del día a día (ventas, catálogo de la UI, cálculo de precios).
--
-- Solución Técnica: Índices Parciales (Partial Indexes) con predicado `WHERE activo = TRUE`.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- 2. Creación del Índice Parcial
-- ---------------------------------------------------------------------

DROP INDEX IF EXISTS idx_producto_categoria_precio_activo;

CREATE INDEX idx_producto_categoria_precio_activo 
    ON producto(categoria_id, precio) 
    WHERE activo = TRUE;

COMMENT ON INDEX idx_producto_categoria_precio_activo IS 
'Índice parcial que almacena únicamente punteros a productos comercializables (activo = TRUE). Excluye bajas lógicas.';


-- ---------------------------------------------------------------------
-- 3. Prueba Comparativa de Rendimiento con EXPLAIN (ANALYZE, BUFFERS)
-- ---------------------------------------------------------------------

-- Caso A: Consulta operativa del catálogo filtrando productos activos por categoría
-- Esta consulta coincide con la lógica de negocio de la vista `vw_productos_vigentes`.

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, nombre, precio, stock
FROM producto
WHERE categoria_id = 1
  AND activo = TRUE
ORDER BY precio ASC;

-- Resultado esperado:
-- El optimizador de PostgreSQL reconoce que el predicado de la consulta (`activo = TRUE`)
-- satisface la condición del índice parcial (`WHERE activo = TRUE`), seleccionando un
-- `Index Scan using idx_producto_categoria_precio_activo`.
-- No requiere escanear ni cargar en shared_buffers las páginas correspondientes a filas inactivas.


-- Caso B: Consulta a través de la Vista `vw_productos_vigentes`
-- El optimizador despliega la vista y aplica automáticamente el índice parcial:

EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM vw_productos_vigentes
WHERE nombre_categoria = 'Bebidas'
ORDER BY precio ASC;


-- ---------------------------------------------------------------------
-- 4. Patrón Avanzado: Índice Único Parcial para Bajas Lógicas
-- ---------------------------------------------------------------------
-- Si una regla de negocio exige que no haya dos productos o clientes activos
-- con el mismo nombre o email, pero permite que un valor histórico dado de baja
-- sea reutilizado a futuro, se utiliza un Índice Único Parcial:

-- Ejemplo: Garantizar unicidad de email SOLO entre clientes activos
DROP INDEX IF EXISTS unq_cliente_email_activo;

CREATE UNIQUE INDEX unq_cliente_email_activo 
    ON cliente(email) 
    WHERE activo = TRUE;

-- Esto permite:
-- 1. Insertar cliente 'juan@ejemplo.com' (activo = TRUE) -> OK.
-- 2. Dar de baja lógica a Juan (activo = FALSE).
-- 3. Insertar un nuevo cliente 'juan@ejemplo.com' (activo = TRUE) -> OK (sin violar restricción).
-- 4. Intentar insertar un segundo cliente activo 'juan@ejemplo.com' -> RECHAZADO por el motor.


-- ---------------------------------------------------------------------
-- 5. Consulta de Diagnóstico: Comparativa de Tamaño en Disco
-- ---------------------------------------------------------------------
-- Permite verificar el ahorro de espacio en bytes entre un índice total y uno parcial:

SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS tamano_indice
FROM pg_stat_user_indexes
WHERE tablename IN ('producto', 'cliente')
ORDER BY tablename, indexname;
