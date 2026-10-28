-- =====================================================================
-- Base de Datos II — Trabajo Práctico Unidad 5 (Food Store)
-- Archivo: sql/auditoria_config.sql
-- Propósito: Parte B.1 — activar la auditoría nativa del servidor de
--            desarrollo (Clase 1): conexiones, desconexiones y sentencias
--            de modificación, con un prefijo que diga quién, dónde y desde
--            dónde.
--
-- Ejecución (como superusuario):
--   psql -U postgres -d <base> -f TP5/sql/auditoria_config.sql
--   y luego reiniciar el servidor (logging_collector exige reinicio):
--   pg_ctl -D <datadir> restart
--
-- ALTER SYSTEM escribe en postgresql.auto.conf, que se aplica sobre
-- postgresql.conf. Para volver atrás: ALTER SYSTEM RESET <parámetro>.
--
-- pg_hba.conf no se modifica desde SQL: ver docs/informe_auditoria.md §1.2
-- (los roles de la aplicación deben autenticarse con scram-sha-256 para
-- que exista un "inicio de sesión fallido" que auditar).
-- =====================================================================

-- Quién se conecta y cuándo se va (con duración de la sesión).
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;

-- 'mod' = DDL + INSERT/UPDATE/DELETE/TRUNCATE/COPY FROM. No registra los
-- SELECT: es el nivel que pide la consigna y evita volcar al log cada
-- lectura de datos personales.
ALTER SYSTEM SET log_statement = 'mod';

-- El prefijo por defecto ('%m [%p] ') no identifica al usuario ni el
-- origen. Se agrega: usuario, base, aplicación, host de origen y el id
-- de sesión (para unir las líneas de una misma conexión).
ALTER SYSTEM SET log_line_prefix = '%m [%p] sesion=%c user=%u db=%d app=%a client=%h ';

-- Archivo de log propio del servidor, legible solo por su dueño (0600):
-- el log es un activo sensible (ver informe §4).
ALTER SYSTEM SET logging_collector = on;
ALTER SYSTEM SET log_directory = 'log';
ALTER SYSTEM SET log_filename = 'postgresql-%Y-%m-%d.log';
ALTER SYSTEM SET log_file_mode = '0600';

SELECT pg_reload_conf();

SELECT name, setting, pending_restart
FROM pg_settings
WHERE name IN ('log_connections', 'log_disconnections', 'log_statement',
               'log_line_prefix', 'logging_collector', 'log_directory',
               'log_filename', 'log_file_mode')
ORDER BY name;
