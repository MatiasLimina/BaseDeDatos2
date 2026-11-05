-- movil/casos/c4_borrador.sql: Caso C4 (Borrador con producto C antes de la baja en el servidor).
-- Producto C: Papas Fritas 150g (id 3, precio 180000 centavos, stock 29).

PRAGMA foreign_keys = ON;
.headers on
.echo on

BEGIN TRANSACTION;

INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('c4000000-0000-4000-8000-000000000001', 'vendedor_feria_1', 'EFECTIVO');

INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES ('c4000000-0000-4000-8000-000000000001', 3, 2, 180000);

INSERT INTO cola_sync (solicitud_uuid, id_local, estado)
VALUES ('c4000000-0000-4000-8000-000000000002', 'c4000000-0000-4000-8000-000000000001', 'PENDIENTE');

COMMIT;

-- Verificacion del borrador de C4 insertado:
SELECT id_local, usuario, forma_pago, fecha FROM pedido_borrador WHERE id_local = 'c4000000-0000-4000-8000-000000000001';
SELECT id_local, producto_id, cantidad, precio_centavos_visto FROM item_borrador WHERE id_local = 'c4000000-0000-4000-8000-000000000001';
SELECT solicitud_uuid, id_local, estado FROM cola_sync WHERE solicitud_uuid = 'c4000000-0000-4000-8000-000000000002';
