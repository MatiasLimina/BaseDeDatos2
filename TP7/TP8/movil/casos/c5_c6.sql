-- movil/casos/c5_c6.sql: Caso C6 (Reintento del mismo UUID de solicitud, idempotencia).
-- Demuestra que la tablet rechaza por clave primaria (solicitud_uuid) una solicitud repetida
-- sin duplicar la fila ni alterar su estado.

PRAGMA foreign_keys = ON;
.headers on
.echo on

-- Asegura que el borrador de C5 existe (en corrida normal viene de pruebas_sqlite.sql):
INSERT OR IGNORE INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('c5000000-0000-4000-8000-000000000001', 'vendedor_feria_1', 'EFECTIVO');

INSERT OR IGNORE INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES ('c5000000-0000-4000-8000-000000000001', 4, 2, 320000);

INSERT OR IGNORE INTO cola_sync (solicitud_uuid, id_local, estado)
VALUES ('c5000000-0000-4000-8000-000000000002', 'c5000000-0000-4000-8000-000000000001', 'PENDIENTE');

-- C6: Reintento de insercion con el mismo solicitud_uuid (debe fallar por PK con .bail off)
.bail off
INSERT INTO cola_sync (solicitud_uuid, id_local, estado)
VALUES ('c5000000-0000-4000-8000-000000000002', 'c5000000-0000-4000-8000-000000000001', 'PENDIENTE');

-- Verificacion: solo existe una fila con ese UUID y su estado no se reinicio a PENDIENTE
SELECT solicitud_uuid, id_local, estado, motivo, evaluada_en, snapshot_copiado_en
FROM cola_sync
WHERE solicitud_uuid = 'c5000000-0000-4000-8000-000000000002';
