-- sql/casos/preparar_c4.sql: prepara el caso C4 en food_store_copia.
-- Da de baja logica al producto C (id 3, Papas Fritas 150g) cambiando activo = false.
-- Solo se ejecuta sobre food_store_copia y verifica que se modifique exactamente 1 fila.
-- Uso: PGCLIENTENCODING=UTF8 psql -X -w -h localhost -U postgres -d food_store_copia -v ON_ERROR_STOP=1 -f sql/casos/preparar_c4.sql

SELECT current_database() = 'food_store_copia' AS es_copia \gset
\if :es_copia
\else
  DO $$ BEGIN RAISE EXCEPTION 'preparar_c4: solo se puede ejecutar sobre food_store_copia'; END $$;
\endif

\i sql/casos/productos_casos.sql

DO $$
DECLARE
  n int;
BEGIN
  UPDATE producto
  SET activo = false
  WHERE id = 3 AND activo = true;
  
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'preparar_c4: se esperaba dar de baja 1 fila con activo = true, se actualizaron %', n;
  END IF;
  
  RAISE NOTICE 'preparar_c4: OK (producto 3 dado de baja logica)';
END $$;
