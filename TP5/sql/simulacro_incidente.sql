-- =====================================================================
-- Base de Datos II — Trabajo Práctico Unidad 5 (Food Store)
-- Archivo: sql/simulacro_incidente.sql
-- Propósito: Parte C.1/C.2 — simulacro controlado de acceso indebido,
--            EXCLUSIVAMENTE contra el entorno de desarrollo propio.
--
-- Escenario: la credencial de la aplicación (app_web) se filtró. Con ella
-- el atacante:
--   1. prueba claves contra una cuenta de Food Store con fn_autenticar
--      (5 fallidas y 1 exitosa),
--   2. intenta una lectura masiva de la tabla usuario,
--   3. intenta escalar: otorgarse admin_datos, asumir ese rol y promover
--      la cuenta comprometida a ADMIN.
-- Al final el DBA verifica si el escalamiento falló (C.2). Si no falló,
-- el script termina con ERROR "HALLAZGO": el esquema de la Parte A tiene
-- un defecto que hay que corregir antes de continuar.
--
-- Ejecución (como DBA superusuario, por TCP):
--   psql -h localhost -p <puerto> -U postgres -d <base> \
--        -f TP5/sql/simulacro_incidente.sql
--
-- Precondiciones: auditoria_config.sql aplicado, pg_hba.conf con
-- scram-sha-256 para la aplicación, usuario_autenticacion.sql y roles.sql
-- aplicados (fn_autenticar registra cada intento con RAISE LOG).
--
-- La clave de app_web se regenera al azar y no se registra en el log.
-- Los marcadores "TP5-C inicio/fin <id>" delimitan el fragmento a extraer.
-- =====================================================================

\set ON_ERROR_STOP 1

\set base :DBNAME
\set servidor :HOST
\set puerto :PORT
\set dba :USER

-- ---------------------------------------------------------------------
-- 0. PREPARACIÓN (DBA): clave efímera de app_web y estado inicial
-- ---------------------------------------------------------------------
SELECT to_char(clock_timestamp(), 'YYYYMMDD"T"HH24MISS') AS corrida,
       encode(gen_random_bytes(18), 'base64') AS clave
\gset

BEGIN;
SET LOCAL log_statement = 'none';   -- la clave no debe llegar al log
ALTER ROLE app_web PASSWORD :'clave';
COMMIT;

-- Cuenta víctima: una cuenta USUARIO activa de los datos sintéticos.
SELECT id AS victima_id, rol AS victima_rol_inicial
FROM usuario WHERE mail = 'cuenta7@foodstore.test'
\gset

SET tp5.corrida = :'corrida';
DO $$ BEGIN RAISE LOG 'TP5-C inicio %', current_setting('tp5.corrida'); END $$;

-- ---------------------------------------------------------------------
-- 1. ATACANTE: conexión con la credencial filtrada de app_web
-- ---------------------------------------------------------------------
\setenv PGPASSWORD :clave
\connect :base app_web :servidor :puerto

-- Los pasos del atacante fallan a propósito: no se detiene el script.
\set ON_ERROR_STOP 0

-- 1.a Fuerza bruta contra la cuenta víctima (diccionario corto).
SELECT * FROM fn_autenticar('cuenta7@foodstore.test', '123456');
SELECT * FROM fn_autenticar('cuenta7@foodstore.test', 'password');
SELECT * FROM fn_autenticar('cuenta7@foodstore.test', 'foodstore');
SELECT * FROM fn_autenticar('cuenta7@foodstore.test', 'FoodStore2026');
SELECT * FROM fn_autenticar('cuenta7@foodstore.test', 'FoodStore#2026');
-- 1.b Acierto: inicio de sesión exitoso en la aplicación.
SELECT * FROM fn_autenticar('cuenta7@foodstore.test', 'FoodStore#7');

-- ---------------------------------------------------------------------
-- 2. ATACANTE: lectura masiva de usuario
-- ---------------------------------------------------------------------
SELECT * FROM usuario;
SELECT id, nombre, apellido, mail, celular FROM usuario;

-- ---------------------------------------------------------------------
-- 3. ATACANTE: intento de escalamiento hacia admin_datos
-- ---------------------------------------------------------------------
GRANT admin_datos TO app_web;
SET ROLE admin_datos;
UPDATE usuario SET rol = 'ADMIN' WHERE mail = 'cuenta7@foodstore.test';

\set ON_ERROR_STOP 1

-- ---------------------------------------------------------------------
-- 4. VERIFICACIÓN (DBA): ¿el escalamiento falló? (C.2)
-- ---------------------------------------------------------------------
\setenv PGPASSWORD
\connect :base :dba :servidor :puerto

SELECT pg_has_role('app_web', 'admin_datos', 'MEMBER') AS app_web_es_admin_datos,
       (SELECT rol FROM usuario WHERE id = :victima_id) AS victima_rol_final,
       :'victima_rol_inicial' AS victima_rol_inicial
\gset

SET tp5.corrida = :'corrida';
SET tp5.es_admin = :'app_web_es_admin_datos';
SET tp5.rol_final = :'victima_rol_final';
SET tp5.rol_inicial = :'victima_rol_inicial';
DO $$
BEGIN
    IF current_setting('tp5.es_admin')::boolean
       OR current_setting('tp5.rol_final') <> current_setting('tp5.rol_inicial') THEN
        RAISE EXCEPTION 'HALLAZGO: el escalamiento NO falló (app_web miembro de admin_datos = %, rol de la víctima % -> %). Corregir roles.sql antes de continuar.',
            current_setting('tp5.es_admin'), current_setting('tp5.rol_inicial'),
            current_setting('tp5.rol_final');
    END IF;
    RAISE LOG 'TP5-C fin %', current_setting('tp5.corrida');
END
$$;

\echo 'simulacro_incidente: escalamiento rechazado; corrida' :corrida
