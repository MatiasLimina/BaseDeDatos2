-- movil/casos/c3_borrador.sql: Caso C3 (Borrador que pide mas unidades que el stock disponible).
-- Producto B: Producto 19 (id 24, precio 114977 centavos, stock 4).
-- El borrador solicita 5 unidades (stock + 1), sin tocar el stock del servidor.

PRAGMA foreign_keys = ON;
.headers on
.echo on

BEGIN TRANSACTION;

INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('c3000000-0000-4000-8000-000000000001', 'vendedor_feria_1', 'EFECTIVO');

INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES ('c3000000-0000-4000-8000-000000000001', 24, 5, 114977);

INSERT INTO cola_sync (solicitud_uuid, id_local, estado)
VALUES ('c3000000-0000-4000-8000-000000000002', 'c3000000-0000-4000-8000-000000000001', 'PENDIENTE');

COMMIT;

-- Verificacion del borrador de C3 insertado:
SELECT id_local, usuario, forma_pago, fecha FROM pedido_borrador WHERE id_local = 'c3000000-0000-4000-8000-000000000001';
SELECT id_local, producto_id, cantidad, precio_centavos_visto FROM item_borrador WHERE id_local = 'c3000000-0000-4000-8000-000000000001';
SELECT solicitud_uuid, id_local, estado FROM cola_sync WHERE solicitud_uuid = 'c3000000-0000-4000-8000-000000000002';
