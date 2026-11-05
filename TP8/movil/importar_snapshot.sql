PRAGMA foreign_keys = ON;
.bail on

-- Importa movil/servidor_snapshot.csv a snapshot_servidor.
-- Uso (desde TP8/): sqlite3 movil/foodstore_movil.db < movil/importar_snapshot.sql
BEGIN;

DELETE FROM snapshot_servidor;
.import --csv --skip 1 movil/servidor_snapshot.csv snapshot_servidor

-- Guarda: .import informa las filas fallidas pero sigue. Si la cantidad cargada no
-- coincide con filas_copia (o hay un char(13) de un fin de linea \r\n), el CHECK falla,
-- .bail corta y la transaccion abierta se deshace al salir.
CREATE TEMP TABLE verificacion_importacion (ok INTEGER NOT NULL CHECK (ok = 1));
INSERT INTO verificacion_importacion
SELECT CASE WHEN count(*) > 0
             AND count(*) = min(filas_copia) AND count(*) = max(filas_copia)
             AND sum(instr(copiado_en, char(13)) + instr(nombre, char(13))) = 0
            THEN 1 ELSE 0 END
FROM snapshot_servidor;
DROP TABLE verificacion_importacion;

-- Recarga de producto_cache: upsert, NUNCA borrar. item_borrador referencia al producto
-- (la FK impediria el DELETE) y C4 pide que la fila quede. "WHERE true" evita la ambiguedad
-- de parseo de SELECT + ON CONFLICT.
INSERT INTO producto_cache (id, nombre, precio_centavos, stock_visto, disponible, eliminado, copiado_en)
SELECT id, nombre, precio_centavos, stock, disponible, eliminado, copiado_en
FROM snapshot_servidor WHERE true
ON CONFLICT (id) DO UPDATE SET
  nombre = excluded.nombre,
  precio_centavos = excluded.precio_centavos,
  stock_visto = excluded.stock_visto,
  disponible = excluded.disponible,
  eliminado = excluded.eliminado,
  copiado_en = excluded.copiado_en;

-- Los productos que el servidor ya no manda quedan como lapida: eliminado=1, disponible=0.
UPDATE producto_cache SET eliminado = 1, disponible = 0
WHERE id NOT IN (SELECT id FROM snapshot_servidor);

COMMIT;
