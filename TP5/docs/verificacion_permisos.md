# Verificación de permisos — Food Store (Unidad 5, Parte A)

## 1. Propósito

Este informe demuestra que el esquema creado por `TP5/sql/roles.sql` otorga **exactamente** los privilegios definidos en la especificación de Kiro (`TP5/docs/kiro_roles_spec/requirements.md` y `design.md`), ni más ni menos. Se auditan atributos, membresías, privilegios directos, privilegios por columna, privilegios efectivos (incluida la herencia), hardening de rutinas y política para objetos futuros.

## 2. Entorno de la captura

| Dato | Valor |
|---|---|
| Motor | PostgreSQL 17 (compatible con el mínimo exigido: 16+) |
| Clúster | Aislado, puerto `55432`, autenticación `trust` |
| Base | `foodstore_tp5` |
| Esquema | `public` armado con `Proyecto_Integrador/database/` (`schema`, `seed`, `procedures`, `views`, `indices_parciales_soft_delete`, `materializadas`, `generar_registros_adaptado`, `triggers`) más `TP5/sql/usuario_autenticacion.sql` |
| Script aplicado | `TP5/sql/roles.sql` (dos ejecuciones consecutivas para probar idempotencia) |
| Script de auditoría | `TP5/sql/verificacion_roles.sql` |
| Pruebas de regresión | `TP5/sql/test_roles.sql` (termina con `test_roles: OK`) |

La salida se capturó con:

```bash
psql -h localhost -p 55432 -U postgres -d foodstore_tp5 \
     -v ON_ERROR_STOP=1 -f TP5/sql/verificacion_roles.sql \
     > TP5/docs/verificacion_roles_salida.txt 2>&1
```

> **Recaptura (corrección de R2 y R10):** esta salida reemplaza a la primera captura (base `foodstore_fresh`), hecha antes de corregir los riesgos R2 y R10. Respecto de aquella, desaparecen las filas `admin_datos | usuario | contrasena | INSERT`, `rol | INSERT` y `rol | UPDATE` del bloque 4, `fn_resetear_password` pasa a `f` para `admin_datos` en el bloque 6.b y se agrega el bloque 6.c. La consola de Windows desfigura dos mensajes propios de psql (`usará`, `Replicación`), que se corrigieron a mano; los datos que devuelve el servidor no se tocaron.

> **Nota:** la captura se hizo sobre un clúster de prueba aislado, no sobre la base de desarrollo del equipo. Los valores de datos cambian; los privilegios y atributos no. La salida se conserva completa para que cualquier persona pueda reproducirla con el mismo script.

## 3. Consultas de auditoría

El archivo `TP5/sql/verificacion_roles.sql` contiene ocho bloques. Los más relevantes para la consigna son:

### 3.1 `information_schema.role_table_grants` (privilegios directos de tabla/vista)

```sql
SELECT grantee, table_schema, table_name, privilege_type, is_grantable
FROM information_schema.role_table_grants
WHERE grantee IN (
    'rol_app_lectura', 'rol_app_escritura', 'rol_soporte', 'rol_reportes',
    'rol_owner_codigo', 'app_web', 'admin_datos'
)
ORDER BY grantee, table_name, privilege_type;
```

### 3.2 `information_schema.column_privileges` (caso obligatorio sobre `usuario`)

```sql
SELECT grantee, table_name, column_name, privilege_type, is_grantable
FROM information_schema.column_privileges
WHERE grantee IN (
    'rol_app_lectura', 'rol_app_escritura', 'rol_soporte', 'rol_reportes',
    'rol_owner_codigo', 'app_web', 'admin_datos'
)
  AND table_name = 'usuario'
ORDER BY grantee, column_name, privilege_type;
```

### 3.3 Matriz de privilegios efectivos (incluye herencia)

```sql
SELECT
    has_column_privilege('rol_soporte', 'public.usuario', 'contrasena', 'SELECT')
        AS soporte_select_contrasena,
    has_column_privilege('rol_soporte', 'public.usuario', 'mail', 'SELECT')
        AS soporte_select_mail,
    has_table_privilege('rol_app_escritura', 'public.pedido', 'UPDATE')
        AS escritura_update_pedido,
    has_table_privilege('rol_app_escritura', 'public.pedido', 'DELETE')
        AS escritura_delete_pedido,
    has_table_privilege('admin_datos', 'public.pedido', 'DELETE')
        AS admin_delete_pedido,
    has_column_privilege('admin_datos', 'public.usuario', 'contrasena', 'SELECT')
        AS admin_select_contrasena,
    has_column_privilege('admin_datos', 'public.usuario', 'contrasena', 'UPDATE')
        AS admin_update_contrasena,
    has_table_privilege('rol_reportes', 'public.mv_facturacion_categoria_mes', 'SELECT')
        AS reportes_select_mv,
    has_table_privilege('rol_reportes', 'public.usuario', 'SELECT')
        AS reportes_select_usuario,
    has_table_privilege('app_web', 'public.usuario', 'SELECT')
        AS app_web_select_usuario;
```

### 3.4 Hardening de rutinas

```sql
SELECT n.nspname, p.proname,
       pg_get_function_identity_arguments(p.oid) AS argumentos,
       p.prosecdef AS security_definer,
       p.proconfig AS configuracion,
       pg_get_userbyid(p.proowner) AS propietario
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('fn_autenticar', 'fn_resetear_password', 'sp_registrar_pedido')
ORDER BY p.proname;
```

### 3.5 `\du`

```text
\du
```

## 4. Salida completa de la verificación

La misma salida se conserva como archivo plano en `TP5/docs/verificacion_roles_salida.txt`, listo para adjuntar a la entrega.

```text
El paginador no se usará.
=== 1. ATRIBUTOS DE LOS ROLES (LOGIN, SUPERUSER, CREATEROLE, etc.) ===
      rolname      | puede_login | superuser | createdb | createrole | replication | bypassrls | connection_limit 
-------------------+-------------+-----------+----------+------------+-------------+-----------+------------------
 admin_datos       | t           | f         | f        | f          | f           | f         |                5
 app_web           | t           | f         | f        | f          | f           | f         |               20
 rol_app_escritura | f           | f         | f        | f          | f           | f         |               -1
 rol_app_lectura   | f           | f         | f        | f          | f           | f         |               -1
 rol_owner_codigo  | f           | f         | f        | f          | f           | f         |               -1
 rol_reportes      | f           | f         | f        | f          | f           | f         |               -1
 rol_soporte       | f           | f         | f        | f          | f           | f         |               -1
(7 filas)

=== 2. MEMBRESÍAS (quién hereda qué rol) ===
   rol_otorgado    |      miembro      | con_admin_option | hereda_automaticamente 
-------------------+-------------------+------------------+------------------------
 rol_app_escritura | app_web           | f                | t
 rol_app_lectura   | app_web           | f                | t
 rol_app_lectura   | rol_app_escritura | f                | t
(3 filas)

=== 3. PRIVILEGIOS DIRECTOS DE TABLA/VISTA (information_schema) ===
     grantee      | table_schema |      table_name       | privilege_type | is_grantable 
------------------+--------------+-----------------------+----------------+--------------
 admin_datos      | public       | categoria             | INSERT         | NO
 admin_datos      | public       | categoria             | SELECT         | NO
 admin_datos      | public       | categoria             | UPDATE         | NO
 admin_datos      | public       | cliente               | INSERT         | NO
 admin_datos      | public       | cliente               | SELECT         | NO
 admin_datos      | public       | cliente               | UPDATE         | NO
 admin_datos      | public       | pedido                | INSERT         | NO
 admin_datos      | public       | pedido                | SELECT         | NO
 admin_datos      | public       | pedido                | UPDATE         | NO
 admin_datos      | public       | pedido_detalle        | INSERT         | NO
 admin_datos      | public       | pedido_detalle        | SELECT         | NO
 admin_datos      | public       | pedido_detalle        | UPDATE         | NO
 admin_datos      | public       | producto              | INSERT         | NO
 admin_datos      | public       | producto              | SELECT         | NO
 admin_datos      | public       | producto              | UPDATE         | NO
 admin_datos      | public       | vw_detalle_pedido     | SELECT         | NO
 admin_datos      | public       | vw_pedidos_cliente    | SELECT         | NO
 admin_datos      | public       | vw_productos_vigentes | SELECT         | NO
 rol_app_lectura  | public       | vw_detalle_pedido     | SELECT         | NO
 rol_app_lectura  | public       | vw_pedidos_cliente    | SELECT         | NO
 rol_app_lectura  | public       | vw_productos_vigentes | SELECT         | NO
 rol_owner_codigo | public       | producto              | UPDATE         | NO
 rol_reportes     | public       | vw_detalle_pedido     | SELECT         | NO
 rol_soporte      | public       | vw_detalle_pedido     | SELECT         | NO
 rol_soporte      | public       | vw_pedidos_cliente    | SELECT         | NO
(25 filas)

=== 4. PRIVILEGIOS POR COLUMNA SOBRE usuario ===
     grantee      | table_name | column_name | privilege_type | is_grantable 
------------------+------------+-------------+----------------+--------------
 admin_datos      | usuario    | activo      | INSERT         | NO
 admin_datos      | usuario    | activo      | SELECT         | NO
 admin_datos      | usuario    | activo      | UPDATE         | NO
 admin_datos      | usuario    | apellido    | INSERT         | NO
 admin_datos      | usuario    | apellido    | SELECT         | NO
 admin_datos      | usuario    | apellido    | UPDATE         | NO
 admin_datos      | usuario    | celular     | INSERT         | NO
 admin_datos      | usuario    | celular     | SELECT         | NO
 admin_datos      | usuario    | celular     | UPDATE         | NO
 admin_datos      | usuario    | created_at  | SELECT         | NO
 admin_datos      | usuario    | id          | SELECT         | NO
 admin_datos      | usuario    | mail        | INSERT         | NO
 admin_datos      | usuario    | mail        | SELECT         | NO
 admin_datos      | usuario    | mail        | UPDATE         | NO
 admin_datos      | usuario    | nombre      | INSERT         | NO
 admin_datos      | usuario    | nombre      | SELECT         | NO
 admin_datos      | usuario    | nombre      | UPDATE         | NO
 admin_datos      | usuario    | rol         | SELECT         | NO
 rol_owner_codigo | usuario    | activo      | SELECT         | NO
 rol_owner_codigo | usuario    | contrasena  | SELECT         | NO
 rol_owner_codigo | usuario    | contrasena  | UPDATE         | NO
 rol_owner_codigo | usuario    | id          | SELECT         | NO
 rol_owner_codigo | usuario    | mail        | SELECT         | NO
 rol_owner_codigo | usuario    | rol         | SELECT         | NO
 rol_soporte      | usuario    | activo      | SELECT         | NO
 rol_soporte      | usuario    | apellido    | SELECT         | NO
 rol_soporte      | usuario    | created_at  | SELECT         | NO
 rol_soporte      | usuario    | id          | SELECT         | NO
 rol_soporte      | usuario    | mail        | SELECT         | NO
 rol_soporte      | usuario    | nombre      | SELECT         | NO
 rol_soporte      | usuario    | rol         | SELECT         | NO
(31 filas)

=== 5. MATRIZ DE CHECKS CRÍTICOS (incluye herencia) ===
 soporte_select_tabla_usuario | soporte_select_contrasena | soporte_select_mail | soporte_update_usuario | lectura_select_producto | lectura_select_vista | escritura_insert_pedido | escritura_update_pedido | escritura_delete_pedido | escritura_insert_email_cliente | escritura_returning_id_cliente | escritura_usage_seq_cliente | escritura_usage_seq_pedido | admin_delete_pedido | admin_select_contrasena | admin_update_contrasena | owner_codigo_select_contrasena | owner_codigo_select_tabla_usuario | reportes_select_mv | reportes_select_usuario | app_web_hereda_lectura | app_web_select_usuario 
------------------------------+---------------------------+---------------------+------------------------+-------------------------+----------------------+-------------------------+-------------------------+-------------------------+--------------------------------+--------------------------------+-----------------------------+----------------------------+---------------------+-------------------------+-------------------------+--------------------------------+-----------------------------------+--------------------+-------------------------+------------------------+------------------------
 f                            | f                         | t                   | f                      | f                       | t                    | f                       | f                       | f                       | t                              | t                              | t                           | f                          | f                   | f                       | f                       | t                              | f                                 | t                  | f                       | t                      | f
(1 fila)

=== 6. PROPIEDAD Y HARDENING DE RUTINAS ===
 esquema |        rutina        |                                             argumentos                                              | security_definer |          configuracion          |   propietario    
---------+----------------------+-----------------------------------------------------------------------------------------------------+------------------+---------------------------------+------------------
 public  | fn_autenticar        | p_mail text, p_password text                                                                        | t                | {"search_path=public, pg_temp"} | rol_owner_codigo
 public  | fn_resetear_password | p_usuario_id bigint, p_nueva text                                                                   | t                | {"search_path=public, pg_temp"} | rol_owner_codigo
 public  | sp_registrar_pedido  | IN p_cliente_id bigint, IN p_forma_pago forma_pago_enum, IN p_items jsonb, INOUT p_pedido_id bigint | t                | {"search_path=public, pg_temp"} | rol_owner_codigo
(3 filas)

=== 6.b PRIVILEGIOS EFECTIVOS DE EJECUCIÓN DE RUTINAS ===
      rolname      | fn_autenticar | fn_resetear_password | sp_registrar_pedido 
-------------------+---------------+----------------------+---------------------
 admin_datos       | f             | f                    | t
 app_web           | t             | f                    | t
 rol_app_escritura | t             | f                    | t
 rol_app_lectura   | t             | f                    | f
 rol_owner_codigo  | t             | t                    | t
 rol_reportes      | f             | f                    | f
 rol_soporte       | f             | t                    | f
(7 filas)

=== 6.c FUNCIONES DE pgcrypto (riesgo R10: no abiertas a PUBLIC) ===
      rolname      | crypt | gen_salt 
-------------------+-------+----------
 admin_datos       | f     | f
 app_web           | f     | f
 rol_app_escritura | f     | f
 rol_app_lectura   | f     | f
 rol_owner_codigo  | t     | t
 rol_reportes      | f     | f
 rol_soporte       | f     | f
(7 filas)

=== 7. PRIVILEGIOS POR OMISIÓN (objetos futuros) ===
 propietario | esquema | tipo_objeto |          acl          
-------------+---------+-------------+-----------------------
 postgres    |         | T           | {postgres=U/postgres}
 postgres    |         | f           | {postgres=X/postgres}
(2 filas)

=== 8. du (metacomando de psql; incluye todos los roles del clúster) ===
                                   Lista de roles
     Nombre de rol      |                         Atributos                         
------------------------+-----------------------------------------------------------
 admin_datos            | 5 conexiones
 app_web                | 20 conexiones
 postgres               | Superusuario, Crear rol, Crear BD, Replicación, Ignora RLS
 rol_app_escritura      | No puede conectarse
 rol_app_lectura        | No puede conectarse
 rol_owner_codigo       | No puede conectarse
 rol_reportes           | No puede conectarse
 rol_reportes_foodstore | 
 rol_soporte            | No puede conectarse
```

## 5. Lectura crítica de los resultados

### 5.1 Lo que la salida demuestra

- **Atributos (bloque 1):** los cuatro roles de grupo y el técnico tienen `puede_login = f`; solo `app_web` y `admin_datos` tienen `t`. Ningún rol tiene `superuser`, `createdb`, `createrole`, `replication` ni `bypassrls`. Los límites de conexión son 20 y 5.
- **Membresías (bloque 2):** solo existen tres: `app_web → rol_app_escritura`, `app_web → rol_app_lectura` y `rol_app_escritura → rol_app_lectura`. Ninguna tiene `admin_option`. `rol_owner_codigo` no tiene membresías.
- **Privilegios directos (bloque 3):** `rol_app_lectura` solo aparece sobre las tres vistas; `rol_reportes` aparece solo por `vw_detalle_pedido` (su `SELECT` sobre la vista materializada no lo muestra `information_schema`; se verifica en el bloque 5); `admin_datos` tiene `SELECT/INSERT/UPDATE` en tablas de negocio, **sin `DELETE`**. No hay `GRANT ALL`.
- **Permiso por columna (bloque 4):** `rol_soporte` tiene `SELECT` sobre `id, nombre, apellido, mail, rol, activo, created_at`, y **ninguna** fila para `contrasena`. `admin_datos` no tiene ninguna fila para `contrasena` y sobre `rol` solo tiene `SELECT`.
- **Matriz efectiva (bloque 5):** los 22 checks coinciden con la especificación. En particular:
  - `soporte_select_contrasena = false`
  - `soporte_select_mail = true`
  - `escritura_update_pedido = false`
  - `escritura_delete_pedido = false`
  - `admin_delete_pedido = false`
  - `admin_select_contrasena = false`
  - `admin_update_contrasena = false`
  - `reportes_select_mv = true`
  - `reportes_select_usuario = false`
  - `app_web_select_usuario = false`
- **Rutinas (bloque 6):** las tres tienen `security_definer = t`, `configuracion = {"search_path=public, pg_temp"}` y propietario `rol_owner_codigo`. Ninguna corre como superusuario.
- **Privilegios de ejecución (bloque 6.b):** `fn_autenticar` solo para `rol_app_lectura`, `rol_app_escritura`, `app_web` y el dueño; `fn_resetear_password` solo para `rol_soporte` y el dueño; `sp_registrar_pedido` solo para `rol_app_escritura`, `app_web`, `admin_datos` y el dueño. `rol_reportes` no ejecuta ninguna rutina.
- **pgcrypto (bloque 6.c):** `crypt` y `gen_salt` solo son ejecutables por `rol_owner_codigo`; ningún rol de negocio puede fabricar hashes.
- **Objetos futuros (bloque 7):** `pg_default_acl` registra la política para funciones (`f`) y tipos (`T`) del rol `postgres`, sin `EXECUTE` ni `USAGE` para `PUBLIC`.
- **`\du` (bloque 8):** confirma visualmente que los roles de grupo y el técnico son `NOLOGIN`, y que los dos de conexión no tienen atributos administrativos.

### 5.2 Por qué `information_schema.role_table_grants` no muestra todo

`information_schema.role_table_grants` tiene tres limitaciones que la verificación debe cubrir:

1. **No muestra privilegios por columna.** Por eso `cliente` no aparece para `rol_app_escritura`, y `usuario` no aparece para `rol_soporte` ni `admin_datos` en el bloque 3; esos privilegios se verifican en el bloque 4 y con `has_column_privilege`.
2. **No muestra vistas materializadas.** `mv_facturacion_categoria_mes` no figura en el bloque 3; se verifica con `has_table_privilege` (`reportes_select_mv = true`).
3. **No muestra privilegios heredados por membresía.** `app_web` no aparece en el bloque 3; se verifica con `has_table_privilege` (`app_web_hereda_lectura = true`).

Por eso el informe combina `information_schema` con las funciones `has_*_privilege`, que evalúan el privilegio **efectivo**.

### 5.3 Por qué `pg_default_acl` solo tiene dos filas

En PostgreSQL:

- Las tablas y secuencias **no** otorgan privilegios a `PUBLIC` por defecto. El `REVOKE ALL ... ON TABLES/SEQUENCES FROM PUBLIC` es una declaración de política y no genera una entrada en `pg_default_acl` porque el ACL resultante es igual al implícito.
- Las funciones **sí** otorgan `EXECUTE` a `PUBLIC` por defecto, y los tipos `USAGE`. Al revocarlos, el ACL deja de ser el implícito y queda registrado: `{postgres=X/postgres}` para funciones y `{postgres=U/postgres}` para tipos.

La ausencia de filas para tablas/secuencias **no** significa que la política no se aplicó: significa que el valor por omisión ya era seguro. Lo que importa es que no hay ninguna entrada que otorgue privilegios a los roles de Food Store sobre objetos futuros.

### 5.4 El caso `rol_owner_codigo` y `contrasena`

El bloque 5 muestra `owner_codigo_select_contrasena = true`. **Es intencional y está justificado:** `fn_autenticar` necesita comparar `contrasena = crypt(p_password, contrasena)`. El rol es `NOLOGIN`, no tiene membresías, no puede `CREATE` y solo es propietario de las rutinas; no puede consultar el hash de forma interactiva. Aun así, se registra como riesgo residual R3 en el diseño: si se le asignara la propiedad de una rutina maliciosa, podría exfiltrar hashes. La mitigación recomendada es mover la verificación a la aplicación o usar un rol técnico por rutina.

### 5.5 Hallazgo corregido (R2): el guard de `ADMIN` no protegía frente a `admin_datos`

`fn_resetear_password` rechaza resetear una cuenta con `rol = 'ADMIN'`. Eso impide que `rol_soporte` escale verticalmente, porque soporte no tiene `UPDATE` sobre `usuario.rol`.

En la **primera versión** de `roles.sql`, `admin_datos` sí tenía `UPDATE (rol)`. La cadena siguiente se verificó en el clúster de prueba dentro de una transacción revertida:

```sql
BEGIN;
SET ROLE admin_datos;
UPDATE usuario SET rol = 'USUARIO' WHERE id = 1;      -- degrada al ADMIN
SELECT fn_resetear_password(1, 'ClaveConocida2026!');  -- el guard ya no aplica
UPDATE usuario SET rol = 'ADMIN' WHERE id = 1;         -- lo vuelve a promover
RESET ROLE;
ROLLBACK;
```

Resultado: `UPDATE 1`, función ejecutada, `UPDATE 1`. Es un **escalamiento vertical real** desde la credencial de administración de datos. No es un defecto de `fn_resetear_password` sino una consecuencia de combinar `UPDATE (rol)` con `EXECUTE` sobre la función.

**Corrección aplicada:** se le quitaron a `admin_datos` `INSERT/UPDATE (rol)`, `INSERT (contrasena)` y `EXECUTE` sobre `fn_resetear_password` (decisión D6 del diseño: segregación de funciones). La misma cadena, re-ejecutada sobre `foodstore_tp5`, se corta en el primer paso:

```text
UPDATE usuario SET rol = 'USUARIO' WHERE id = 1;       -> ERROR:  permission denied for table usuario
SELECT fn_resetear_password(1, 'ClaveConocida2026!');   -> ERROR:  permission denied for function fn_resetear_password
INSERT INTO usuario (..., contrasena, rol) VALUES (..., 'ADMIN') -> ERROR:  permission denied for table usuario
```

`TP5/sql/test_roles.sql` deja esta comprobación como prueba de regresión.

### 5.6 Hallazgo: `rol_reportes_foodstore` de TP3

El bloque 8 (`\du`) muestra un rol adicional, `rol_reportes_foodstore`, que **no forma parte del esquema nuevo**. Fue creado en TP3 por `Proyecto_Integrador/database/views.sql` con `LOGIN PASSWORD 'AuditorPassword2026!'` (contraseña en texto plano dentro del repositorio) y `SELECT` sobre `vw_pedidos_cliente`.

Es un hallazgo de seguridad, no un error de `roles.sql`:

- La contraseña está versionada en Git y debe considerarse comprometida.
- El rol tiene `LOGIN` sin `CONNECTION LIMIT` ni política de rotación.
- No existe un reemplazo exacto en el esquema nuevo: `rol_reportes` no recibe `vw_pedidos_cliente` porque esa vista expone nombres de clientes. Si se necesita esa vista, debe crearse un rol específico con justificación y sin datos personales.

**Acción recomendada:** `DROP ROLE rol_reportes_foodstore` en cada base donde exista, o —si se necesita conservar la credencial— rotar la clave con `\password` y migrar su uso a `rol_reportes`.

### 5.7 Hallazgo corregido (R10): `crypt` y `gen_salt` abiertas a `PUBLIC`

En la primera versión, la consulta:

```sql
SELECT
    has_function_privilege('admin_datos',  'public.crypt(text,text)', 'EXECUTE') AS admin_crypt,
    has_function_privilege('rol_soporte',  'public.crypt(text,text)', 'EXECUTE') AS soporte_crypt,
    has_function_privilege('app_web',      'public.crypt(text,text)', 'EXECUTE') AS app_crypt;
```

devuelve `t | t | t`. Las funciones de `pgcrypto` se crearon con `EXECUTE` para `PUBLIC` y el script no las revoca; el `ALTER DEFAULT PRIVILEGES` solo cubre funciones futuras.

**Impacto:** no otorga escritura por sí solo, pero `admin_datos` ya tiene `INSERT (contrasena, rol)`; con `crypt` puede generar el hash de una clave conocida y crear una cuenta `ADMIN` sin depender de un hash precalculado. Se registra como R10 en `design.md` §7.

**Corrección aplicada:** `roles.sql` §9 ejecuta `REVOKE EXECUTE ... FROM PUBLIC` sobre `crypt(text,text)`, `gen_salt(text)` y `gen_salt(text,integer)`, y las otorga solo a `rol_owner_codigo`. El bloque 6.c muestra `f | f` para todos los roles de negocio y `t | t` para el dueño técnico. `fn_autenticar` y `fn_resetear_password` siguen funcionando porque corren como ese dueño (`SECURITY DEFINER`); `test_roles.sql` lo comprueba autenticando como `app_web` y reseteando como `rol_soporte`.

## 6. Pruebas de comportamiento (runtime)

La matriz de catálogo se complementó con pruebas de ejecución con `SET ROLE`. Resultados:

| Rol | Operación | Resultado |
|---|---|---|
| `rol_soporte` | `SELECT id, nombre, mail FROM usuario` | OK |
| `rol_soporte` | `SELECT contrasena FROM usuario` | `ERROR: permission denied for table usuario` |
| `rol_soporte` | `SELECT * FROM usuario` | `ERROR: permission denied for table usuario` |
| `rol_soporte` | `UPDATE usuario SET mail = 'x'` | `ERROR: permission denied for table usuario` |
| `rol_soporte` | `SELECT fn_resetear_password(2, 'NuevaClave2026!')` | OK; el hash cambia |
| `rol_soporte` | `SELECT fn_resetear_password(1, 'NuevaClave2026!')` (usuario `ADMIN`) | `ERROR: No existe un usuario activo con id 1 o la cuenta es ADMIN...` |
| `rol_app_escritura` | `INSERT INTO cliente (nombre, apellido, email, telefono) VALUES (...) RETURNING id` | OK; devuelve `id` |
| `rol_app_escritura` | `CALL sp_registrar_pedido(...)` | OK; inserta pedido, detalle y descuenta stock |
| `rol_app_escritura` | `UPDATE producto SET stock = 0` | `ERROR: permission denied for table producto` |
| `rol_app_escritura` | `DELETE FROM cliente` | `ERROR: permission denied for table cliente` |
| `app_web` | `CREATE TABLE t (id int)` | `ERROR: permission denied for schema public` |
| `app_web` | `GRANT admin_datos TO app_web` | `ERROR: permission denied to grant role "admin_datos"` |
| `admin_datos` | `DELETE FROM pedido` | `ERROR: permission denied for table pedido` |
| `admin_datos` | `SELECT contrasena FROM usuario` | `ERROR: permission denied for table usuario` |
| `admin_datos` | `UPDATE usuario SET contrasena = 'x'` | `ERROR: permission denied for table usuario` |
| `rol_reportes` | `SELECT * FROM mv_facturacion_categoria_mes` | OK |
| `rol_reportes` | `SELECT * FROM usuario` | `ERROR: permission denied for table usuario` |
| `rol_owner_codigo` | `CREATE TABLE t (id int)` | `ERROR: permission denied for schema public` |
| `admin_datos` | `UPDATE usuario SET rol = 'USUARIO' WHERE id = 1` | `ERROR: permission denied for table usuario` |
| `admin_datos` | `SELECT fn_resetear_password(1, '...')` | `ERROR: permission denied for function fn_resetear_password` |
| `admin_datos` | `INSERT INTO usuario (nombre, apellido, mail) VALUES (...)` | OK; la cuenta nace `rol = 'USUARIO'` y `contrasena = NULL` |
| `app_web` | `SELECT * FROM fn_autenticar('cuenta2@foodstore.test', <clave correcta>)` | 1 fila (`2`, `USUARIO`) |
| `app_web` | `SELECT * FROM fn_autenticar('cuenta2@foodstore.test', 'incorrecta')` | 0 filas |

Las filas agregadas (corrección de R2 y R10) se ejecutan automáticamente en `TP5/sql/test_roles.sql`.

## 7. Idempotencia

`roles.sql` se ejecutó dos veces consecutivas sobre la misma base. La segunda ejecución:

- No produjo errores.
- No perdió filas de las tablas de Food Store.
- Recreó los siete roles con los mismos privilegios.
- Mantuvo la propiedad de las rutinas en `rol_owner_codigo` (la transferencia se repite).

Esto valida los Requisitos 12.1–12.3.

## 8. Conclusión

El esquema cumple la especificación:

- **7 roles**: 4 de grupo `NOLOGIN`, 1 técnico `NOLOGIN` y 2 `LOGIN`.
- **Cero** `SUPERUSER`, `CREATEROLE`, `CREATEDB`, `REPLICATION` o `BYPASSRLS`.
- **Cero** `GRANT ALL`, `DELETE`, `TRUNCATE`, `REFERENCES` o `TRIGGER` para roles de aplicación.
- **Caso obligatorio de permiso por columna** implementado y verificado: `rol_soporte` no puede leer `usuario.contrasena`, y `SELECT *` falla.
- **`fn_resetear_password`** es `SECURITY DEFINER`, con `search_path` fijo, `REVOKE ALL FROM PUBLIC`, propietario no superusuario y bloqueo de cuentas `ADMIN`.
- **`ALTER DEFAULT PRIVILEGES`** impide que funciones y tipos futuros nazcan con privilegios para `PUBLIC` y no otorga nada automáticamente a los roles de negocio.
- **Hallazgos de la verificación corregidos:** el escalamiento de `admin_datos` (R2, §5.5) y `crypt`/`gen_salt` abiertas a `PUBLIC` (R10, §5.7).

Los riesgos residuales (RLS horizontal, `rol_owner_codigo` puede leer hashes para autenticar, `FOR UPDATE` exige `UPDATE` de tabla, el rol heredado `rol_reportes_foodstore` de TP3) están documentados en `design.md` §7 con su mitigación y recomendación.
