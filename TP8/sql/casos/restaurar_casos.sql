-- sql/casos/restaurar_casos.sql: restaura los productos modificados en food_store_copia.
-- Devuelve el producto A (id 1) a su precio original (2750.00) y el producto C (id 3)
-- a su estado activo (true). Es idempotente: puede ejecutarse multiples veces sin error.
-- Uso: PGCLIENTENCODING=UTF8 psql -X -w -h localhost -U postgres -d food_store_copia -v ON_ERROR_STOP=1 -f sql/casos/restaurar_casos.sql

SELECT current_database() = 'food_store_copia' AS es_copia \gset
\if :es_copia
\else
  DO $$ BEGIN RAISE EXCEPTION 'restaurar_casos: solo se puede ejecutar sobre food_store_copia'; END $$;
\endif

\i sql/casos/productos_casos.sql

DO $$
BEGIN
  -- Restaurar precio de Coca Cola 1.5L
  UPDATE producto
  SET precio = 2750.00
  WHERE id = 1;

  -- Restaurar activo de Papas Fritas 150g
  UPDATE producto
  SET activo = true
  WHERE id = 3;

  RAISE NOTICE 'restaurar_casos: OK (productos 1 y 3 restaurados a sus valores originales)';
END $$;
