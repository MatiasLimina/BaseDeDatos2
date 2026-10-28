-- =====================================================================
-- Base de Datos II — Trabajo Práctico Unidad 5 (Food Store)
-- Archivo: sql/test_usuario_anon.sql
-- Propósito: Parte D — verificar que usuario_anon es efectiva (no conserva
--            ningún dato personal ni credencial de usuario) y que conserva
--            lo que el análisis necesita (cardinalidad, rol, estado y
--            fecha de alta). Termina con "test_usuario_anon: OK".
--
-- Ejecución (como DBA, después de sql/usuario_anon.sql):
--   psql -v ON_ERROR_STOP=1 -d <base> -f TP5/sql/test_usuario_anon.sql
-- =====================================================================

\set ON_ERROR_STOP 1

DO $$
BEGIN
    ASSERT to_regclass('public.usuario_anon') IS NOT NULL,
        'usuario_anon debe existir (aplicar sql/usuario_anon.sql)';
END
$$;

-- 1. Efectividad: ningún dato personal real sobrevive.
DO $$
BEGIN
    ASSERT NOT EXISTS (SELECT 1 FROM usuario_anon a JOIN usuario u ON u.mail = a.mail),
        'usuario_anon no debe contener ningún mail real';
    ASSERT NOT EXISTS (SELECT 1 FROM usuario_anon a JOIN usuario u
                       ON u.nombre = a.nombre OR u.apellido = a.apellido),
        'usuario_anon no debe contener nombres ni apellidos reales';
    ASSERT NOT EXISTS (SELECT 1 FROM usuario_anon WHERE celular IS NOT NULL),
        'usuario_anon no debe contener celulares';
    ASSERT NOT EXISTS (SELECT 1 FROM usuario_anon a JOIN usuario u
                       ON u.contrasena = a.contrasena),
        'usuario_anon no debe contener ningún hash real';
    -- El valor sustituto no es un hash bcrypt: ninguna clave lo valida.
    ASSERT NOT EXISTS (SELECT 1 FROM usuario_anon WHERE contrasena ~ '^\$2[abxy]\$'),
        'la contraseña de usuario_anon no debe ser un hash utilizable';
END
$$;

-- 2. Determinismo y utilidad: misma cardinalidad, mismo id, rol, estado
--    y fecha de alta; valores sintéticos derivados del id.
DO $$
BEGIN
    ASSERT (SELECT count(*) FROM usuario_anon) = (SELECT count(*) FROM usuario),
        'usuario_anon debe tener las mismas filas que usuario';
    ASSERT NOT EXISTS (
        SELECT id, rol, activo, created_at FROM usuario
        EXCEPT
        SELECT id, rol, activo, created_at FROM usuario_anon
    ), 'usuario_anon debe conservar id, rol, activo y created_at de cada cuenta';
    ASSERT NOT EXISTS (
        SELECT 1 FROM usuario_anon
        WHERE mail <> 'usuario' || id || '@ejemplo.test'
           OR nombre <> 'Usuario ' || id
           OR apellido <> 'Apellido ' || id
    ), 'los valores sintéticos deben derivarse del id (patrón de la Clase 2)';
    ASSERT (SELECT count(DISTINCT mail) FROM usuario_anon) = (SELECT count(*) FROM usuario_anon),
        'los mails sintéticos deben ser únicos (preservan la selectividad del índice)';
END
$$;

-- 3. Exposición: la tabla anonimizada no queda abierta a los roles de la
--    aplicación (ALTER DEFAULT PRIVILEGES no otorga nada automáticamente).
DO $$
DECLARE
    r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['app_web', 'admin_datos', 'rol_soporte', 'rol_reportes']
    LOOP
        ASSERT NOT has_table_privilege(r, 'public.usuario_anon', 'SELECT'),
            format('%s no debe leer usuario_anon sin un GRANT revisado', r);
    END LOOP;
END
$$;

\echo 'test_usuario_anon: OK'
