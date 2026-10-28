-- =====================================================================
-- Base de Datos II — Trabajo Práctico Unidad 5 (Food Store)
-- Archivo: sql/usuario_autenticacion.sql
-- Motor: PostgreSQL 16+
-- Propósito: reconstrucción de la tabla de cuentas `usuario` y de la
--            función `fn_autenticar` trabajadas en las Clases 1 y 2.
--            Es el paso previo a roles.sql que pide la consigna
--            ("si esos artefactos no se conservaron ... reconstruirlos").
--
-- Precondiciones:
--   1. Base de Food Store armada con Proyecto_Integrador/database/
--      (schema, seed, procedures, views, materializadas, ...).
--   2. Ejecutar como superusuario o como dueño del esquema (DBA).
--
-- ATENCIÓN: Proyecto_Integrador/database/tp4_fnbc_control_lote.sql crea
-- OTRA tabla `usuario` (responsables de depósito) y la limpia con
-- DROP TABLE usuario CASCADE. No ejecutar ese script en la base del TP5.
--
-- Diferencias con el material de clase (decisiones del equipo):
--   * Baja lógica con `activo` (regla R7 del proyecto) en lugar de
--     `eliminado`, igual que el resto de las tablas de Food Store.
--   * `contrasena` admite NULL: una cuenta recién dada de alta queda
--     sin credencial hasta que soporte la activa con fn_resetear_password.
--     Así admin_datos puede dar altas sin escribir hashes (ver roles.sql).
--   * fn_autenticar se escribe en SQL parametrizado (sin EXECUTE de
--     cadenas): es la mitigación de inyección vista en la Clase 2.
--
-- Idempotencia: CREATE ... IF NOT EXISTS y ON CONFLICT DO NOTHING; no
-- borra datos. roles.sql endurece después la función (SECURITY DEFINER,
-- propietario técnico, REVOKE de PUBLIC).
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------
-- 1. TIPO DE ROL DE NEGOCIO
-- ---------------------------------------------------------------------
-- Dominio cerrado: rige qué pantallas ve la aplicación. No confundir con
-- los roles del motor (rol_app_lectura, admin_datos, ...).
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'rol_usuario_enum') THEN
        CREATE TYPE rol_usuario_enum AS ENUM ('ADMIN', 'USUARIO');
    END IF;
END
$$;

-- ---------------------------------------------------------------------
-- 2. TABLA usuario (cuentas de acceso a la aplicación)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuario (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre      VARCHAR(60)  NOT NULL,                       -- participación total: toda cuenta identifica a una persona
    apellido    VARCHAR(60)  NOT NULL,
    mail        VARCHAR(120) NOT NULL,                       -- credencial de login: obligatoria
    celular     VARCHAR(30),                                 -- dato de contacto opcional
    contrasena  VARCHAR(100),                                -- hash bcrypt; NULL = cuenta pendiente de activación
    rol         rol_usuario_enum NOT NULL DEFAULT 'USUARIO', -- toda alta nace sin privilegios de negocio
    activo      BOOLEAN NOT NULL DEFAULT TRUE,               -- baja lógica (R7), sin borrado físico
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_usuario_mail             UNIQUE (mail),    -- un mail, una cuenta
    CONSTRAINT ck_usuario_nombre_no_vacio   CHECK (btrim(nombre)   <> ''),
    CONSTRAINT ck_usuario_apellido_no_vacio CHECK (btrim(apellido) <> ''),
    CONSTRAINT ck_usuario_mail_formato      CHECK (mail ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    -- Solo se guardan hashes bcrypt ($2a$/$2b$...), nunca texto plano.
    CONSTRAINT ck_usuario_contrasena_hash   CHECK (contrasena IS NULL OR contrasena ~ '^\$2[abxy]\$')
);

COMMENT ON TABLE usuario IS
    'Cuentas de la aplicación Food Store (Unidad 5). contrasena guarda hash bcrypt; NULL = pendiente de activación.';

-- ---------------------------------------------------------------------
-- 3. DATOS SINTÉTICOS DE DESARROLLO
-- ---------------------------------------------------------------------
-- 30 cuentas deterministas: la 1 es ADMIN, cada quinta cuenta está dada
-- de baja, y las altas se reparten semanalmente desde enero de 2026
-- (sirve a la Parte D: conteos por rol y mes de alta).
-- Las claves son de prueba ('FoodStore#<id>'); no son credenciales reales.
INSERT INTO usuario (nombre, apellido, mail, celular, contrasena, rol, activo, created_at)
SELECT
    (ARRAY['Ana','Bruno','Carla','Diego','Elena','Facundo','Gabriela','Hernán','Inés','Julián'])[1 + (i - 1) % 10],
    (ARRAY['Gómez','Pérez','Rodríguez','Fernández','López','Martínez','Sosa','Díaz'])[1 + (i - 1) % 8],
    'cuenta' || i || '@foodstore.test',
    '+54 9 261 555-' || lpad(i::text, 4, '0'),
    crypt('FoodStore#' || i, gen_salt('bf')),
    CASE WHEN i = 1 THEN 'ADMIN' ELSE 'USUARIO' END::rol_usuario_enum,
    i % 5 <> 0,
    timestamptz '2026-01-05 09:00:00-03' + (i - 1) * interval '7 days'
FROM generate_series(1, 30) AS g(i)
ON CONFLICT (mail) DO NOTHING;

-- ---------------------------------------------------------------------
-- 4. fn_autenticar — verificación parametrizada de credenciales
-- ---------------------------------------------------------------------
-- Devuelve la cuenta autenticada o ninguna fila. No distingue "mail
-- inexistente" de "clave incorrecta" para no permitir enumerar cuentas.
-- La comparación usa el hash guardado como sal: crypt(clave, hash) = hash.
CREATE OR REPLACE FUNCTION public.fn_autenticar(
    p_mail TEXT,
    p_password TEXT
)
RETURNS TABLE (usuario_id BIGINT, rol rol_usuario_enum)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT u.id, u.rol
    FROM public.usuario u
    WHERE u.mail = lower(btrim(p_mail))
      AND u.activo
      AND u.contrasena IS NOT NULL
      AND u.contrasena = public.crypt(p_password, u.contrasena);
$$;

COMMENT ON FUNCTION public.fn_autenticar(TEXT, TEXT) IS
    'Autenticación por mail y clave. Sin SQL dinámico. roles.sql la pasa a SECURITY DEFINER con dueño rol_owner_codigo.';
