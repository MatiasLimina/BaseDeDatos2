-- pruebas_sqlite.sql: pruebas de la base SQLite de la tablet (Consigna 1.c).
-- Cubre:
--   1. Borrador completo con BEGIN ... COMMIT (borrador del caso C5).
--   2. Operacion deshecha con ROLLBACK (atomicidad: nada a medias).
--   3. Caso C1: consulta del catalogo disponible offline.
--   4. Caso C7: datos invalidos (cantidad 0 y producto inexistente) no dejan filas.

.headers on
.echo on

-- Integridad referencial obligatoria por conexion.
PRAGMA foreign_keys = ON;
PRAGMA foreign_keys;

-- ============================================================================
-- 1. Borrador completo guardado de forma atomica con COMMIT.
--    Este borrador corresponde al Caso C5 (Producto D: Queso Tybo x 200g, id 4,
--    precio 3200.00 / 320000 centavos, stock suficiente).
--    Nace PENDIENTE en cola_sync para ser evaluado luego por el semaforo.
-- ============================================================================

BEGIN TRANSACTION;

INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('c5000000-0000-4000-8000-000000000001', 'vendedor_feria_1', 'EFECTIVO');

INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES ('c5000000-0000-4000-8000-000000000001', 4, 2, 320000);

INSERT INTO cola_sync (solicitud_uuid, id_local, estado)
VALUES ('c5000000-0000-4000-8000-000000000002', 'c5000000-0000-4000-8000-000000000001', 'PENDIENTE');

COMMIT;

-- Verificacion del borrador de C5 insertado:
SELECT id_local, usuario, forma_pago, fecha FROM pedido_borrador WHERE id_local = 'c5000000-0000-4000-8000-000000000001';
SELECT id_local, producto_id, cantidad, precio_centavos_visto FROM item_borrador WHERE id_local = 'c5000000-0000-4000-8000-000000000001';
SELECT solicitud_uuid, id_local, estado, motivo FROM cola_sync WHERE solicitud_uuid = 'c5000000-0000-4000-8000-000000000002';

-- ============================================================================
-- 2. Operacion deshecha con ROLLBACK.
--    Demuestra que una transaccion abortada no deja filas en ninguna tabla.
-- ============================================================================

-- Conteos antes del ROLLBACK:
SELECT count(*) AS n_pedidos_antes_rollback FROM pedido_borrador;
SELECT count(*) AS n_items_antes_rollback FROM item_borrador;
SELECT count(*) AS n_cola_antes_rollback FROM cola_sync;

BEGIN TRANSACTION;

INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('00000000-0000-4000-8000-000000000002', 'vendedor_feria_1', 'TARJETA');

INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES ('00000000-0000-4000-8000-000000000002', 4, 1, 320000);

INSERT INTO cola_sync (solicitud_uuid, id_local, estado)
VALUES ('00000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000002', 'PENDIENTE');

ROLLBACK;

-- Conteos despues del ROLLBACK: deben ser exactamente iguales a los de antes:
SELECT count(*) AS n_pedidos_despues_rollback FROM pedido_borrador;
SELECT count(*) AS n_items_despues_rollback FROM item_borrador;
SELECT count(*) AS n_cola_despues_rollback FROM cola_sync;

-- ============================================================================
-- 3. Caso C1: Catalogo disponible offline.
--    La tablet lista los productos aptos para la venta (disponible = 1 y
--    eliminado = 0) leyendo exclusivamente de su base local SQLite.
-- ============================================================================

-- Para que la evidencia sea legible: el total del catalogo disponible y las
-- primeras 10 filas (la consulta completa es la misma sin el LIMIT).
SELECT count(*) AS productos_en_catalogo
FROM producto_cache
WHERE disponible = 1 AND eliminado = 0;

SELECT id, nombre, precio_centavos, stock_visto
FROM producto_cache
WHERE disponible = 1 AND eliminado = 0
ORDER BY id
LIMIT 10;

-- ============================================================================
-- 4. Caso C7: Datos invalidos no dejan filas nuevas (.bail off para ver errores).
--    C7.a: Intento de insertar item con cantidad 0 (viola CHECK).
--    C7.b: Intento de insertar item con producto inexistente (viola FOREIGN KEY).
-- ============================================================================

.bail off

-- Conteos antes de los intentos invalidos:
SELECT count(*) AS n_pedidos_antes_c7 FROM pedido_borrador;
SELECT count(*) AS n_items_antes_c7 FROM item_borrador;
SELECT count(*) AS n_cola_antes_c7 FROM cola_sync;
SELECT count(*) AS n_prod_antes_c7 FROM producto_cache;

-- C7.a: Cantidad 0 dentro de un borrador en curso (rechazado por CHECK) + ROLLBACK
BEGIN TRANSACTION;
INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('00000000-0000-4000-8000-000000000007', 'vendedor_feria_1', 'EFECTIVO');

INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES ('00000000-0000-4000-8000-000000000007', 4, 0, 320000);

ROLLBACK;

-- C7.b: Producto inexistente (rechazado por FOREIGN KEY) + ROLLBACK
BEGIN TRANSACTION;
INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('00000000-0000-4000-8000-000000000008', 'vendedor_feria_1', 'EFECTIVO');

INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES ('00000000-0000-4000-8000-000000000008', 999999, 1, 10000);

ROLLBACK;

-- Conteos despues de los intentos de C7: deben ser exactamente los mismos de antes:
SELECT count(*) AS n_pedidos_despues_c7 FROM pedido_borrador;
SELECT count(*) AS n_items_despues_c7 FROM item_borrador;
SELECT count(*) AS n_cola_despues_c7 FROM cola_sync;
SELECT count(*) AS n_prod_despues_c7 FROM producto_cache;
