-- =====================================================================
-- integrity_check.sql — Verificación semanal de integridad (SPEC_U6.md)
-- PostgreSQL 16 o superior, con la extensión amcheck (viene con el motor).
--
-- Uso (la salida queda en logs/ como evidencia):
--   psql -X -w -h localhost -U postgres -d foodstore -v ON_ERROR_STOP=1 \
--        -f integrity_check.sql -o logs/integrity_AAAAMMDD.txt
--
-- Qué verifica, en todas las tablas e índices del esquema public:
--   - Tablas (verify_heapam): que cada página y cada tupla del heap sean
--     legibles y coherentes (cabeceras, transacciones, TOAST).
--   - Índices B-tree (bt_index_check con heapallindexed): que el índice esté
--     bien ordenado y que cada fila de la tabla tenga su entrada en él.
--     Es lo que detecta un índice que "miente": una consulta que lo usa
--     devolvería resultados distintos de los de la tabla.
--
-- Única escritura: CREATE EXTENSION IF NOT EXISTS amcheck (idempotente; la
-- primera vez requiere superusuario). Lo demás solo lee.
--
-- Bloqueos: ambas funciones toman AccessShareLock, el mismo de un SELECT, así
-- que no frenan escrituras. Una tabla con un bloqueo exclusivo de otra sesión
-- no se espera (lock_timeout): se informa como OMITIDA y no cuenta como falla.
--
-- Resultado: una fila por objeto con OK, FALLA u OMITIDA. Si hay alguna
-- FALLA, el script termina con error (código distinto de 0 con ON_ERROR_STOP)
-- después de haber revisado todos los objetos.
-- =====================================================================

\set QUIET 1
\pset footer off
\pset null '-'
CREATE EXTENSION IF NOT EXISTS amcheck;
SET lock_timeout = '5s';
\set QUIET 0

SELECT now()::timestamp(0) AS momento, current_database() AS base;

-- Envoltorio que nunca corta la revisión: devuelve el resultado de un objeto
-- en lugar de abortar en la primera falla. Vive en pg_temp: desaparece al
-- cerrar la sesión y no deja nada en la base.
\set QUIET 1
CREATE FUNCTION pg_temp.revisar(objeto regclass, tipo text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    problemas bigint;
    primero   text;
BEGIN
    IF tipo = 'tabla' THEN
        SELECT count(*), min(format('bloque %s, tupla %s: %s', blkno, offnum, msg))
          INTO problemas, primero
          FROM verify_heapam(objeto);
        IF problemas > 0 THEN
            RETURN format('FALLA: %s problema(s); %s', problemas, primero);
        END IF;
    ELSE
        PERFORM bt_index_check(objeto, heapallindexed => true);
    END IF;
    RETURN 'OK';
EXCEPTION
    WHEN lock_not_available THEN
        RETURN 'OMITIDA: bloqueada por otra sesión';
    WHEN OTHERS THEN
        RETURN 'FALLA: ' || SQLERRM;
END;
$$;

CREATE TEMP TABLE resultado_integridad AS
SELECT c.relname::text AS objeto,
       'tabla'::text   AS tipo,
       '-'::text       AS tabla,
       pg_temp.revisar(c.oid, 'tabla') AS resultado
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'm')
UNION ALL
SELECT ci.relname::text, 'indice', ct.relname::text,
       pg_temp.revisar(ci.oid, 'indice')
FROM pg_index i
JOIN pg_class ci ON ci.oid = i.indexrelid
JOIN pg_class ct ON ct.oid = i.indrelid
JOIN pg_namespace n ON n.oid = ci.relnamespace
JOIN pg_am am ON am.oid = ci.relam
WHERE n.nspname = 'public' AND am.amname = 'btree' AND i.indisvalid;
\set QUIET 0

\qecho '== Integridad por objeto'
SELECT tipo, objeto, tabla, resultado
FROM resultado_integridad
ORDER BY resultado LIKE 'OK%', tipo DESC, objeto;

\qecho '== Resumen'
SELECT count(*) FILTER (WHERE resultado = 'OK')           AS ok,
       count(*) FILTER (WHERE resultado LIKE 'FALLA%')    AS fallas,
       count(*) FILTER (WHERE resultado LIKE 'OMITIDA%')  AS omitidas
FROM resultado_integridad;

SELECT count(*) > 0 AS hay_fallas
FROM resultado_integridad WHERE resultado LIKE 'FALLA%' \gset

\if :hay_fallas
    DO $$ BEGIN
        RAISE EXCEPTION 'integridad: hay objetos con FALLA (ver la tabla de arriba)';
    END $$;
\endif
