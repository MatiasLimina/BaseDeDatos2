-- =====================================================================
-- Base de Datos II — Trabajo Práctico Unidad 5 (Food Store)
-- Archivo: sql/roles.sql
-- Motor: PostgreSQL 16+
-- Propósito: esquema de roles, privilegios y hardening de rutinas
--            SECURITY DEFINER bajo el Principio de Mínimo Privilegio.
--
-- Precondiciones:
--   1. Ejecutar como superusuario o como dueño del esquema (DBA).
--   2. El esquema public ya contiene: categoria, producto, cliente,
--      pedido, pedido_detalle, usuario, las tres vistas, la vista
--      materializada mv_facturacion_categoria_mes y los procedimientos
--      sp_registrar_pedido / fn_autenticar / fn_resetear_password.
--      usuario y fn_autenticar se crean con sql/usuario_autenticacion.sql.
--   3. La extensión pgcrypto debe estar disponible (hash bcrypt).
--   4. Las contraseñas de los roles LOGIN NO se versionan: se crean
--      con PASSWORD NULL y se provisionan con \password o con un
--      gestor de secretos.
--   5. Los roles son objetos del clúster, no de una base. Si el clúster
--      aloja otras bases que usan estos roles, DROP ROLE fallará por
--      dependencias: ejecutar DROP OWNED BY <rol> en cada base o usar
--      un clúster dedicado a Food Store.
--   6. El rol legado rol_reportes_foodstore (creado en TP3 con una
--      contraseña en texto plano) NO se elimina automáticamente: se
--      documenta como hallazgo en docs/verificacion_permisos.md §5.6.
--      Evaluar DROP ROLE rol_reportes_foodstore o rotar su credencial.
--
-- Idempotencia:
--   El bloque 0 reasigna al DBA cualquier objeto que hubiera quedado
--   en propiedad de los roles de este script y luego los elimina.
--   Así el archivo puede ejecutarse varias veces sin borrar datos ni
--   objetos del esquema.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. LIMPIEZA IDEMPOTENTE DE ROLES
-- ---------------------------------------------------------------------
-- REASSIGN OWNED evita que DROP OWNED borre objetos si una ejecución
-- anterior (o el script de clase) dejó tablas/funciones a nombre de
-- estos roles. Los objetos se transfieren al DBA que ejecuta el script.
DO $$
DECLARE
    r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY[
        'app_web',
        'admin_datos',
        'rol_app_lectura',
        'rol_app_escritura',
        'rol_soporte',
        'rol_reportes',
        'rol_owner_codigo'
    ]
    LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('REASSIGN OWNED BY %I TO CURRENT_USER', r);
            EXECUTE format('DROP OWNED BY %I', r);
        END IF;
    END LOOP;
END
$$;

DROP ROLE IF EXISTS app_web;
DROP ROLE IF EXISTS admin_datos;
DROP ROLE IF EXISTS rol_app_lectura;
DROP ROLE IF EXISTS rol_app_escritura;
DROP ROLE IF EXISTS rol_soporte;
DROP ROLE IF EXISTS rol_reportes;
DROP ROLE IF EXISTS rol_owner_codigo;

-- ---------------------------------------------------------------------
-- 1. ROLES DE GRUPO (NOLOGIN) — sin credenciales, solo privilegios
-- ---------------------------------------------------------------------
-- Los cuatro roles de grupo representan funciones de negocio. No pueden
-- autenticarse: solo se activan por membresía o SET ROLE.
CREATE ROLE rol_app_lectura
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOREPLICATION NOBYPASSRLS;

CREATE ROLE rol_app_escritura
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOREPLICATION NOBYPASSRLS;

CREATE ROLE rol_soporte
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOREPLICATION NOBYPASSRLS;

CREATE ROLE rol_reportes
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOREPLICATION NOBYPASSRLS;

-- Rol técnico de propiedad de rutinas SECURITY DEFINER. No es un rol
-- de negocio ni tiene membresías: existe para que las funciones no se
-- ejecuten con los privilegios del superusuario que corrió el script.
CREATE ROLE rol_owner_codigo
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOREPLICATION NOBYPASSRLS;

-- ---------------------------------------------------------------------
-- 2. ROLES DE CONEXIÓN (LOGIN)
-- ---------------------------------------------------------------------
-- PASSWORD NULL: la credencial se asigna fuera del repositorio.
--   psql=# \password app_web
--   psql=# \password admin_datos
CREATE ROLE app_web
    LOGIN PASSWORD NULL
    NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOREPLICATION NOBYPASSRLS
    CONNECTION LIMIT 20;

CREATE ROLE admin_datos
    LOGIN PASSWORD NULL
    NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOREPLICATION NOBYPASSRLS
    CONNECTION LIMIT 5;

-- ---------------------------------------------------------------------
-- 3. ACCESO AL ESQUEMA
-- ---------------------------------------------------------------------
-- Sin USAGE en el esquema, ningún GRANT sobre objetos es efectivo.
-- Se revoca el USAGE implícito de PUBLIC para que solo los roles
-- explícitos puedan resolver nombres en public.
REVOKE ALL ON SCHEMA public FROM PUBLIC;

GRANT USAGE ON SCHEMA public
    TO rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes,
       rol_owner_codigo, app_web, admin_datos;

-- CREATE se concede temporalmente a rol_owner_codigo para poder
-- transferirle la propiedad de las rutinas y se revoca al final.
GRANT CREATE ON SCHEMA public TO rol_owner_codigo;

-- ---------------------------------------------------------------------
-- 4. PUNTO DE PARTIDA: REVOCAR PRIVILEGIOS HEREDADOS O DE PUBLIC
-- ---------------------------------------------------------------------
-- Las tablas de Food Store no deben ser accesibles por PUBLIC ni por
-- roles que solo necesitan vistas. Se revoca antes de otorgar.
REVOKE ALL ON TABLE
    public.categoria,
    public.producto,
    public.cliente,
    public.pedido,
    public.pedido_detalle,
    public.usuario
FROM PUBLIC;

REVOKE ALL ON TABLE
    public.vw_productos_vigentes,
    public.vw_pedidos_cliente,
    public.vw_detalle_pedido,
    public.mv_facturacion_categoria_mes
FROM PUBLIC;

REVOKE ALL ON SEQUENCE
    public.categoria_id_seq,
    public.producto_id_seq,
    public.cliente_id_seq,
    public.pedido_id_seq,
    public.usuario_id_seq
FROM PUBLIC;

-- Las funciones creadas por el usuario reciben EXECUTE de PUBLIC por
-- defecto en PostgreSQL. El REVOKE de cada rutina de Food Store se
-- ejecuta después de crearla/alterarla, más abajo, para que el script
-- también funcione en una base donde aún no exista.

-- fn_autenticar se endurece de forma genérica para no depender de su
-- firma exacta: se revoca PUBLIC y se permite solo a la aplicación.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'fn_autenticar'
    LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.sig);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO rol_app_lectura', r.sig);
    END LOOP;
END
$$;

-- ---------------------------------------------------------------------
-- 5. rol_app_lectura — catálogo y consulta de pedidos por vistas
-- ---------------------------------------------------------------------
-- Solo SELECT sobre las vistas. No hay acceso directo a las tablas
-- base, ni a usuario, ni a secuencias, ni a la vista materializada.
GRANT SELECT ON TABLE
    public.vw_productos_vigentes,
    public.vw_pedidos_cliente,
    public.vw_detalle_pedido
TO rol_app_lectura;

-- ---------------------------------------------------------------------
-- 6. rol_app_escritura — alta de clientes y registro de pedidos
-- ---------------------------------------------------------------------
-- Hereda la lectura de la aplicación.
GRANT rol_app_lectura TO rol_app_escritura;

-- El pedido se escribe exclusivamente a través del procedimiento
-- transaccional. No se otorga INSERT/UPDATE directo sobre pedido,
-- pedido_detalle ni producto.
GRANT EXECUTE ON PROCEDURE
    public.sp_registrar_pedido(BIGINT, forma_pago_enum, JSONB, BIGINT)
TO rol_app_escritura;

-- Única escritura directa de la aplicación: alta de cliente en el
-- checkout. Se limita a las columnas de negocio; id, activo y
-- created_at quedan bajo control de los DEFAULT/IDENTITY.
GRANT INSERT (nombre, apellido, email, telefono)
    ON TABLE public.cliente
    TO rol_app_escritura;

-- El alta devuelve el id generado (INSERT ... RETURNING id). RETURNING
-- exige SELECT sobre la columna devuelta; se limita a id, no a los
-- datos de contacto del cliente.
GRANT SELECT (id) ON TABLE public.cliente TO rol_app_escritura;

-- La columna id es GENERATED ALWAYS AS IDENTITY: para insertar sin
-- nombrarla, PostgreSQL exige USAGE sobre su secuencia. Se otorga
-- únicamente la secuencia de cliente, no todas las del esquema.
GRANT USAGE ON SEQUENCE public.cliente_id_seq TO rol_app_escritura;

-- ---------------------------------------------------------------------
-- 7. rol_soporte — atención al cliente y reset de contraseña
-- ---------------------------------------------------------------------
-- CASO OBLIGATORIO DE PERMISO A NIVEL DE COLUMNA:
-- SELECT solo sobre columnas identificativas/no sensibles de usuario.
-- La columna contrasena queda fuera del GRANT. Un SELECT * fallará
-- porque PostgreSQL exige privilegio sobre todas las columnas.
REVOKE ALL ON TABLE public.usuario FROM rol_soporte;

GRANT SELECT (id, nombre, apellido, mail, rol, activo, created_at)
    ON TABLE public.usuario
    TO rol_soporte;

-- Soporte ve pedidos y detalle sin email/teléfono del cliente: usa las
-- vistas seguras, no las tablas base.
GRANT SELECT ON TABLE
    public.vw_pedidos_cliente,
    public.vw_detalle_pedido
TO rol_soporte;

-- El reset de contraseña se hace por función acotada, no por UPDATE
-- directo sobre usuario. El GRANT EXECUTE se otorga en la sección 11,
-- después de crear la función.

-- ---------------------------------------------------------------------
-- 8. rol_reportes — lectura analítica sin datos personales
-- ---------------------------------------------------------------------
-- Vista materializada de facturación y detalle de pedidos (sin datos
-- del cliente). No se otorga vw_pedidos_cliente porque expone nombres.
GRANT SELECT ON TABLE
    public.mv_facturacion_categoria_mes,
    public.vw_detalle_pedido
TO rol_reportes;

-- ---------------------------------------------------------------------
-- 9. PRIVILEGIOS DEL ROL TÉCNICO PROPIETARIO DE RUTINAS
-- ---------------------------------------------------------------------
-- rol_owner_codigo no inicia sesión. Solo necesita lo que ejecutan
-- sp_registrar_pedido y fn_resetear_password.
GRANT SELECT (id, activo) ON TABLE public.usuario TO rol_owner_codigo;
GRANT UPDATE (contrasena) ON TABLE public.usuario TO rol_owner_codigo;

GRANT SELECT (id, activo) ON TABLE public.cliente TO rol_owner_codigo;

GRANT SELECT (id, nombre, precio, stock, activo)
    ON TABLE public.producto TO rol_owner_codigo;

-- SELECT ... FOR UPDATE sobre producto exige UPDATE a nivel de tabla,
-- no de columna. El rol es NOLOGIN y solo actúa dentro del procedimiento.
GRANT UPDATE ON TABLE public.producto TO rol_owner_codigo;

-- El procedimiento inserta la cabecera y hace RETURNING id.
GRANT SELECT (id) ON TABLE public.pedido TO rol_owner_codigo;
GRANT INSERT (fecha, forma_pago, cliente_id, created_at)
    ON TABLE public.pedido TO rol_owner_codigo;

GRANT INSERT (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
    ON TABLE public.pedido_detalle TO rol_owner_codigo;

GRANT USAGE ON SEQUENCE public.pedido_id_seq TO rol_owner_codigo;
GRANT USAGE ON TYPE public.forma_pago_enum TO rol_owner_codigo;

-- Funciones de pgcrypto usadas por fn_autenticar y fn_resetear_password.
-- La extensión las crea con EXECUTE para PUBLIC: cualquier rol podía
-- fabricar hashes bcrypt de una clave conocida (riesgo R10). Se cierran
-- y solo las ejecuta el rol técnico, dentro de las rutinas.
REVOKE EXECUTE ON FUNCTION
    public.crypt(TEXT, TEXT),
    public.gen_salt(TEXT),
    public.gen_salt(TEXT, INTEGER)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.crypt(TEXT, TEXT) TO rol_owner_codigo;
GRANT EXECUTE ON FUNCTION public.gen_salt(TEXT) TO rol_owner_codigo;

-- ---------------------------------------------------------------------
-- 10. HARDENING DE sp_registrar_pedido
-- ---------------------------------------------------------------------
-- El procedimiento pasa a SECURITY DEFINER para que app_web no necesite
-- DML directo sobre pedido/pedido_detalle/producto. La propiedad se
-- transfiere al rol técnico, nunca a un superusuario.
ALTER PROCEDURE public.sp_registrar_pedido(BIGINT, forma_pago_enum, JSONB, BIGINT)
    SECURITY DEFINER;

ALTER PROCEDURE public.sp_registrar_pedido(BIGINT, forma_pago_enum, JSONB, BIGINT)
    SET search_path = public, pg_temp;

REVOKE ALL ON PROCEDURE
    public.sp_registrar_pedido(BIGINT, forma_pago_enum, JSONB, BIGINT)
FROM PUBLIC;

GRANT EXECUTE ON PROCEDURE
    public.sp_registrar_pedido(BIGINT, forma_pago_enum, JSONB, BIGINT)
TO rol_app_escritura, admin_datos;

-- La transferencia de propiedad se hace al final, cuando ya se
-- otorgaron los privilegios: así el script también funciona si lo
-- ejecuta un dueño no superusuario que puede SET ROLE al propietario.
ALTER PROCEDURE public.sp_registrar_pedido(BIGINT, forma_pago_enum, JSONB, BIGINT)
    OWNER TO rol_owner_codigo;

-- ---------------------------------------------------------------------
-- 11. fn_resetear_password — SECURITY DEFINER endurecida
-- ---------------------------------------------------------------------
-- Requisitos de seguridad:
--   * SECURITY DEFINER: corre con los privilegios del propietario, no
--     del rol que la invoca.
--   * SET search_path = public, pg_temp: evita el ataque de suplantación
--     de esquema (schema shadowing) vía pg_temp u otros esquemas.
--   * REVOKE ALL FROM PUBLIC + GRANT EXECUTE solo a rol_soporte.
--   * El propietario solo puede leer id/activo y actualizar contrasena:
--     no puede leer el hash.
CREATE OR REPLACE FUNCTION public.fn_resetear_password(
    p_usuario_id BIGINT,
    p_nueva TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_filas INTEGER;
BEGIN
    IF p_usuario_id IS NULL THEN
        RAISE EXCEPTION 'El id de usuario no puede ser nulo.';
    END IF;

    IF p_nueva IS NULL OR btrim(p_nueva) = '' THEN
        RAISE EXCEPTION 'La nueva contraseña no puede ser nula ni vacía.';
    END IF;

    -- Defensa contra escalamiento vertical: soporte no puede resetear
    -- la contraseña de una cuenta ADMIN. El reset de administradores
    -- queda reservado al DBA. Si el dominio usa otra etiqueta para el
    -- rol administrador, ajustar el literal 'ADMIN'.
    UPDATE public.usuario
       SET contrasena = crypt(p_nueva, gen_salt('bf'))
     WHERE id = p_usuario_id
       AND activo = TRUE
       AND rol::text <> 'ADMIN';

    GET DIAGNOSTICS v_filas = ROW_COUNT;

    IF v_filas = 0 THEN
        RAISE EXCEPTION
            'No existe un usuario activo con id % o la cuenta es ADMIN y no puede resetearse por esta vía.',
            p_usuario_id;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_resetear_password(BIGINT, TEXT) FROM PUBLIC;

-- Solo soporte. admin_datos no la recibe: combinada con UPDATE (rol)
-- permitía degradar un ADMIN, resetearle la clave y volver a promoverlo
-- (riesgo R2, verificado en docs/verificacion_permisos.md §5.5).
GRANT EXECUTE ON FUNCTION public.fn_resetear_password(BIGINT, TEXT)
    TO rol_soporte;

ALTER FUNCTION public.fn_resetear_password(BIGINT, TEXT)
    OWNER TO rol_owner_codigo;

-- ---------------------------------------------------------------------
-- 11.b HARDENING DE fn_autenticar
-- ---------------------------------------------------------------------
-- fn_autenticar necesita leer el hash para comparar la credencial; si
-- quedara en manos de un propietario superusuario, una inyección en su
-- cuerpo tendría privilegios totales. Se transfiere al mismo rol técnico
-- NOLOGIN y se le concede solo las columnas que la autenticación usa.
GRANT SELECT (id, mail, contrasena, rol, activo)
    ON TABLE public.usuario TO rol_owner_codigo;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'fn_autenticar'
    LOOP
        EXECUTE format('ALTER FUNCTION %s SECURITY DEFINER', r.sig);
        EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', r.sig);
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.sig);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO rol_app_lectura', r.sig);
        EXECUTE format('ALTER FUNCTION %s OWNER TO rol_owner_codigo', r.sig);
    END LOOP;
END
$$;

-- ---------------------------------------------------------------------
-- 12. admin_datos — administración de datos sin DDL ni DELETE
-- ---------------------------------------------------------------------
-- DML explícito (sin GRANT ALL, sin TRUNCATE, sin DELETE físico):
-- la baja es lógica (activo = FALSE), según la regla R7 de Food Store.
GRANT SELECT, INSERT, UPDATE ON TABLE
    public.categoria,
    public.producto,
    public.cliente,
    public.pedido,
    public.pedido_detalle
TO admin_datos;

-- En usuario se aplica también mínimo privilegio por columna:
-- admin_datos administra los datos personales de las cuentas y su baja
-- lógica, pero no toca credenciales ni el rol de negocio (riesgo R2):
--   * Las altas nacen con rol = 'USUARIO' (DEFAULT) y contrasena NULL;
--     soporte las activa con fn_resetear_password.
--   * La promoción a ADMIN y el reset de cuentas ADMIN quedan para el DBA.
-- Puede leer rol para saber qué cuentas son administradoras.
GRANT SELECT (id, nombre, apellido, mail, celular, rol, activo, created_at)
    ON TABLE public.usuario TO admin_datos;

GRANT INSERT (nombre, apellido, mail, celular, activo)
    ON TABLE public.usuario TO admin_datos;

GRANT UPDATE (nombre, apellido, mail, celular, activo)
    ON TABLE public.usuario TO admin_datos;

-- Secuencias de las tablas que admin_datos inserta directamente.
GRANT USAGE, SELECT ON SEQUENCE
    public.categoria_id_seq,
    public.producto_id_seq,
    public.cliente_id_seq,
    public.pedido_id_seq,
    public.usuario_id_seq
TO admin_datos;

GRANT SELECT ON TABLE
    public.vw_productos_vigentes,
    public.vw_pedidos_cliente,
    public.vw_detalle_pedido,
    public.mv_facturacion_categoria_mes
TO admin_datos;

-- ---------------------------------------------------------------------
-- 13. MEMBRESÍAS DE CONEXIÓN
-- ---------------------------------------------------------------------
-- app_web hereda lectura + escritura. No se le concede ningún atributo
-- administrativo ni membresía en admin_datos/rol_soporte/rol_reportes.
GRANT rol_app_lectura, rol_app_escritura TO app_web;

-- ---------------------------------------------------------------------
-- 14. POLÍTICA PARA OBJETOS FUTUROS
-- ---------------------------------------------------------------------
-- Se ejecuta como dueño del esquema (CURRENT_USER). Si el dueño es otro
-- rol, reemplazar CURRENT_USER por el nombre del dueño.
--
-- No se otorgan privilegios automáticos a los roles de negocio: cada
-- tabla/vista/función nueva debe revisarse y recibir GRANT explícito.
-- Esto evita que una tabla futura sensible (por ejemplo usuario_anon
-- o una tabla de auditoría) quede expuesta por herencia.
--
-- Nota técnica: en PostgreSQL las tablas y secuencias NO reciben
-- privilegios de PUBLIC por defecto; el riesgo real está en las
-- funciones, que sí reciben EXECUTE de PUBLIC. Además, un REVOKE
-- "IN SCHEMA" solo puede agregar privilegios por esquema, no quitar
-- los globales: por eso el REVOKE de funciones/tipos va sin IN SCHEMA.
DO $$
BEGIN
    -- Tablas y secuencias futuras: política explícita y sin grants
    -- automáticos a los roles de grupo.
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC',
        CURRENT_USER
    );
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC',
        CURRENT_USER
    );

    -- Funciones y tipos futuros: quitar el privilegio global de PUBLIC.
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC',
        CURRENT_USER
    );
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I REVOKE USAGE ON TYPES FROM PUBLIC',
        CURRENT_USER
    );
END
$$;

-- ---------------------------------------------------------------------
-- 15. RETIRO DEL CREATE TEMPORAL
-- ---------------------------------------------------------------------
-- rol_owner_codigo ya es dueño de las rutinas; no necesita crear más
-- objetos. Se revoca el CREATE para que no pueda introducir código.
REVOKE CREATE ON SCHEMA public FROM rol_owner_codigo;

-- ---------------------------------------------------------------------
-- 16. DOCUMENTACIÓN EN EL CATÁLOGO
-- ---------------------------------------------------------------------
COMMENT ON ROLE rol_app_lectura IS
    'NOLOGIN: SELECT sobre vistas de catálogo y pedidos. Sin acceso a tablas base.';
COMMENT ON ROLE rol_app_escritura IS
    'NOLOGIN: alta de clientes y registro de pedidos vía sp_registrar_pedido. Sin UPDATE/DELETE directo.';
COMMENT ON ROLE rol_soporte IS
    'NOLOGIN: SELECT por columna sobre usuario (sin contrasena) y reset de password vía función.';
COMMENT ON ROLE rol_reportes IS
    'NOLOGIN: SELECT sobre mv_facturacion_categoria_mes y vw_detalle_pedido. Sin datos personales.';
COMMENT ON ROLE rol_owner_codigo IS
    'NOLOGIN técnico: propietario de rutinas SECURITY DEFINER con privilegios mínimos.';
COMMENT ON ROLE app_web IS
    'LOGIN de la aplicación: hereda rol_app_lectura y rol_app_escritura. Sin atributos administrativos.';
COMMENT ON ROLE admin_datos IS
    'LOGIN de administración de datos: DML explícito sin DELETE ni DDL; en usuario no escribe contrasena ni rol.';

DO $$
BEGIN
    RAISE NOTICE 'roles.sql aplicado: 4 roles de grupo, 1 rol técnico y 2 roles LOGIN.';
END
$$;
