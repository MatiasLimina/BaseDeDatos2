-- =====================================================================
-- Base de Datos II — Trabajo Práctico Unidad 5 (Food Store)
-- Archivo: sql/test_roles.sql
-- Propósito: pruebas de regresión de roles.sql. Cada bloque falla con
--            ERROR si el esquema de permisos se aparta de la
--            especificación de Kiro; si todo pasa, termina con
--            "test_roles: OK".
--
-- Ejecución (como DBA, después de usuario_autenticacion.sql y roles.sql):
--   psql -v ON_ERROR_STOP=1 -d <base> -f TP5/sql/test_roles.sql
--
-- Todo corre dentro de una transacción que se revierte: no deja datos.
-- =====================================================================

\set ON_ERROR_STOP 1
BEGIN;

-- ---------------------------------------------------------------------
-- 1. R2 — admin_datos no gestiona credenciales ni rol de negocio
-- ---------------------------------------------------------------------
DO $$
BEGIN
    ASSERT NOT has_column_privilege('admin_datos', 'public.usuario', 'rol', 'UPDATE'),
        'admin_datos no debe poder UPDATE usuario.rol';
    ASSERT NOT has_column_privilege('admin_datos', 'public.usuario', 'rol', 'INSERT'),
        'admin_datos no debe poder INSERT usuario.rol';
    ASSERT NOT has_column_privilege('admin_datos', 'public.usuario', 'contrasena', 'INSERT'),
        'admin_datos no debe poder INSERT usuario.contrasena';
    ASSERT NOT has_column_privilege('admin_datos', 'public.usuario', 'contrasena', 'UPDATE'),
        'admin_datos no debe poder UPDATE usuario.contrasena';
    ASSERT NOT has_function_privilege('admin_datos', 'public.fn_resetear_password(bigint,text)', 'EXECUTE'),
        'admin_datos no debe ejecutar fn_resetear_password';
    -- Lo que sí conserva: alta y edición de datos personales.
    ASSERT has_column_privilege('admin_datos', 'public.usuario', 'mail', 'INSERT'),
        'admin_datos debe poder dar de alta cuentas';
    ASSERT has_column_privilege('admin_datos', 'public.usuario', 'activo', 'UPDATE'),
        'admin_datos debe poder dar de baja lógica';
END
$$;

-- La cadena de escalamiento documentada en verificacion_permisos.md §5.5
-- debe cortarse en el primer paso.
DO $$
BEGIN
    SET LOCAL ROLE admin_datos;
    BEGIN
        UPDATE public.usuario SET rol = 'USUARIO' WHERE id = 1;
        RAISE EXCEPTION 'FALLA: admin_datos pudo degradar la cuenta ADMIN';
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;
    BEGIN
        PERFORM public.fn_resetear_password(2, 'ClaveConocida2026!');
        RAISE EXCEPTION 'FALLA: admin_datos pudo resetear una contraseña';
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;
    RESET ROLE;
END
$$;

-- Un alta hecha por admin_datos nace como USUARIO y sin credencial.
DO $$
DECLARE
    v_rol public.rol_usuario_enum;
    v_hash TEXT;
BEGIN
    SET LOCAL ROLE admin_datos;
    INSERT INTO public.usuario (nombre, apellido, mail)
    VALUES ('Test', 'Alta', 'test.alta@foodstore.test');
    RESET ROLE;

    SELECT rol, contrasena INTO v_rol, v_hash
    FROM public.usuario WHERE mail = 'test.alta@foodstore.test';
    ASSERT v_rol = 'USUARIO', 'el alta debe nacer con rol USUARIO';
    ASSERT v_hash IS NULL, 'el alta debe nacer sin credencial';
END
$$;

-- ---------------------------------------------------------------------
-- 2. R10 — crypt/gen_salt solo para el rol técnico
-- ---------------------------------------------------------------------
DO $$
DECLARE
    r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['app_web', 'admin_datos', 'rol_soporte', 'rol_reportes',
                             'rol_app_lectura', 'rol_app_escritura']
    LOOP
        ASSERT NOT has_function_privilege(r, 'public.crypt(text,text)', 'EXECUTE'),
            format('%s no debe ejecutar crypt', r);
        ASSERT NOT has_function_privilege(r, 'public.gen_salt(text)', 'EXECUTE'),
            format('%s no debe ejecutar gen_salt', r);
    END LOOP;
    ASSERT has_function_privilege('rol_owner_codigo', 'public.crypt(text,text)', 'EXECUTE'),
        'rol_owner_codigo necesita crypt para las rutinas';
END
$$;

-- Las rutinas elevadas llaman a pgcrypto con el esquema explícito
-- (auditoría A.4, propuesta 7): no dependen solo del search_path.
DO $$
DECLARE
    v_def TEXT;
BEGIN
    FOREACH v_def IN ARRAY ARRAY[
        pg_get_functiondef('public.fn_resetear_password(bigint,text)'::regprocedure),
        pg_get_functiondef('public.fn_autenticar(text,text)'::regprocedure)
    ]
    LOOP
        ASSERT v_def !~ '(?<![.\w])crypt\(',
            'las rutinas deben invocar public.crypt, no crypt sin esquema';
        ASSERT v_def !~ '(?<![.\w])gen_salt\(',
            'las rutinas deben invocar public.gen_salt, no gen_salt sin esquema';
    END LOOP;
END
$$;

-- ---------------------------------------------------------------------
-- 3. Regresión — lo que ya cumplía la primera versión
-- ---------------------------------------------------------------------
-- fn_autenticar sigue funcionando para la aplicación con crypt revocada.
DO $$
DECLARE
    v_ok INTEGER;
    v_mal INTEGER;
BEGIN
    SET LOCAL ROLE app_web;
    SELECT count(*) INTO v_ok  FROM public.fn_autenticar('cuenta2@foodstore.test', 'FoodStore#2');
    SELECT count(*) INTO v_mal FROM public.fn_autenticar('cuenta2@foodstore.test', 'incorrecta');
    RESET ROLE;
    ASSERT v_ok = 1,  'fn_autenticar debe aceptar la clave correcta';
    ASSERT v_mal = 0, 'fn_autenticar debe rechazar la clave incorrecta';
END
$$;

-- fn_autenticar deja en el log del servidor cada intento con su resultado
-- (Clase 1: auditar los inicios de sesión fallidos), nunca la clave, y
-- neutraliza los caracteres de control del mail para que no se puedan
-- falsificar líneas del log. Requiere logging_collector (auditoria_config.sql).
DO $$
DECLARE
    v_marca  TEXT := 'test' || to_char(clock_timestamp(), 'HH24MISSUS');
    -- Literal a propósito: si el servidor agregara la línea STATEMENT al
    -- registro, el texto de este bloque (con la clave) llegaría al log.
    v_clave  TEXT := 'ClaveLiteralQueNoDebeLoguearse';
    v_log    TEXT;
    v_inicio BIGINT;
BEGIN
    v_inicio := (pg_stat_file(pg_current_logfile())).size;

    PERFORM public.fn_autenticar(v_marca || '@foodstore.test', v_clave);
    PERFORM public.fn_autenticar('cuenta2@foodstore.test', 'FoodStore#2');
    PERFORM public.fn_autenticar(v_marca || E'\nFATAL:  falsa@foodstore.test', 'x');
    PERFORM pg_sleep(0.5);   -- el collector escribe de forma asíncrona

    v_log := pg_read_file(pg_current_logfile(), v_inicio,
                          (pg_stat_file(pg_current_logfile())).size - v_inicio);

    ASSERT v_log ~ ('fn_autenticar: intento fallido mail=' || v_marca || '@foodstore\.test'),
        'fn_autenticar debe registrar el intento fallido con el mail';
    ASSERT v_log ~ 'fn_autenticar: inicio de sesión exitoso usuario_id=2 ',
        'fn_autenticar debe registrar el inicio de sesión exitoso';
    ASSERT position(v_clave IN v_log) = 0,
        'la clave probada nunca debe llegar al log';
    -- PostgreSQL ya sangra las líneas de continuación con un tabulador,
    -- pero un parser ingenuo (grep "FATAL") las tomaría igual: el mail
    -- tiene que quedar en una sola línea, con el control reemplazado.
    ASSERT v_log ~ (v_marca || '\?FATAL:  falsa@'),
        'el salto de línea del mail debe registrarse reemplazado por ?';
    ASSERT v_log !~ (v_marca || E'\\n'),
        'un salto de línea en el mail no debe partir la línea del log';
END
$$;

-- Soporte resetea cuentas comunes pero no ADMIN, y no lee el hash.
DO $$
BEGIN
    ASSERT NOT has_column_privilege('rol_soporte', 'public.usuario', 'contrasena', 'SELECT'),
        'rol_soporte no debe leer contrasena';
    SET LOCAL ROLE rol_soporte;
    PERFORM public.fn_resetear_password(2, 'NuevaClave2026!');
    BEGIN
        PERFORM public.fn_resetear_password(1, 'NuevaClave2026!');
        RAISE EXCEPTION 'FALLA: rol_soporte pudo resetear una cuenta ADMIN';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FALLA:%' THEN RAISE; END IF;
    END;
    RESET ROLE;
END
$$;

-- Escalamiento por membresía: un rol de bajo privilegio no puede
-- otorgarse admin_datos (secuencia del simulacro de la Parte C).
DO $$
BEGIN
    SET LOCAL ROLE app_web;
    BEGIN
        GRANT admin_datos TO app_web;
        RAISE EXCEPTION 'FALLA: app_web pudo otorgarse admin_datos';
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;
    RESET ROLE;
END
$$;

-- Ningún rol del esquema tiene atributos administrativos.
DO $$
BEGIN
    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname IN ('rol_app_lectura', 'rol_app_escritura', 'rol_soporte', 'rol_reportes',
                          'rol_owner_codigo', 'app_web', 'admin_datos')
          AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolreplication OR rolbypassrls)
    ), 'ningún rol de Food Store debe tener atributos administrativos';
END
$$;

ROLLBACK;

\echo 'test_roles: OK'
