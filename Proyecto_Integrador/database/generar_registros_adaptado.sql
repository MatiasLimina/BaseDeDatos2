-- =====================================================================
-- Proyecto Integrador: Food Store - Generación masiva adaptada
-- Origen: Generar_registros_bdCopia.sql / Generar_registros_bdOG.sql (profesor)
-- Destino: Compatible con Proyecto_Integrador/database/schema.sql y triggers.sql
-- Motor: PostgreSQL
-- Uso: psql -U postgres -d foodstore_copia -f Proyecto_Integrador/database/generar_registros_adaptado.sql
--      Para BD original: psql -U postgres -d foodstore -f Proyecto_Integrador/database/generar_registros_adaptado.sql
-- Protocolo: Probar primero en copia con BEGIN ... ROLLBACK (ver protocolo_seguridad.md)
-- =====================================================================

-- NOTA: No usar "USE food_store_copia;" en PostgreSQL. La BD se elige en la conexión.

BEGIN;

-- ---------------------------------------------------------------------
-- 1) Productos: 50.000 filas repartidas entre las categorías existentes
-- Adaptado: elimina columna "descripcion" (no existe en schema.sql:40-47),
--           agrega "activo" = TRUE para no violar trg_verificar_producto_activo
-- ---------------------------------------------------------------------
INSERT INTO producto (nombre, precio, stock, activo, categoria_id)
SELECT 'Producto ' || i,
       (random() * 4500 + 500)::numeric(10,2),
       (random() * 200)::int,
       TRUE,
       (SELECT id FROM categoria ORDER BY random() LIMIT 1)
FROM generate_series(1, 50000) AS s(i);

-- ---------------------------------------------------------------------
-- 2) Clientes: 20.000 filas
-- Adaptado: tabla "usuario" -> "cliente" (schema.sql:64-75)
--           mail -> email, celular -> telefono, se descarta contrasena,
--           se agrega activo = TRUE para no violar trg_verificar_cliente_activo
-- ---------------------------------------------------------------------
INSERT INTO cliente (nombre, apellido, email, telefono, activo)
SELECT 'Usuario' || i,
       'Apellido' || i,
       'usuario' || i || '@test.com',
       '261' || lpad((random()*9999999)::int::text, 7, '0'),
       TRUE
FROM generate_series(1, 20000) AS s(i);

-- ---------------------------------------------------------------------
-- 3) Pedidos: 200.000 filas, con cliente existente elegido al azar
-- Adaptado: elimina columna "estado" y tipo estado_pedido (no existe en schema.sql:80-93),
--           usuario_id -> cliente_id, casteo a forma_pago_enum (schema.sql:20-25)
-- ---------------------------------------------------------------------
INSERT INTO pedido (fecha, forma_pago, cliente_id)
SELECT CURRENT_DATE - (random()*365)::int,
       (ARRAY['EFECTIVO','TARJETA','TRANSFERENCIA']::forma_pago_enum)[floor(random()*3+1)],
       (SELECT id FROM cliente ORDER BY random() LIMIT 1)
FROM generate_series(1, 200000) AS s(i);

-- ---------------------------------------------------------------------
-- 4) Detalle de pedido: entre 1 y 4 líneas por pedido, sin repetir producto
-- Adaptado: tabla "detalle_pedido" -> "pedido_detalle" (schema.sql:98-122)
--           Se calculan precio_unitario y subtotal leyendo producto.precio
--           (cumple R4 histórico, evita depender de trigger trg_subtotal inexistente)
-- ---------------------------------------------------------------------
INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
SELECT pedido_id, producto_id, cantidad, p.precio, (cantidad * p.precio)::numeric(10,2)
FROM (
    SELECT p.id AS pedido_id, pr.producto_id,
           (random()*3 + 1)::int AS cantidad,
           row_number() OVER (PARTITION BY p.id ORDER BY random()) AS rn,
           (1 + floor(random()*4))::int AS n_lineas
    FROM pedido p
    CROSS JOIN LATERAL (
        SELECT id AS producto_id FROM producto ORDER BY random() LIMIT 4
    ) pr
) sub
JOIN producto p ON p.id = sub.producto_id
WHERE rn <= n_lineas
ON CONFLICT (pedido_id, producto_id) DO NOTHING;

COMMIT;

ANALYZE producto;
ANALYZE cliente;
ANALYZE pedido;
ANALYZE pedido_detalle;
