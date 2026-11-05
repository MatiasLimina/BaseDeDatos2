-- Exporta la instantanea (S) al CSV que importa la tablet.
-- Uso (desde TP8/): PGCLIENTENCODING=UTF8 psql -X -w -h localhost -U postgres -d food_store_copia -v ON_ERROR_STOP=1 -f sql/02_exportar_snapshot.sql
-- Solo lee food_store_copia; escribe movil/servidor_snapshot.csv (ruta relativa a TP8/).
DO $$
BEGIN
  IF current_database() <> 'food_store_copia' THEN
    RAISE EXCEPTION 'Base equivocada: % (solo food_store_copia)', current_database();
  END IF;
END $$;

\copy (SELECT * FROM v_snapshot_movil ORDER BY id) TO 'movil/servidor_snapshot.csv' CSV HEADER
