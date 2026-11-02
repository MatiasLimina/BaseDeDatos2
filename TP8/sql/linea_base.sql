-- Linea base de food_store_copia: solo lectura. Se corre antes y despues de los casos
-- y la salida tiene que ser identica (salvo medido_en).
-- Uso (desde TP8/): PGCLIENTENCODING=UTF8 psql -X -w -h localhost -U postgres -d food_store_copia -v ON_ERROR_STOP=1 -At -f sql/linea_base.sql

-- Guarda: si se corre contra otra base (por ejemplo foodstore), la linea base no sirve.
-- \gset no imprime nada, asi que la salida con -At sigue siendo una medida por linea.
SELECT current_database() = 'food_store_copia' AS es_copia \gset
\if :es_copia
\else
  DO $$ BEGIN RAISE EXCEPTION 'linea_base: hay que correrla sobre food_store_copia'; END $$;
\endif

-- coalesce en cada columna: un NULL anularia la fila entera y string_agg la saltearia,
-- con lo que un cambio en esa fila no moveria la huella.
SELECT 'pedidos=' || count(*) FROM pedido
UNION ALL SELECT 'productos=' || count(*) FROM producto
UNION ALL SELECT 'suma_stock=' || sum(stock) FROM producto
UNION ALL SELECT 'huella_producto=' || md5(string_agg(
    id::text || '|' || coalesce(nombre, '') || '|' || coalesce(precio::text, '') || '|' ||
    coalesce(stock::text, '') || '|' || coalesce(activo::text, '') || '|' ||
    coalesce(categoria_id::text, ''), ',' ORDER BY id)) FROM producto
UNION ALL SELECT 'medido_en=' || now();
