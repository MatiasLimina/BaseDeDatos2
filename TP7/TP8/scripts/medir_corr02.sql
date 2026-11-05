-- Comprobacion del hallazgo CORR-02 (code review 3.c).
-- Uso (desde TP8/): psql -X -w -h localhost -U postgres -d food_store_copia -f scripts/medir_corr02.sql
-- Se mide en food_store_copia: por regla del change el TP8 solo usa esa base (para no
-- tocar la original), y la foodstore del TP7 no existe en esta maquina. La copia no tiene pedido.estado (lo agrego el TP7), por
-- eso el SELECT final no lo muestra: la vista que se mide (pedido_total) no lo usa.
-- Solo lectura: vistas temporales (mueren con la sesion) y EXPLAIN ANALYZE de un SELECT.
-- Mide la consulta d) de ../consultas_postgresql.sql con la vista pedido_total original
-- (agrupa todo pedido_detalle) y con el filtro temprano por los 9 pedidos migrados.
-- Antes de cada EXPLAIN se corre la misma consulta una vez (calentamiento): asi las dos
-- versiones se comparan con la cache caliente y no gana la que corrio despues.

\pset footer off
SELECT version();
SELECT count(*) AS filas_pedido_detalle FROM pedido_detalle;

CREATE TEMP VIEW migrados (id) AS
    VALUES (1::bigint), (2), (7), (20), (26), (120), (217), (240), (10167);

-- Version original (consultas_postgresql.sql, lineas 36-39).
CREATE TEMP VIEW pedido_total AS
    SELECT d.pedido_id AS id, sum(d.subtotal) AS total
    FROM pedido_detalle d
    GROUP BY d.pedido_id;

-- Version con filtro temprano (la que propone la IA).
CREATE TEMP VIEW pedido_total_opt AS
    SELECT d.pedido_id AS id, sum(d.subtotal) AS total
    FROM pedido_detalle d
    WHERE d.pedido_id IN (SELECT id FROM migrados)
    GROUP BY d.pedido_id;

\echo '== Antes: consulta d) con pedido_total (original)'
SELECT count(*) AS calentamiento FROM (SELECT p.id, t.total
FROM pedido p JOIN migrados m USING (id) JOIN pedido_total t USING (id)
WHERE t.total > 20000.00) x;
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, t.total
FROM pedido p JOIN migrados m USING (id) JOIN pedido_total t USING (id)
WHERE t.total > 20000.00;

\echo '== Despues: consulta d) con pedido_total_opt (filtro temprano)'
SELECT count(*) AS calentamiento FROM (SELECT p.id, t.total
FROM pedido p JOIN migrados m USING (id) JOIN pedido_total_opt t USING (id)
WHERE t.total > 20000.00) x;
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, t.total
FROM pedido p JOIN migrados m USING (id) JOIN pedido_total_opt t USING (id)
WHERE t.total > 20000.00;

\echo '== Mismo resultado en las dos versiones'
SELECT 'original' AS version, string_agg(id::text, ',' ORDER BY id) AS ids
FROM (SELECT p.id FROM pedido p JOIN migrados m USING (id) JOIN pedido_total t USING (id)
      WHERE t.total > 20000.00) x
UNION ALL
SELECT 'filtro temprano', string_agg(id::text, ',' ORDER BY id)
FROM (SELECT p.id FROM pedido p JOIN migrados m USING (id) JOIN pedido_total_opt t USING (id)
      WHERE t.total > 20000.00) x;
