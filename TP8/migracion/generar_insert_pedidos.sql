-- =====================================================================
-- generar_insert_pedidos.sql — Genera mongodb/02_insert_pedidos.js desde PostgreSQL
-- Uso (desde la raíz del repo):
--   psql -X -w -h localhost -U postgres -d foodstore -At -v ON_ERROR_STOP=1 \
--        -f migracion/generar_insert_pedidos.sql -o mongodb/02_insert_pedidos.js
--
-- Arma una instrucción insertMany() con los pedidos de sql/01_seleccion_pedidos.sql
-- (la misma regla, repetida acá en la CTE seleccion). Así los valores se copian
-- de la base y no se transcriben a mano:
--   - _id, cliente.id y producto.id conservan los identificadores de origen;
--   - precio_unitario es el precio HISTÓRICO de pedido_detalle, nunca el
--     precio actual de producto;
--   - importes como NumberDecimal("...") (Decimal128), igual que NUMERIC(10,2);
--   - fecha como ISODate en UTC (timestamptz en PostgreSQL);
--   - los textos se escapan con to_json(), que produce cadenas JSON válidas en JS.
-- =====================================================================
WITH marcados AS (
    SELECT p.id, p.estado,
           EXISTS (SELECT 1 FROM pedido_detalle d
                   WHERE d.pedido_id = p.id AND d.producto_id = 13896) AS contiene_producto
    FROM pedido p
    WHERE p.id <= 200001   -- lote original (ver sql/01_seleccion_pedidos.sql)
),
seleccion AS (
    SELECT DISTINCT ON (estado, contiene_producto) id
    FROM marcados
    ORDER BY estado, contiene_producto, id
),
lineas AS (
    SELECT d.pedido_id,
           sum(d.subtotal) AS total,
           string_agg(format(
               '{ producto: { id: %s, nombre: %s, categoria: %s }, cantidad: %s, '
               'precio_unitario: NumberDecimal("%s"), subtotal: NumberDecimal("%s") }',
               pr.id, to_json(pr.nombre::text), to_json(ca.nombre::text),
               d.cantidad, d.precio_unitario, d.subtotal),
               E',\n      ' ORDER BY d.producto_id) AS js
    FROM pedido_detalle d
    JOIN producto pr  ON pr.id = d.producto_id
    JOIN categoria ca ON ca.id = pr.categoria_id
    WHERE d.pedido_id IN (SELECT id FROM seleccion)
    GROUP BY d.pedido_id
)
SELECT '// Generado por migracion/generar_insert_pedidos.sql desde foodstore (PostgreSQL). No editar a mano.'
       || E'\n// Uso: mongosh mongodb://localhost:27017/foodstore --file mongodb/02_insert_pedidos.js\n'
       || E'db = db.getSiblingDB("foodstore");\n'
       || E'const resultado = db.pedidos.insertMany([\n'
       || string_agg(format(
              -- || explícito: un literal E'...' no admite la concatenación implícita entre líneas.
              E'  { _id: %s, fecha: ISODate("%s"), estado: "%s", forma_pago: "%s",\n'
              || E'    cliente: { id: %s, nombre: %s, apellido: %s, email: %s },\n'
              || E'    lineas: [\n      %s\n    ],\n'
              || E'    total: NumberDecimal("%s") }',
              p.id, to_char(p.fecha AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
              p.estado, p.forma_pago,
              c.id, to_json(c.nombre::text), to_json(c.apellido::text), to_json(c.email::text),
              l.js, l.total),
              E',\n' ORDER BY p.id)
       || E'\n]);\n'
       || 'print("pedidos insertados: " + Object.keys(resultado.insertedIds).length);'
FROM pedido p
JOIN cliente c ON c.id = p.cliente_id
JOIN lineas l  ON l.pedido_id = p.id;
