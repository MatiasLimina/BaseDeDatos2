-- movil/casos/c2_aceptar.sql: Caso C2 (Aceptacion del precio nuevo).
-- Cuando el cliente acepta el precio actualizado por el servidor (299000 centavos),
-- la tablet actualiza el precio visto en los items del borrador y crea una nueva
-- solicitud PENDIENTE en cola_sync, todo en una unica transaccion atomica.
-- La solicitud original anterior permanece como CONFLICTO para trazabilidad historica.

PRAGMA foreign_keys = ON;
.headers on
.echo on

BEGIN TRANSACTION;

UPDATE item_borrador
SET precio_centavos_visto = (
  SELECT precio_centavos
  FROM snapshot_servidor
  WHERE snapshot_servidor.id = item_borrador.producto_id
)
WHERE id_local = 'c2000000-0000-4000-8000-000000000001'
  AND producto_id = 1;

INSERT INTO cola_sync (solicitud_uuid, id_local, estado)
VALUES ('c2000000-0000-4000-8000-000000000003', 'c2000000-0000-4000-8000-000000000001', 'PENDIENTE');

COMMIT;

-- Verificacion: precio visto actualizado y nueva solicitud PENDIENTE:
SELECT id_local, producto_id, cantidad, precio_centavos_visto
FROM item_borrador
WHERE id_local = 'c2000000-0000-4000-8000-000000000001';

SELECT solicitud_uuid, id_local, estado, motivo
FROM cola_sync
WHERE id_local = 'c2000000-0000-4000-8000-000000000001'
ORDER BY creada_en ASC;
