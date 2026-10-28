-- =====================================================================
-- Base de Datos II — Trabajo Práctico Unidad 5 (Food Store)
-- Archivo: sql/auditoria_test.sql
-- Propósito: Parte B.2 — secuencia breve de operaciones contra Food Store
--            para generar evidencia en el log del servidor: una lectura,
--            una inserción, una actualización y un inicio de sesión
--            fallido, con conexiones reales de app_web y admin_datos.
--
-- Ejecución (como DBA superusuario, conectado por TCP a la base):
--   psql -h localhost -p <puerto> -U postgres -d <base> \
--        -f TP5/sql/auditoria_test.sql
--
-- Precondiciones (sección 1, se verifican y el script aborta si faltan):
--   * sql/auditoria_config.sql aplicado (log_connections, log_disconnections,
--     log_statement = 'mod', log_line_prefix con usuario/base/host).
--   * pg_hba.conf exige scram-sha-256 a los roles de la aplicación por TCP
--     (con trust no existe un "login fallido" que registrar).
--   * sql/usuario_autenticacion.sql y sql/roles.sql aplicados.
--
-- Credenciales: la clave de app_web y admin_datos se genera al azar en
-- cada corrida y no se guarda en ningún archivo. El ALTER ROLE ... PASSWORD
-- se ejecuta con log_statement = 'none' para que la clave no quede en el
-- log (con 'mod' o 'ddl' el motor escribiría la sentencia completa).
--
-- Marcadores: RAISE LOG escribe "TP5-B inicio/fin <id de corrida>" en el
-- log para poder extraer exactamente el fragmento de esta corrida.
-- =====================================================================

\set ON_ERROR_STOP 1

-- Conexión de partida: se reutiliza para volver al DBA entre pasos.
\set base :DBNAME
\set servidor :HOST
\set puerto :PORT
\set dba :USER

-- ---------------------------------------------------------------------
-- 1. PRECONDICIONES
-- ---------------------------------------------------------------------
DO $$
BEGIN
    ASSERT current_setting('log_connections')::boolean,
        'log_connections debe estar activo (aplicar sql/auditoria_config.sql)';
    ASSERT current_setting('log_disconnections')::boolean,
        'log_disconnections debe estar activo';
    ASSERT current_setting('log_statement') IN ('mod', 'all'),
        'log_statement debe registrar al menos las modificaciones (mod)';
    ASSERT current_setting('log_line_prefix') LIKE '%\%u%'
       AND current_setting('log_line_prefix') LIKE '%\%d%'
       AND current_setting('log_line_prefix') LIKE '%\%h%',
        'log_line_prefix debe incluir usuario (%u), base (%d) y host (%h)';
    ASSERT EXISTS (
        SELECT 1 FROM pg_hba_file_rules
        WHERE type = 'host' AND 'all' = ANY (user_name)
          AND auth_method = 'scram-sha-256' AND error IS NULL
    ), 'pg_hba.conf debe exigir scram-sha-256 por TCP a los roles de la aplicación';
    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_hba_file_rules
        WHERE type = 'host' AND 'all' = ANY (user_name) AND auth_method = 'trust'
          AND NOT ('replication' = ANY (database))
    ), 'pg_hba.conf no debe tener reglas trust para todos los roles por TCP';
END
$$;

-- ---------------------------------------------------------------------
-- 2. PREPARACIÓN: id de corrida y claves efímeras
-- ---------------------------------------------------------------------
SELECT to_char(clock_timestamp(), 'YYYYMMDD"T"HH24MISS') AS corrida,
       encode(gen_random_bytes(18), 'base64') AS clave
\gset

BEGIN;
SET LOCAL log_statement = 'none';   -- la clave no debe llegar al log
ALTER ROLE app_web PASSWORD :'clave';
ALTER ROLE admin_datos PASSWORD :'clave';
COMMIT;

\setenv PGAPPNAME tp5_auditoria_test
-- psql no interpola variables dentro de $$...$$: el id viaja por un
-- parámetro de sesión.
SET tp5.corrida = :'corrida';
DO $$ BEGIN RAISE LOG 'TP5-B inicio %', current_setting('tp5.corrida'); END $$;

-- ---------------------------------------------------------------------
-- 3. LECTURA — app_web consulta el catálogo (vista)
-- ---------------------------------------------------------------------
\setenv PGPASSWORD :clave
\connect :base app_web :servidor :puerto

SELECT id, nombre, precio
FROM vw_productos_vigentes
ORDER BY id
LIMIT 3;

-- ---------------------------------------------------------------------
-- 4. INSERCIÓN — app_web da de alta un cliente (checkout)
-- ---------------------------------------------------------------------
-- Datos sintéticos: aun así, quedarán escritos en el log (ver informe).
INSERT INTO cliente (nombre, apellido, email, telefono)
VALUES ('Prueba', 'Auditoria', 'auditoria.' || :'corrida' || '@foodstore.test', '+54 261 555-0000')
RETURNING id AS cliente_id
\gset

-- ---------------------------------------------------------------------
-- 5. ACTUALIZACIÓN — admin_datos corrige el teléfono del cliente
-- ---------------------------------------------------------------------
\connect :base admin_datos :servidor :puerto

UPDATE cliente
   SET telefono = '+54 261 555-1111'
 WHERE id = :cliente_id;

-- ---------------------------------------------------------------------
-- 6. INICIO DE SESIÓN FALLIDO — app_web con una clave incorrecta
-- ---------------------------------------------------------------------
-- En modo no interactivo psql termina el script si un \connect falla, así
-- que el intento se hace desde un psql hijo (\!), que hereda la clave
-- incorrecta por variable de entorno; -w evita que pida una por teclado.
-- \! no interpola variables de psql: el destino también viaja por entorno.
\setenv PGHOST :servidor
\setenv PGPORT :puerto
\setenv PGDATABASE :base
\setenv PGPASSWORD clave_incorrecta
\! psql -X -w -U app_web -c "SELECT 1"

-- ---------------------------------------------------------------------
-- 7. CIERRE — vuelta al DBA y marcador final
-- ---------------------------------------------------------------------
\setenv PGPASSWORD
\connect :base :dba :servidor :puerto

SET tp5.corrida = :'corrida';
DO $$ BEGIN RAISE LOG 'TP5-B fin %', current_setting('tp5.corrida'); END $$;

\echo 'auditoria_test: secuencia ejecutada, corrida' :corrida
