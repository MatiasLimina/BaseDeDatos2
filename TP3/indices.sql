-- =====================================================================
-- Base de Datos II — Trabajo Práctico Unidad 3 (Food Store)
-- Archivo: indices.sql
-- Integrantes: Matías Limina, Nicolás Monjelardi, Lautaro Agüero
-- Motor: PostgreSQL 16+
-- Repositorio: https://github.com/MatiasLimina/BaseDeDatos2.git
-- =====================================================================

-- =====================================================================
-- 1. ÍNDICE ACEPTADO (Verificado empíricamente con beneficio real)
-- =====================================================================

-- Índice: idx_pedido_fecha
-- Tabla: pedido(fecha)
-- Tipo: B-tree
-- Justificación técnica:
--   Cubre filtros de rango (BETWEEN, >=, <=) sobre fecha de pedido.
--   Transforma un 'Parallel Seq Scan' costoso (289.65 ms) en un 'Index Scan'
--   altamente selectivo (0.018 ms), logrando una aceleración de ~16.000x.
CREATE INDEX idx_pedido_fecha ON pedido(fecha);


-- =====================================================================
-- 2. ÍNDICES DESCARTADOS POR SOBREINDEXACIÓN
-- Criterio de ingeniería: Ningún índice debe persistir si no produce
-- ganancia medible en el planificador o si genera overhead injustificado.
-- =====================================================================

/*
-------------------------------------------------------------------------
Índice Descartado 1: idx_detalle_producto_id
Propuesta: CREATE INDEX idx_detalle_producto_id ON pedido_detalle(producto_id);
Tabla: pedido_detalle
Motivo de descarte (Sobreindexación - Ignorado por el optimizador):
  - Consulta objetivo: Top 5 productos más vendidos (SUM de cantidad agrupado por producto).
  - Comportamiento del planner: Con ~621.199 filas en pedido_detalle, el optimizador
    evaluó el índice y lo IGNORÓ por completo, manteniendo 'Seq Scan + Hash Join'.
  - Razón técnica: Al tener que procesar la totalidad o gran volumen de la tabla
    para calcular el agregado, el costo de accesos aleatorios al heap mediante
    un Index Scan es superior a la lectura secuencial continua (Seq Scan).
  - La aparente reducción de tiempo (423 ms a 218 ms) se debió exclusivamente al
    efecto de 'warm cache' (páginas ya cargadas en shared_buffers), no al índice.
  - Conclusión: Mantenerlo solo degradaría el rendimiento de las operaciones de
    escritura (INSERT/UPDATE/DELETE) y consumiría espacio en disco sin beneficio.
-------------------------------------------------------------------------
-- CREATE INDEX idx_detalle_producto_id ON pedido_detalle(producto_id);


-------------------------------------------------------------------------
Índice Descartado 2: idx_detalle_subtotal
Propuesta: CREATE INDEX idx_detalle_subtotal ON pedido_detalle(pedido_id, subtotal DESC);
Tabla: pedido_detalle
Motivo de descarte (Sobreindexación - Overhead sin beneficio):
  - Consulta objetivo: Detalle de un pedido específico ordenado por subtotal DESC.
  - Comportamiento del planner: La consulta ANTES ya resolvía de manera óptima
    con 'Index Scan' utilizando la clave primaria compuesta pk_pedido_detalle
    (pedido_id, producto_id), tardando apenas 0.055 ms.
  - Resultado con el nuevo índice: Cambió el índice usado pero el tiempo de ejecución
    se incrementó a 0.102 ms (+85% de overhead).
  - Razón técnica: Dado que un pedido típico contiene pocas líneas (1 a 5 ítems),
    el sort de esas pocas tuplas en memoria (RAM) tiene costo despreciable.
    Crear y mantener un índice compuesto secundario no justifica ahorrarse un
    quicksort en memoria de 3 filas.
  - Conclusión: Se descarta por redundancia y costo injustificado de mantenimiento.
-------------------------------------------------------------------------
-- CREATE INDEX idx_detalle_subtotal ON pedido_detalle(pedido_id, subtotal DESC);


-------------------------------------------------------------------------
Índice Descartado 3: idx_pedido_forma_pago
Propuesta: CREATE INDEX idx_pedido_forma_pago ON pedido(forma_pago);
Tabla: pedido
Motivo de descarte (Baja cardinalidad / baja selectividad):
  - La columna forma_pago utiliza el tipo ENUM 'forma_pago_enum' con solo 4 valores.
  - Cualquier filtro simple selecciona en promedio el ~25% de la tabla.
  - PostgreSQL descarta índices con tan baja selectividad ante consultas generales
    y opta por 'Seq Scan + Filter', pues saltar al heap para el 25% de las filas
    es más costoso que leer las páginas secuencialmente.
-------------------------------------------------------------------------
-- CREATE INDEX idx_pedido_forma_pago ON pedido(forma_pago);
*/


-- =====================================================================
-- 3. MEDICIONES EXPLAIN ANALYZE
-- =====================================================================

-- Consulta 1: Rango de fechas con forma de pago (Caso exitoso)
-- ANTES: Parallel Seq Scan (Execution Time: 289.652 ms)
-- DESPUÉS: Index Scan using idx_pedido_fecha (Execution Time: 0.018 ms)
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM pedido
WHERE fecha BETWEEN '2023-01-01' AND '2023-12-31'
  AND forma_pago = 'EFECTIVO';