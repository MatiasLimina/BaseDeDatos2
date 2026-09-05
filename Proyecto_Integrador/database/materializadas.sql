-- =====================================================================
-- Proyecto Integrador: Food Store (TP3 — Punto 4.3)
-- Archivo: materializadas.sql
-- Motor: PostgreSQL
-- Descripción: Vista materializada de facturación por categoría y mes
-- Spec:  Proyecto_Integrador/specs/spec_punto_4.3/requirements.md
-- =====================================================================

-- ---------------------------------------------------------------------
-- Consulta_Original — Medición ANTES de materializar (Requisito 3.1)
--
-- Ejecutar este bloque ANTES de crear la vista materializada para
-- registrar Planning Time y Execution Time de la consulta con 4 JOINs
-- + agregación sobre cientos de miles de filas.
-- ---------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    c.nombre                              AS categoria,
    DATE_TRUNC('month', p.fecha)          AS mes,
    COUNT(DISTINCT p.id)                  AS total_pedidos,
    SUM(pd.subtotal)                      AS facturacion_total
FROM pedido_detalle pd
JOIN pedido    p  ON pd.pedido_id    = p.id
JOIN producto  pr ON pd.producto_id  = pr.id
JOIN categoria c  ON pr.categoria_id = c.id
GROUP BY c.nombre, DATE_TRUNC('month', p.fecha)
ORDER BY mes DESC, facturacion_total DESC;

-- Resultado real (anotaciones_vistas_materializadas.txt — base con 621 199 filas en pedido_detalle):
-- Incremental Sort (cost=66612.59..154189.05) + GroupAggregate + Gather Merge (2 workers)
--   + Sort external merge Disk 8880kB + Hash Join ×3 + Parallel Seq Scan
--   Buffers: shared hit=6894 read=1568, temp read=3170 written=3179
-- Planning Time: 67.035 ms
-- Execution Time: 760.827 ms


-- ---------------------------------------------------------------------
-- Requisito 1 — Creación de la vista materializada con WITH DATA
--
-- Reporte: facturación histórica agrupada por categoría y mes.
-- Justificación: 4 JOINs (pedido_detalle→pedido, pedido_detalle→producto,
-- producto→categoria) + SUM + COUNT DISTINCT sobre ~621k filas en
-- pedido_detalle. Candidata natural a materialización.
-- Columnas: categoria (c.nombre), mes (DATE_TRUNC month de pedido.fecha),
--           total_pedidos (COUNT DISTINCT pedido.id),
--           facturacion_total (SUM pedido_detalle.subtotal)
-- ---------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS mv_facturacion_categoria_mes CASCADE;

CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS
SELECT
    c.nombre                              AS categoria,
    DATE_TRUNC('month', p.fecha)          AS mes,
    COUNT(DISTINCT p.id)                  AS total_pedidos,
    SUM(pd.subtotal)                      AS facturacion_total
FROM pedido_detalle pd
JOIN pedido    p  ON pd.pedido_id    = p.id
JOIN producto  pr ON pd.producto_id  = pr.id
JOIN categoria c  ON pr.categoria_id = c.id
GROUP BY c.nombre, DATE_TRUNC('month', p.fecha)
ORDER BY mes DESC, facturacion_total DESC
WITH DATA;
-- WITH DATA: la vista queda inmediatamente poblada con los datos vigentes
-- al momento de la creación. La alternativa WITH NO DATA requeriría un
-- REFRESH explícito antes del primer uso.


-- ---------------------------------------------------------------------
-- Requisito 2 — Índice UNIQUE sobre (categoria, mes)
--
-- Prerrequisito técnico de REFRESH CONCURRENTLY: PostgreSQL exige al
-- menos un índice UNIQUE sobre la vista materializada para poder
-- refrescar sin adquirir bloqueo exclusivo (permite lecturas concurrentes
-- durante el REFRESH). No es un índice de búsqueda primario.
-- Si (categoria, mes) no fuera único, este CREATE INDEX fallará con
-- error de violación de unicidad, señalando que la definición de la
-- vista debe revisarse (GROUP BY ya garantiza 1 fila por par).
-- ---------------------------------------------------------------------
CREATE UNIQUE INDEX idx_mv_facturacion_categoria_mes
    ON mv_facturacion_categoria_mes (categoria, mes);
-- NOTA: Índice UNIQUE requerido para REFRESH MATERIALIZED VIEW CONCURRENTLY.
-- Sin este índice, CONCURRENTLY falla con:
--   "cannot refresh materialized view concurrently without a unique index"


-- ---------------------------------------------------------------------
-- Requisito 3 — Medición DESPUÉS sobre la vista materializada
--
-- Ejecutar este bloque DESPUÉS de crear la vista + índice para comparar
-- contra la Consulta_Original. Debe ser más rápido: lee páginas ya
-- materializadas en disco (Seq Scan sobre la vista) en lugar de
-- re-ejecutar JOINs y agregaciones.
-- ---------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM mv_facturacion_categoria_mes;

-- Resultado real (anotaciones_vistas_materializadas.txt):
-- Seq Scan on mv_facturacion_categoria_mes (cost=0.00..1.24 rows=24 width=226)
--   Buffers: shared hit=1
--   Planning Buffers: shared hit=21 read=1 dirtied=3
-- Planning Time: 1.567 ms
-- Execution Time: 0.020 ms


-- ---------------------------------------------------------------------
-- Refresco concurrente (Requisito 4.5)
--
-- Comando exacto para refrescar sin bloquear lecturas. Programable vía
-- pg_cron o script de mantenimiento nocturno. Requiere el índice UNIQUE
-- creado arriba; de lo contrario usar REFRESH sin CONCURRENTLY (bloqueante).
-- ---------------------------------------------------------------------
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes;

-- Alternativa bloqueante (no concurrente, adquiere ACCESS EXCLUSIVE):
-- REFRESH MATERIALIZED VIEW mv_facturacion_categoria_mes;
