-- =====================================================================
-- health_check.sql — Chequeo de salud diario (SPEC_U6.md, Parte 3)
-- PostgreSQL 16 o superior. Solo lectura: no modifica nada.
--
-- Uso (la salida queda en logs/ como evidencia):
--   psql -X -w -h localhost -U postgres -d foodstore -v ON_ERROR_STOP=1 \
--        -f health_check.sql -o logs/health_AAAAMMDD.txt
--
-- Usa current_database(), así que sirve igual sobre foodstore_restore_test.
--
-- Orden: primero lo que no toma bloqueos sobre las tablas (vistas pg_stat_*
-- y pg_database_size). Al final va el tamaño por tabla, porque
-- pg_total_relation_size toma un bloqueo sobre cada tabla y, si otra sesión
-- tiene una bloqueada, se queda esperando (probado). Por eso ese último
-- control corre con lock_timeout: ante un bloqueo, el chequeo termina con
-- error en vez de colgarse, y para entonces ya mostró quién bloquea a quién.
-- =====================================================================

\set QUIET 1
\pset footer off
\pset null '-'
\set QUIET 0

SELECT now()::timestamp(0) AS momento,
       current_database() AS base,
       current_setting('server_version') AS version,
       pg_size_pretty(pg_database_size(current_database())) AS tamano_base;

-- ---------------------------------------------------------------------
-- 1. Actividad de conexiones y transacciones
--    numbackends contra max_connections muestra cuánto margen queda.
--    Un aumento de rollbacks o deadlocks indica errores de la aplicación,
--    y un cache hit bajo indica que faltan memoria o índices.
--    Los contadores son acumulados desde stats_reset.
-- ---------------------------------------------------------------------
\qecho '== 1. Conexiones y transacciones'
SELECT d.numbackends AS conexiones,
       current_setting('max_connections')::int AS max_conexiones,
       d.xact_commit,
       d.xact_rollback,
       round(100.0 * d.xact_rollback / nullif(d.xact_commit + d.xact_rollback, 0), 2) AS pct_rollback,
       d.deadlocks,
       d.temp_files,
       pg_size_pretty(d.temp_bytes) AS temp_bytes,
       round(100.0 * d.blks_hit / nullif(d.blks_hit + d.blks_read, 0), 2) AS pct_cache_hit,
       d.stats_reset::timestamp(0) AS desde
FROM pg_stat_database d
WHERE d.datname = current_database();

SELECT coalesce(state, '(proceso interno)') AS estado, count(*) AS sesiones
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
GROUP BY state
ORDER BY sesiones DESC;

-- ---------------------------------------------------------------------
-- 2. Consultas activas y sesiones bloqueadas
--    Excluye la sesión propia. 'idle in transaction' también se lista,
--    porque retiene bloqueos e impide que VACUUM limpie tuplas.
-- ---------------------------------------------------------------------
\qecho '== 2. Consultas activas'
SELECT pid,
       usename AS usuario,
       state AS estado,
       date_trunc('second', now() - query_start) AS duracion,
       wait_event_type,
       left(regexp_replace(query, '\s+', ' ', 'g'), 70) AS consulta
FROM pg_stat_activity
WHERE datname = current_database()
  AND state <> 'idle'
  AND pid <> pg_backend_pid()
ORDER BY query_start;

\qecho '== 2b. Sesiones bloqueadas (y quién las bloquea)'
SELECT pid,
       pg_blocking_pids(pid) AS bloqueada_por,
       date_trunc('second', now() - query_start) AS esperando,
       left(regexp_replace(query, '\s+', ' ', 'g'), 70) AS consulta
FROM pg_stat_activity
WHERE datname = current_database()
  AND cardinality(pg_blocking_pids(pid)) > 0;

-- ---------------------------------------------------------------------
-- 3. Estado de las tablas: tuplas vivas y muertas, último vacuum/analyze
--    pct_muertas alto con un ultimo_vacuum viejo significa que autovacuum
--    no alcanza. Un ultimo_analyze vacío significa que el planificador no
--    tiene estadísticas. El detalle de umbrales está en maintenance.sql.
-- ---------------------------------------------------------------------
\qecho '== 3. Estado de tablas'
SELECT relname AS tabla,
       n_live_tup,
       n_dead_tup,
       round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) AS pct_muertas,
       greatest(last_vacuum, last_autovacuum)::timestamp(0)   AS ultimo_vacuum,
       greatest(last_analyze, last_autoanalyze)::timestamp(0) AS ultimo_analyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC, relname;

-- Distancia al límite de wraparound de XID: si se acerca a
-- autovacuum_freeze_max_age, autovacuum fuerza un VACUUM sobre toda la base.
SELECT age(datfrozenxid) AS edad_xid,
       current_setting('autovacuum_freeze_max_age')::bigint AS freeze_max_age,
       round(100.0 * age(datfrozenxid)
             / current_setting('autovacuum_freeze_max_age')::bigint, 2) AS pct_del_limite
FROM pg_database
WHERE datname = current_database();

-- ---------------------------------------------------------------------
-- 4. Tamaño de las tablas más grandes
--    Sirve para seguir el crecimiento y estimar el espacio de los respaldos.
--    Va al final y con lock_timeout (ver el encabezado).
-- ---------------------------------------------------------------------
\qecho '== 4. Tamaño por tabla'
\set QUIET 1
SET lock_timeout = '5s';
\set QUIET 0
SELECT c.relname AS tabla,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total,
       pg_size_pretty(pg_relation_size(c.oid))       AS datos,
       pg_size_pretty(pg_indexes_size(c.oid))        AS indices
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'm')
ORDER BY pg_total_relation_size(c.oid) DESC
LIMIT 10;
