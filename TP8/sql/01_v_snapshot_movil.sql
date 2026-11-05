-- Vista de la instantanea del catalogo para la tablet (TP8, consigna 2.a).
-- [PG-escritura] Solo agrega un objeto (la vista) en food_store_copia; no altera tablas.
-- Uso (desde TP8/): PGCLIENTENCODING=UTF8 psql -X -w -h localhost -U postgres -d food_store_copia -v ON_ERROR_STOP=1 -f sql/01_v_snapshot_movil.sql
-- Rollback: DROP VIEW IF EXISTS v_snapshot_movil;

-- Guarda: si se lanza contra foodstore o food_store, aborta sin cambiar nada.
DO $$
BEGIN
  IF current_database() <> 'food_store_copia' THEN
    RAISE EXCEPTION 'Base equivocada: % (solo food_store_copia)', current_database();
  END IF;
END $$;

CREATE OR REPLACE VIEW v_snapshot_movil AS
SELECT p.id,                                    -- id del servidor: es el id de producto_cache
       p.nombre,
       -- Precio en centavos enteros: SQLite STRICT lo guarda como INTEGER, sin redondeos
       -- de coma flotante. round() antes del cast para no depender del redondeo implicito.
       round(p.precio * 100)::bigint            AS precio_centavos,
       p.stock,
       -- Booleanos como enteros 1/0: en un CSV de psql saldrian como t/f y la tabla STRICT
       -- de la tablet los rechazaria. disponible = activo y con stock.
       (p.activo AND p.stock > 0)::int          AS disponible,
       -- eliminado = no activo. Se incluyen TODOS los productos, tambien los inactivos:
       -- son la "lapida" que le avisa a la tablet de una baja.
       (NOT p.activo)::int                      AS eliminado,
       -- now() es constante dentro de la transaccion del \copy: una sola fecha de copia
       -- por instantanea, en ISO-8601 UTC (ordenable como texto).
       to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS copiado_en,
       -- Total esperado de filas: el CSV lleva su propio control para que la importacion
       -- detecte si se perdio alguna.
       count(*) OVER ()                         AS filas_copia
FROM producto p;
