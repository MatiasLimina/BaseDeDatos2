-- sql/casos/preparar_c2.sql: prepara el caso C2 en food_store_copia.
-- Sube el precio del producto A (id 1, Coca Cola 1.5L) de 2750.00 a 2990.00.
-- Solo se ejecuta sobre food_store_copia y verifica que se modifique exactamente 1 fila.
-- Uso: PGCLIENTENCODING=UTF8 psql -X -w -h localhost -U postgres -d food_store_copia -v ON_ERROR_STOP=1 -f sql/casos/preparar_c2.sql

SELECT current_database() = 'food_store_copia' AS es_copia \gset
\if :es_copia
\else
  DO $$ BEGIN RAISE EXCEPTION 'preparar_c2: solo se puede ejecutar sobre food_store_copia'; END $$;
\endif

\i sql/casos/productos_casos.sql

DO $$
DECLARE
  n int;
BEGIN
  UPDATE producto
  SET precio = 2990.00
  WHERE id = 1 AND precio = 2750.00;
  
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'preparar_c2: se esperaba actualizar 1 fila con precio 2750.00, se actualizaron %', n;
  END IF;
  
  RAISE NOTICE 'preparar_c2: OK (producto 1 actualizado a 2990.00)';
END $$;
