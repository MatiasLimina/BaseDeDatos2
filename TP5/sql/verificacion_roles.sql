-- =====================================================================
-- Base de Datos II — Trabajo Práctico Unidad 5 (Food Store)
-- Archivo: sql/verificacion_roles.sql
-- Motor: PostgreSQL 16+
-- Propósito: auditar que los roles creados por roles.sql tengan
--            exactamente los privilegios previstos (ni más ni menos).
--
-- Uso:
--   psql -h <host> -U <dba> -d <foodstore> \
--        -v ON_ERROR_STOP=1 -f sql/verificacion_roles.sql
--
-- Nota: information_schema.role_table_grants muestra privilegios
-- DIRECTOS de tabla/vista, no los heredados por membresía ni los
-- privilegios por columna. Por eso se complementa con
-- information_schema.column_privileges, has_table_privilege,
-- has_column_privilege y pg_default_acl.
-- =====================================================================

\pset pager off
\echo '=== 1. ATRIBUTOS DE LOS ROLES (LOGIN, SUPERUSER, CREATEROLE, etc.) ==='
SELECT
    rolname,
    rolcanlogin  AS puede_login,
    rolsuper     AS superuser,
    rolcreatedb  AS createdb,
    rolcreaterole AS createrole,
    rolreplication AS replication,
    rolbypassrls AS bypassrls,
    rolconnlimit AS connection_limit
FROM pg_roles
WHERE rolname IN (
    'rol_app_lectura', 'rol_app_escritura', 'rol_soporte', 'rol_reportes',
    'rol_owner_codigo', 'app_web', 'admin_datos'
)
ORDER BY rolname;

\echo '=== 2. MEMBRESÍAS (quién hereda qué rol) ==='
SELECT
    r.rolname  AS rol_otorgado,
    m.rolname  AS miembro,
    am.admin_option AS con_admin_option,
    am.inherit_option AS hereda_automaticamente
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE r.rolname IN (
    'rol_app_lectura', 'rol_app_escritura', 'rol_soporte', 'rol_reportes',
    'rol_owner_codigo', 'app_web', 'admin_datos'
)
OR m.rolname IN (
    'rol_app_lectura', 'rol_app_escritura', 'rol_soporte', 'rol_reportes',
    'rol_owner_codigo', 'app_web', 'admin_datos'
)
ORDER BY r.rolname, m.rolname;

\echo '=== 3. PRIVILEGIOS DIRECTOS DE TABLA/VISTA (information_schema) ==='
SELECT
    grantee,
    table_schema,
    table_name,
    privilege_type,
    is_grantable
FROM information_schema.role_table_grants
WHERE grantee IN (
    'rol_app_lectura', 'rol_app_escritura', 'rol_soporte', 'rol_reportes',
    'rol_owner_codigo', 'app_web', 'admin_datos'
)
ORDER BY grantee, table_name, privilege_type;

\echo '=== 4. PRIVILEGIOS POR COLUMNA SOBRE usuario ==='
SELECT
    grantee,
    table_name,
    column_name,
    privilege_type,
    is_grantable
FROM information_schema.column_privileges
WHERE grantee IN (
    'rol_app_lectura', 'rol_app_escritura', 'rol_soporte', 'rol_reportes',
    'rol_owner_codigo', 'app_web', 'admin_datos'
)
  AND table_name = 'usuario'
ORDER BY grantee, column_name, privilege_type;

\echo '=== 5. MATRIZ DE CHECKS CRÍTICOS (incluye herencia) ==='
SELECT
    has_table_privilege('rol_soporte', 'public.usuario', 'SELECT')
        AS soporte_select_tabla_usuario,
    has_column_privilege('rol_soporte', 'public.usuario', 'contrasena', 'SELECT')
        AS soporte_select_contrasena,
    has_column_privilege('rol_soporte', 'public.usuario', 'mail', 'SELECT')
        AS soporte_select_mail,
    has_table_privilege('rol_soporte', 'public.usuario', 'UPDATE')
        AS soporte_update_usuario,
    has_table_privilege('rol_app_lectura', 'public.producto', 'SELECT')
        AS lectura_select_producto,
    has_table_privilege('rol_app_lectura', 'public.vw_productos_vigentes', 'SELECT')
        AS lectura_select_vista,
    has_table_privilege('rol_app_escritura', 'public.pedido', 'INSERT')
        AS escritura_insert_pedido,
    has_table_privilege('rol_app_escritura', 'public.pedido', 'UPDATE')
        AS escritura_update_pedido,
    has_table_privilege('rol_app_escritura', 'public.pedido', 'DELETE')
        AS escritura_delete_pedido,
    has_column_privilege('rol_app_escritura', 'public.cliente', 'email', 'INSERT')
        AS escritura_insert_email_cliente,
    has_column_privilege('rol_app_escritura', 'public.cliente', 'id', 'SELECT')
        AS escritura_returning_id_cliente,
    has_sequence_privilege('rol_app_escritura', 'public.cliente_id_seq', 'USAGE')
        AS escritura_usage_seq_cliente,
    has_sequence_privilege('rol_app_escritura', 'public.pedido_id_seq', 'USAGE')
        AS escritura_usage_seq_pedido,
    has_table_privilege('admin_datos', 'public.pedido', 'DELETE')
        AS admin_delete_pedido,
    has_column_privilege('admin_datos', 'public.usuario', 'contrasena', 'SELECT')
        AS admin_select_contrasena,
    has_column_privilege('admin_datos', 'public.usuario', 'contrasena', 'UPDATE')
        AS admin_update_contrasena,
    has_column_privilege('rol_owner_codigo', 'public.usuario', 'contrasena', 'SELECT')
        AS owner_codigo_select_contrasena,
    has_table_privilege('rol_owner_codigo', 'public.usuario', 'SELECT')
        AS owner_codigo_select_tabla_usuario,
    has_table_privilege('rol_reportes', 'public.mv_facturacion_categoria_mes', 'SELECT')
        AS reportes_select_mv,
    has_table_privilege('rol_reportes', 'public.usuario', 'SELECT')
        AS reportes_select_usuario,
    has_table_privilege('app_web', 'public.vw_productos_vigentes', 'SELECT')
        AS app_web_hereda_lectura,
    has_table_privilege('app_web', 'public.usuario', 'SELECT')
        AS app_web_select_usuario;

\echo '=== 6. PROPIEDAD Y HARDENING DE RUTINAS ==='
SELECT
    n.nspname AS esquema,
    p.proname AS rutina,
    pg_get_function_identity_arguments(p.oid) AS argumentos,
    p.prosecdef AS security_definer,
    p.proconfig AS configuracion,
    pg_get_userbyid(p.proowner) AS propietario
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('fn_autenticar', 'fn_resetear_password', 'sp_registrar_pedido')
ORDER BY p.proname;

\echo '=== 6.b PRIVILEGIOS EFECTIVOS DE EJECUCIÓN DE RUTINAS ==='
SELECT
    r.rolname,
    has_function_privilege(
        r.rolname, 'public.fn_autenticar(text,text)', 'EXECUTE'
    ) AS fn_autenticar,
    has_function_privilege(
        r.rolname, 'public.fn_resetear_password(bigint,text)', 'EXECUTE'
    ) AS fn_resetear_password,
    has_function_privilege(
        r.rolname,
        'public.sp_registrar_pedido(bigint,forma_pago_enum,jsonb,bigint)',
        'EXECUTE'
    ) AS sp_registrar_pedido
FROM pg_roles r
WHERE r.rolname IN (
    'rol_app_lectura', 'rol_app_escritura', 'rol_soporte', 'rol_reportes',
    'rol_owner_codigo', 'app_web', 'admin_datos'
)
ORDER BY r.rolname;

\echo '=== 7. PRIVILEGIOS POR OMISIÓN (objetos futuros) ==='
SELECT
    pg_get_userbyid(d.defaclrole) AS propietario,
    n.nspname AS esquema,
    d.defaclobjtype AS tipo_objeto,
    d.defaclacl AS acl
FROM pg_default_acl d
LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
ORDER BY 1, 2, 3;

\echo '=== 8. \du (metacomando de psql; incluye todos los roles del clúster) ==='
\du
