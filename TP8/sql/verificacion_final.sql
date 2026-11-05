-- sql/verificacion_final.sql: verificacion final de food_store_copia tras los casos.
-- Emite exactamente las mismas metricas que sql/linea_base.sql para comparar diff.
-- Uso (desde TP8/): PGCLIENTENCODING=UTF8 psql -X -w -h localhost -U postgres -d food_store_copia -v ON_ERROR_STOP=1 -At -f sql/verificacion_final.sql > evidencias/verificacion_final.txt

SELECT current_database() = 'food_store_copia' AS es_copia \gset
\if :es_copia
\else
  DO $$ BEGIN RAISE EXCEPTION 'verificacion_final: hay que correrla sobre food_store_copia'; END $$;
\endif

SELECT 'pedidos=' || count(*) FROM pedido
UNION ALL SELECT 'productos=' || count(*) FROM producto
UNION ALL SELECT 'suma_stock=' || sum(stock) FROM producto
UNION ALL SELECT 'huella_producto=' || md5(string_agg(
    id::text || '|' || coalesce(nombre, '') || '|' || coalesce(precio::text, '') || '|' ||
    coalesce(stock::text, '') || '|' || coalesce(activo::text, '') || '|' ||
    coalesce(categoria_id::text, ''), ',' ORDER BY id)) FROM producto
UNION ALL SELECT 'medido_en=' || now();
