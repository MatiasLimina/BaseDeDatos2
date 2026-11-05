-- =====================================================================
-- consultas_postgresql.sql — Parte 2, Consigna 5: equivalentes en PostgreSQL
-- Uso: psql -X -w -h localhost -U postgres -d foodstore -v ON_ERROR_STOP=1 -f consultas_postgresql.sql
--
-- Equivalentes de las consultas b) y c) de consultas_mongodb.js; d) se agrega
-- como verificación adicional. Cada consulta se define una sola vez, como vista
-- temporal (desaparece al cerrar la sesión). Se muestra y después se imprime
-- "RESULTADO <x>: <ids>", que tests/test_consultas.sh compara con MongoDB.
-- Solo lectura: no modifica foodstore.
-- =====================================================================

\set QUIET 1
\pset footer off
\set QUIET 0

-- ---------------------------------------------------------------------
-- Primera versión: las consultas sobre TODA la tabla pedido.
-- Diferencia detectada: PostgreSQL devuelve decenas de miles de pedidos y
-- MongoDB, 2 y 5. No es un error del modelo: en MongoDB está solo el
-- subconjunto migrado (9 pedidos), mientras que foodstore tiene 200 001.
-- Corrección: comparar sobre los mismos pedidos (sección siguiente).
-- ---------------------------------------------------------------------
\echo '== Primera versión, sobre toda la tabla (no comparable con MongoDB)'
SELECT (SELECT count(*) FROM pedido WHERE estado = 'ENTREGADO') AS b_estado_entregado,
       (SELECT count(DISTINCT pedido_id) FROM pedido_detalle WHERE producto_id = 13896) AS c_con_producto_13896;

-- ---------------------------------------------------------------------
-- Corrección: los 9 pedidos migrados, la lista que produce
-- sql/01_seleccion_pedidos.sql. Literal, para que se vea qué se compara.
-- ---------------------------------------------------------------------
\set QUIET 1
CREATE TEMP VIEW migrados (id) AS
    VALUES (1::bigint), (2), (7), (20), (26), (120), (217), (240), (10167);

-- Total del pedido: pedido no tiene columna total; es la suma de los subtotales.
CREATE TEMP VIEW pedido_total AS
    SELECT d.pedido_id AS id, sum(d.subtotal) AS total
    FROM pedido_detalle d
    GROUP BY d.pedido_id;

-- b) Pedidos con estado ENTREGADO (equivalente de { estado: "ENTREGADO" }).
CREATE TEMP VIEW consulta_b AS
    SELECT p.id, p.estado, p.fecha, t.total
    FROM pedido p
    JOIN migrados m USING (id)
    JOIN pedido_total t USING (id)
    WHERE p.estado = 'ENTREGADO';

-- c) Pedidos que contienen el producto 13896 (equivalente de
--    { "lineas.producto.id": 13896 }). En el modelo relacional, la "línea" es
--    una fila de pedido_detalle: hace falta el JOIN.
CREATE TEMP VIEW consulta_c AS
    SELECT p.id, p.estado, d.producto_id, pr.nombre AS producto, d.cantidad, d.precio_unitario
    FROM pedido p
    JOIN migrados m USING (id)
    JOIN pedido_detalle d ON d.pedido_id = p.id
    JOIN producto pr ON pr.id = d.producto_id
    WHERE d.producto_id = 13896;
-- Sin DISTINCT: la PK (pedido_id, producto_id) garantiza una sola fila por pedido.

-- d) Pedidos con total mayor que 20 000 (umbral justificado en consultas_mongodb.js).
CREATE TEMP VIEW consulta_d AS
    SELECT p.id, p.estado, t.total
    FROM pedido p
    JOIN migrados m USING (id)
    JOIN pedido_total t USING (id)
    WHERE t.total > 20000.00;
\set QUIET 0

-- La lista literal también se imprime: el test la compara con la regla de selección.
SELECT coalesce(string_agg(id::text, ',' ORDER BY id), '') AS ids FROM migrados \gset
\echo 'RESULTADO a:' :ids

\echo '== b) Pedidos migrados con estado ENTREGADO'
SELECT * FROM consulta_b ORDER BY id;
SELECT coalesce(string_agg(id::text, ',' ORDER BY id), '') AS ids, count(*) AS n FROM consulta_b \gset
\echo 'RESULTADO b:' :ids
\echo :n 'pedidos'

\echo '== c) Pedidos migrados que contienen el producto 13896'
SELECT * FROM consulta_c ORDER BY id;
SELECT coalesce(string_agg(id::text, ',' ORDER BY id), '') AS ids, count(*) AS n FROM consulta_c \gset
\echo 'RESULTADO c:' :ids
\echo :n 'pedidos'

\echo '== d) Pedidos migrados con total > 20000.00'
SELECT * FROM consulta_d ORDER BY total DESC;
SELECT coalesce(string_agg(id::text, ',' ORDER BY id), '') AS ids, count(*) AS n FROM consulta_d \gset
\echo 'RESULTADO d:' :ids
\echo :n 'pedidos'
