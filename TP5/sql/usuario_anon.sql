-- =====================================================================
-- Base de Datos II — Trabajo Práctico Unidad 5 (Food Store)
-- Archivo: sql/usuario_anon.sql
-- Propósito: Parte D.1 — copia anonimizada de usuario con datos sintéticos
--            deterministas (enmascaramiento estático, Clase 2 §5.3), para
--            desarrollo, pruebas y análisis sin exponer datos personales.
--
-- Ejecución (como DBA, después de sql/usuario_autenticacion.sql):
--   psql -v ON_ERROR_STOP=1 -d <base> -f TP5/sql/usuario_anon.sql
-- Verificación: sql/test_usuario_anon.sql
--
-- Criterio (igual que en clase, con baja lógica por activo en lugar de
-- eliminado, regla R7 del proyecto):
--   * nombre/apellido/mail se derivan del id: deterministas, únicos y sin
--     relación con la persona; preservan la cardinalidad y la selectividad
--     de los índices.
--   * celular se descarta (NULL) y contrasena pasa a un literal que no es
--     un hash bcrypt: ninguna clave puede validar contra la copia.
--   * id, rol, activo y created_at se conservan: son los atributos que el
--     análisis agregado necesita (Parte D.3).
-- Riesgo residual: id y created_at exactos permiten re-identificar a una
-- persona a quien además tenga acceso a usuario. La copia no debe salir
-- junto con la tabla real ni con datos que la vinculen (ver
-- docs/verificacion_equivalencia.md §4).
--
-- Idempotencia: se reconstruye completa en una transacción (refleja el
-- estado actual de usuario). No recibe GRANT: ALTER DEFAULT PRIVILEGES
-- (roles.sql §14) no otorga nada automáticamente y cualquier acceso debe
-- concederse explícitamente.
-- =====================================================================

BEGIN;

DROP TABLE IF EXISTS public.usuario_anon;

CREATE TABLE public.usuario_anon AS
SELECT
    id,
    'Usuario ' || id                  AS nombre,
    'Apellido ' || id                 AS apellido,
    'usuario' || id || '@ejemplo.test' AS mail,
    NULL::TEXT                        AS celular,
    'hash_no_valido'::TEXT            AS contrasena,
    rol,
    activo,
    created_at
FROM public.usuario;

ALTER TABLE public.usuario_anon ADD CONSTRAINT pk_usuario_anon PRIMARY KEY (id);

COMMENT ON TABLE public.usuario_anon IS
    'Copia anonimizada y determinista de usuario (TP5 Parte D). Sin datos personales ni credenciales.';

COMMIT;
