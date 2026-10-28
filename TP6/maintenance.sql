-- =====================================================================
-- maintenance.sql — Revisión semanal de mantenimiento (SPEC_U6.md, Parte 3)
-- PostgreSQL 16 o superior.
--
-- Uso (la salida queda en logs/ como evidencia):
--   psql -X -w -h localhost -U postgres -d foodstore -v ON_ERROR_STOP=1 \
--        -f maintenance.sql -o logs/maintenance_AAAAMMDD.txt
--   Si se define la variable solo_revision (-v solo_revision=1; cualquier valor,
--   incluso 0, cuenta), muestra el plan sin ejecutar nada.
--   No usar -1/--single-transaction: VACUUM no puede correr en una transacción.
--
-- Qué hace:
--   1. Muestra la configuración de autovacuum.
--   2. Calcula, por tabla, los mismos umbrales que usa autovacuum (con los
--      valores por tabla de reloptions si los hay) y decide una acción:
--        VACUUM (ANALYZE)  si n_dead_tup supera el umbral de vacuum;
--        ANALYZE           si n_mod_since_analyze supera el umbral de analyze,
--                          o si la tabla tiene filas pero el planificador no
--                          tiene estadísticas (sin filas en pg_stats).
--   3. Ejecuta solo esas acciones, una por sentencia (\gexec).
--   4. Vuelve a mostrar el estado como evidencia.
--
-- Por qué una acción manual, si existe autovacuum:
--   - Una tabla chica que casi no cambia nunca alcanza el umbral de analyze
--     (50 filas + 10 %): categoria (3 filas) y la vista materializada quedan
--     sin estadísticas indefinidamente y el planificador usa valores por
--     defecto. Lo mismo pasa con todas las tablas de una base recién
--     restaurada, porque pg_restore no trae estadísticas.
--   - Si una tabla ya superó el umbral de vacuum, autovacuum la va a
--     procesar igual. Hacerlo en la ventana semanal evita que coincida con
--     el horario de uso.
--   Ambas acciones son seguras: VACUUM (sin FULL) y ANALYZE toman
--   SHARE UPDATE EXCLUSIVE, que no bloquea lecturas ni escrituras. La única
--   excepción es breve y no espera: al final, VACUUM puede tomar un bloqueo
--   exclusivo para devolver al sistema las páginas vacías del final de la
--   tabla, pero solo si lo consigue sin esperar. VACUUM FULL queda excluido:
--   reescribe toda la tabla con un bloqueo exclusivo y no corresponde como
--   tarea periódica.
-- =====================================================================

\set QUIET 1
\pset footer off
\pset null '-'
-- Las tablas bloqueadas por otra sesión se detectan en pg_locks y se saltean
-- (columna "bloqueada"). Si el bloqueo aparece justo entre la revisión y la
-- acción, la acción espera hasta 1 min y falla: con ON_ERROR_STOP el script
-- termina ahí con error (código 3) y las acciones siguientes quedan para la
-- próxima corrida.
SET lock_timeout = '1min';
\set QUIET 0

SELECT now()::timestamp(0) AS momento, current_database() AS base;

-- ---------------------------------------------------------------------
-- 1. Configuración de autovacuum
-- ---------------------------------------------------------------------
\qecho '== 1. Configuración de autovacuum'
SELECT name AS parametro, setting AS valor, unit AS unidad
FROM pg_settings
WHERE name IN ('autovacuum', 'track_counts', 'autovacuum_naptime',
               'autovacuum_vacuum_threshold', 'autovacuum_vacuum_scale_factor',
               'autovacuum_analyze_threshold', 'autovacuum_analyze_scale_factor')
ORDER BY name;

-- ---------------------------------------------------------------------
-- 2. Revisión por tabla. Es una vista temporal: desaparece al terminar la
--    sesión y permite repetir la misma revisión después de actuar.
-- ---------------------------------------------------------------------
\set QUIET 1
CREATE TEMP VIEW revision AS
WITH t AS (
    SELECT s.schemaname, s.relname, s.n_live_tup, s.n_dead_tup, s.n_mod_since_analyze,
           greatest(s.last_vacuum, s.last_autovacuum)   AS ultimo_vacuum,
           greatest(s.last_analyze, s.last_autoanalyze) AS ultimo_analyze,
           greatest(c.reltuples, 0) AS reltuples,  -- -1 = nunca vaciada ni analizada
           -- Otra sesión tiene (o espera) un bloqueo incompatible con VACUUM/ANALYZE:
           -- la tabla no se mide ni se toca y queda para la próxima revisión.
           EXISTS (SELECT 1 FROM pg_locks l
                   WHERE l.relation = c.oid AND l.pid <> pg_backend_pid()
                     AND l.mode IN ('ShareUpdateExclusiveLock', 'ShareLock',
                                    'ShareRowExclusiveLock', 'ExclusiveLock',
                                    'AccessExclusiveLock')) AS bloqueada,
           -- n_live_tup y reltuples no dicen si la tabla tiene filas cuando nunca
           -- se vació ni analizó (por ejemplo, en una base restaurada); el tamaño
           -- físico sí. pg_relation_size toma un bloqueo, así que solo se consulta
           -- si la tabla no está bloqueada (el CASE no evalúa la otra rama).
           CASE WHEN EXISTS (SELECT 1 FROM pg_locks l
                             WHERE l.relation = c.oid AND l.pid <> pg_backend_pid()
                               AND l.mode = 'AccessExclusiveLock')
                THEN NULL
                ELSE pg_relation_size(c.oid) > 0
           END AS tiene_datos,
           EXISTS (SELECT 1 FROM pg_stats p
                   WHERE p.schemaname = s.schemaname AND p.tablename = s.relname) AS tiene_estadisticas,
           -- Valor por tabla (ALTER TABLE ... SET) o, si no hay, el global.
           coalesce((SELECT option_value FROM pg_options_to_table(c.reloptions)
                     WHERE option_name = 'autovacuum_vacuum_threshold'),
                    current_setting('autovacuum_vacuum_threshold'))::numeric      AS v_umbral,
           coalesce((SELECT option_value FROM pg_options_to_table(c.reloptions)
                     WHERE option_name = 'autovacuum_vacuum_scale_factor'),
                    current_setting('autovacuum_vacuum_scale_factor'))::numeric   AS v_factor,
           coalesce((SELECT option_value FROM pg_options_to_table(c.reloptions)
                     WHERE option_name = 'autovacuum_analyze_threshold'),
                    current_setting('autovacuum_analyze_threshold'))::numeric     AS a_umbral,
           coalesce((SELECT option_value FROM pg_options_to_table(c.reloptions)
                     WHERE option_name = 'autovacuum_analyze_scale_factor'),
                    current_setting('autovacuum_analyze_scale_factor'))::numeric  AS a_factor
    FROM pg_stat_user_tables s
    JOIN pg_class c ON c.oid = s.relid
),
d AS (
    SELECT t.*,
           round(v_umbral + v_factor * reltuples) AS umbral_vacuum,
           round(a_umbral + a_factor * reltuples) AS umbral_analyze
    FROM t
)
SELECT schemaname, relname AS tabla, n_live_tup, n_dead_tup, umbral_vacuum,
       n_mod_since_analyze, umbral_analyze, tiene_estadisticas,
       ultimo_vacuum::timestamp(0) AS ultimo_vacuum,
       ultimo_analyze::timestamp(0) AS ultimo_analyze,
       CASE
           WHEN bloqueada THEN '-'
           WHEN n_dead_tup > umbral_vacuum THEN 'VACUUM (ANALYZE)'
           WHEN n_mod_since_analyze > umbral_analyze THEN 'ANALYZE'
           WHEN NOT tiene_estadisticas AND tiene_datos THEN 'ANALYZE'
           ELSE '-'
       END AS accion,
       CASE
           WHEN bloqueada
               THEN 'bloqueada por otra sesión: se revisa la próxima vez'
           WHEN n_dead_tup > umbral_vacuum
               THEN format('%s tuplas muertas > umbral %s', n_dead_tup, umbral_vacuum)
           WHEN n_mod_since_analyze > umbral_analyze
               THEN format('%s cambios desde el último analyze > umbral %s',
                           n_mod_since_analyze, umbral_analyze)
           WHEN NOT tiene_estadisticas AND tiene_datos
               THEN 'tiene filas y el planificador no tiene estadísticas'
           ELSE 'dentro de los umbrales'
       END AS motivo
FROM d;
\set QUIET 0

\qecho '== 2. Revisión (antes)'
SELECT tabla, n_live_tup, n_dead_tup, umbral_vacuum, n_mod_since_analyze, umbral_analyze,
       tiene_estadisticas, ultimo_vacuum, ultimo_analyze, accion, motivo
FROM revision
ORDER BY (accion = '-'), tabla;

\qecho '== 3. Acciones'
SELECT CASE WHEN count(*) = 0 THEN 'Sin acciones: todas las tablas están dentro de los umbrales.'
            ELSE count(*) || ' acción(es) a ejecutar' END AS resumen
FROM revision WHERE accion <> '-';

SELECT format('%s %I.%I', accion, schemaname, tabla) AS sentencia
FROM revision WHERE accion <> '-'
ORDER BY tabla;

\if :{?solo_revision}
\qecho 'solo_revision: no se ejecutó ninguna acción.'
\else
-- Cada fila se ejecuta como una sentencia aparte, fuera de transacción.
SELECT format('%s %I.%I', accion, schemaname, tabla)
FROM revision WHERE accion <> '-'
ORDER BY tabla
\gexec

-- Las estadísticas acumuladas se leen de una instantánea: se descarta para
-- ver el resultado de las acciones recién ejecutadas.
SELECT pg_stat_clear_snapshot() AS limpiar_instantanea \gset

\qecho '== 4. Revisión (después)'
SELECT tabla, n_live_tup, n_dead_tup, umbral_vacuum, n_mod_since_analyze, umbral_analyze,
       tiene_estadisticas, ultimo_vacuum, ultimo_analyze, accion
FROM revision
ORDER BY tabla;
\endif
