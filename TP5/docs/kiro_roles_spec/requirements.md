# Requirements Document

## Introduction

Esta especificación define el **esquema de roles y privilegios de mínimo privilegio (POLP)** para la base de datos **Food Store** del Trabajo Práctico de la Unidad 5 (Base de Datos II, UTN). El alcance es la Parte A del trabajo: diseño, implementación y verificación de identidades, membresías y permisos sobre PostgreSQL 16+.

El esquema de Food Store comprende las tablas base `categoria`, `producto`, `cliente`, `pedido`, `pedido_detalle` y `usuario`; las vistas `vw_productos_vigentes`, `vw_pedidos_cliente` y `vw_detalle_pedido`; la vista materializada `mv_facturacion_categoria_mes`; y las rutinas `sp_registrar_pedido`, `fn_autenticar` y `fn_resetear_password`. La baja de entidades es lógica (`activo = FALSE`), por lo que el borrado físico (`DELETE`) no forma parte de la operación normal del sistema.

El diseño parte de una premisa: **ninguna credencial de conexión debe ser dueña del esquema ni tener privilegios administrativos**. Los permisos se agrupan por función de negocio en roles `NOLOGIN`; las credenciales reales (`app_web`, `admin_datos`) solo heredan los grupos que necesitan. Las escrituras críticas se canalizan por rutinas `SECURITY DEFINER` endurecidas, y la lectura de datos personales o credenciales se limita por vista, por columna o por función.

### Precondiciones de ejecución

1. Ejecutar `sql/roles.sql` como superusuario o como dueño del esquema (`DBA`).
2. La extensión `pgcrypto` debe estar instalada (hash bcrypt con `crypt`/`gen_salt`).
3. Las tablas, vistas, vista materializada y rutinas deben existir antes de aplicar los `GRANT`.
4. Las contraseñas de `app_web` y `admin_datos` no se versionan: se crean con `PASSWORD NULL` y se provisionan con `\password` o un gestor de secretos.
5. Los roles son objetos del clúster. Si otras bases usan los mismos nombres, deben limpiarse con `DROP OWNED BY` en cada base o usarse un clúster dedicado.

---

## Glossary

- **Sistema_Roles**: El conjunto de sentencias `CREATE ROLE`, `GRANT`, `REVOKE`, `ALTER DEFAULT PRIVILEGES` y hardening de rutinas definido en `sql/roles.sql`.
- **Rol_de_Grupo**: Rol `NOLOGIN` que agrupa privilegios por función de negocio y se asigna por membresía a un rol de conexión.
- **Rol_de_Conexión**: Rol `LOGIN` con credenciales, utilizado por una aplicación o por una persona.
- **Rol_Técnico_de_Propiedad**: Rol `NOLOGIN` sin membresías que posee las rutinas `SECURITY DEFINER` para que éstas no se ejecuten con privilegios de superusuario.
- **POLP**: Principio de Mínimo Privilegio; cada identidad recibe solo los permisos indispensables para su operación.
- **Privilegio_por_Columna**: `GRANT SELECT (col1, col2) ON tabla`, que permite leer solo las columnas enumeradas y hace fallar `SELECT *` o el acceso a columnas no incluidas.
- **SECURITY_DEFINER**: Atributo de una función o procedimiento que hace que el cuerpo se ejecute con los privilegios de su propietario, no con los del invocador.
- **search_path_Endurecido**: Fijación explícita `SET search_path = public, pg_temp` para evitar que objetos de `pg_temp` u otros esquemas suplanten tablas o funciones.
- **Privilegios_por_Omisión**: Permisos que PostgreSQL aplica automáticamente a objetos futuros creados por un rol (`ALTER DEFAULT PRIVILEGES`).
- **Privilegio_Directo**: `GRANT` otorgado explícitamente a un rol sobre un objeto.
- **Privilegio_Heredado**: Privilegio que un rol de conexión obtiene por pertenecer a un rol de grupo (`INHERIT`).
- **Hash_de_Contraseña**: Valor bcrypt almacenado en `usuario.contrasena`; nunca debe exponerse a roles de soporte, reportes ni aplicación.
- **Rutina_Endurecida**: Rutina `SECURITY DEFINER` con `search_path` fijo, `REVOKE ALL FROM PUBLIC`, propietario `NOSUPERUSER` y `EXECUTE` otorgado solo a los roles que la necesitan.

---

## Justificación unioracional de roles

| Rol | Tipo | Justificación unioracional |
|---|---|---|
| `rol_app_lectura` | Grupo `NOLOGIN` | Habilita únicamente la lectura del catálogo y del historial de pedidos a través de las vistas, para que el frontend consulte sin acceso directo a las tablas base ni a datos de autenticación. |
| `rol_app_escritura` | Grupo `NOLOGIN` | Habilita el alta de clientes y el registro de pedidos mediante el procedimiento transaccional, para que la aplicación escriba sin privilegios directos de `UPDATE`/`DELETE` sobre pedidos, detalles o stock. |
| `rol_soporte` | Grupo `NOLOGIN` | Habilita la consulta de datos identificativos no sensibles de `usuario` y el reset de contraseña mediante una función acotada, para atender incidentes sin poder leer el hash ni modificar la tabla `usuario` directamente. |
| `rol_reportes` | Grupo `NOLOGIN` | Habilita la lectura de la vista materializada de facturación y del detalle de pedidos sin datos personales, para generar reportes gerenciales sin exponer clientes ni credenciales. |
| `rol_owner_codigo` | Técnico `NOLOGIN` | Habilita la propiedad de las rutinas `SECURITY DEFINER` con solo los privilegios que éstas necesitan, para que ninguna función se ejecute como superusuario ni pueda leer el hash desde la función de reset. |
| `app_web` | Conexión `LOGIN` | Habilita la conexión del backend con la suma de permisos de lectura y escritura de la aplicación, sin atributos administrativos ni acceso al esquema. |
| `admin_datos` | Conexión `LOGIN` | Habilita la conexión de un administrador de datos para consultar y mantener los datos de Food Store, sin `SUPERUSER`, sin `CREATEROLE`, sin `DELETE` físico y sin lectura del hash. |

---

## Requirements

### Requisito 1 — Modelo de roles, atributos y membresías

**User Story:** Como DBA de Food Store, quiero que las identidades del motor reflejen las funciones reales del sistema y que ninguna credencial de conexión tenga atributos administrativos, para reducir el impacto de una fuga de credenciales.

#### Criterios de Aceptación

1. THE `Sistema_Roles` SHALL crear los roles de grupo `rol_app_lectura`, `rol_app_escritura`, `rol_soporte` y `rol_reportes` con atributo `NOLOGIN`.
2. THE `Sistema_Roles` SHALL crear los roles de conexión `app_web` y `admin_datos` con atributo `LOGIN`.
3. THE `Sistema_Roles` SHALL crear el rol técnico de propiedad `rol_owner_codigo` con atributo `NOLOGIN` y sin membresías.
4. THE `Sistema_Roles` SHALL asignar a los siete roles los atributos `NOSUPERUSER`, `NOCREATEDB`, `NOCREATEROLE`, `NOREPLICATION` y `NOBYPASSRLS`.
5. WHEN se crean `app_web` y `admin_datos`, THE `Sistema_Roles` SHALL usar `PASSWORD NULL` y un `CONNECTION LIMIT` explícito, de modo que ninguna contraseña quede versionada en Git.
6. THE `Sistema_Roles` SHALL otorgar `rol_app_lectura` y `rol_app_escritura` a `app_web` sin `WITH ADMIN OPTION`.
7. THE `Sistema_Roles` SHALL otorgar `rol_app_lectura` a `rol_app_escritura` sin `WITH ADMIN OPTION`, para que la escritura herede la lectura.
8. IF un rol de grupo intenta iniciar sesión, THEN PostgreSQL SHALL rechazar la conexión por `NOLOGIN`.
9. IF `app_web` intenta otorgar `admin_datos` a otro rol, THEN PostgreSQL SHALL rechazar la operación por falta de `ADMIN OPTION`.

---

### Requisito 2 — Acceso al esquema y línea base de revocación

**User Story:** Como DBA, quiero que el esquema `public` no sea accesible por `PUBLIC` y que cada rol reciba `USAGE` explícito, para que ningún privilegio se herede por omisión.

#### Criterios de Aceptación

1. THE `Sistema_Roles` SHALL ejecutar `REVOKE ALL ON SCHEMA public FROM PUBLIC`.
2. THE `Sistema_Roles` SHALL otorgar `USAGE ON SCHEMA public` a los siete roles creados.
3. THE `Sistema_Roles` SHALL revocar `ALL` sobre las tablas base, vistas, vista materializada y secuencias de Food Store de `PUBLIC`.
4. THE `Sistema_Roles` SHALL revocar `EXECUTE` de `PUBLIC` sobre `fn_resetear_password`, `sp_registrar_pedido` y todas las sobrecargas de `fn_autenticar`.
5. THE `Sistema_Roles` SHALL NO otorgar `CREATE ON SCHEMA public` a `rol_app_lectura`, `rol_app_escritura`, `rol_soporte`, `rol_reportes`, `app_web` ni `admin_datos`.
6. WHILE un rol de aplicación no tenga `USAGE` sobre `public`, cualquier `SELECT` sobre una vista o tabla de Food Store SHALL fallar con error de permisos.

---

### Requisito 3 — `rol_app_lectura`: lectura exclusiva por vistas

**User Story:** Como desarrollador del frontend, quiero consultar el catálogo y los pedidos sin acceso directo a las tablas base, para que una inyección SQL no pueda leer datos de autenticación ni modificar el esquema.

#### Criterios de Aceptación

1. THE `Sistema_Roles` SHALL otorgar `SELECT` a `rol_app_lectura` únicamente sobre `vw_productos_vigentes`, `vw_pedidos_cliente` y `vw_detalle_pedido`.
2. THE `Sistema_Roles` SHALL NO otorgar `SELECT`, `INSERT`, `UPDATE` ni `DELETE` a `rol_app_lectura` sobre `categoria`, `producto`, `cliente`, `pedido`, `pedido_detalle` ni `usuario`.
3. THE `Sistema_Roles` SHALL NO otorgar privilegios de secuencia a `rol_app_lectura`.
4. THE `Sistema_Roles` SHALL otorgar `EXECUTE` sobre `fn_autenticar` a `rol_app_lectura`, para que el backend autentique sin leer `usuario.contrasena`.
5. WHEN `rol_app_lectura` ejecuta `SELECT * FROM producto`, THE PostgreSQL SHALL responder con error de permisos.
6. WHEN `rol_app_lectura` ejecuta `SELECT * FROM vw_productos_vigentes`, THE PostgreSQL SHALL retornar las filas de la vista.

---

### Requisito 4 — `rol_app_escritura`: escritura mediada por procedimiento

**User Story:** Como desarrollador del backend, quiero registrar pedidos y altas de clientes sin recibir `UPDATE`/`DELETE` directo sobre las tablas transaccionales, para que la lógica de stock y precios históricos quede encapsulada en el procedimiento.

#### Criterios de Aceptación

1. THE `Sistema_Roles` SHALL otorgar `EXECUTE` sobre `sp_registrar_pedido(BIGINT, forma_pago_enum, JSONB, BIGINT)` a `rol_app_escritura`.
2. THE `Sistema_Roles` SHALL otorgar `INSERT` a nivel de columna `(nombre, apellido, email, telefono)` sobre `cliente` a `rol_app_escritura`.
3. THE `Sistema_Roles` SHALL otorgar `SELECT (id)` sobre `cliente` a `rol_app_escritura`, para permitir `INSERT ... RETURNING id` sin exponer los datos de contacto.
4. THE `Sistema_Roles` SHALL otorgar `USAGE` únicamente sobre la secuencia `cliente_id_seq` a `rol_app_escritura`.
5. THE `Sistema_Roles` SHALL NO otorgar `INSERT`, `UPDATE` ni `DELETE` directo sobre `pedido`, `pedido_detalle` ni `producto` a `rol_app_escritura`.
6. THE `Sistema_Roles` SHALL NO otorgar `USAGE` sobre `pedido_id_seq`, `producto_id_seq`, `categoria_id_seq` ni `usuario_id_seq` a `rol_app_escritura`.
7. WHEN `rol_app_escritura` ejecuta `CALL sp_registrar_pedido(...)`, THE PostgreSQL SHALL registrar el pedido, el detalle y descontar stock con los privilegios del propietario de la rutina.
8. IF `rol_app_escritura` intenta `UPDATE producto SET stock = ...`, THEN PostgreSQL SHALL rechazar la operación por falta de privilegio.
9. IF `rol_app_escritura` intenta `DELETE FROM cliente`, THEN PostgreSQL SHALL rechazar la operación por falta de privilegio.

---

### Requisito 5 — `rol_soporte`: permiso por columna y reset acotado

**User Story:** Como agente de soporte, quiero consultar los datos identificativos de un usuario y resetear su contraseña sin poder leer el hash ni modificar la tabla `usuario` directamente, para atender incidentes sin comprometer credenciales.

#### Criterios de Aceptación

1. THE `Sistema_Roles` SHALL ejecutar `REVOKE ALL ON TABLE public.usuario FROM rol_soporte` antes de otorgar privilegios por columna.
2. THE `Sistema_Roles` SHALL otorgar exactamente `SELECT (id, nombre, apellido, mail, rol, activo, created_at)` sobre `usuario` a `rol_soporte`.
3. THE `Sistema_Roles` SHALL NO otorgar `SELECT` sobre `usuario.contrasena` a `rol_soporte`.
4. THE `Sistema_Roles` SHALL NO otorgar `INSERT`, `UPDATE` ni `DELETE` sobre `usuario` a `rol_soporte`.
5. THE `Sistema_Roles` SHALL otorgar `SELECT` sobre `vw_pedidos_cliente` y `vw_detalle_pedido` a `rol_soporte`.
6. THE `Sistema_Roles` SHALL otorgar `EXECUTE` sobre `fn_resetear_password(BIGINT, TEXT)` a `rol_soporte`.
7. WHEN `rol_soporte` ejecuta `SELECT id, nombre, mail FROM usuario`, THE PostgreSQL SHALL retornar las filas permitidas.
8. WHEN `rol_soporte` ejecuta `SELECT contrasena FROM usuario`, THE PostgreSQL SHALL responder con error de permisos.
9. WHEN `rol_soporte` ejecuta `SELECT * FROM usuario`, THE PostgreSQL SHALL responder con error de permisos porque `*` incluye `contrasena`.
10. WHEN `rol_soporte` intenta `UPDATE usuario SET mail = ...`, THE PostgreSQL SHALL rechazar la operación por falta de privilegio.

---

### Requisito 6 — `rol_reportes`: analítica sin datos personales

**User Story:** Como analista de gestión, quiero leer la facturación agregada y el detalle de pedidos sin datos del cliente, para producir reportes sin exponer información personal.

#### Criterios de Aceptación

1. THE `Sistema_Roles` SHALL otorgar `SELECT` sobre `mv_facturacion_categoria_mes` a `rol_reportes`.
2. THE `Sistema_Roles` SHALL otorgar `SELECT` sobre `vw_detalle_pedido` a `rol_reportes`.
3. THE `Sistema_Roles` SHALL NO otorgar `SELECT` sobre `vw_pedidos_cliente` a `rol_reportes`, porque esa vista expone nombres de clientes.
4. THE `Sistema_Roles` SHALL NO otorgar `SELECT` sobre `usuario`, `cliente` ni las tablas base a `rol_reportes`.
5. THE `Sistema_Roles` SHALL NO otorgar privilegios de escritura ni de secuencia a `rol_reportes`.
6. WHEN `rol_reportes` ejecuta `SELECT * FROM mv_facturacion_categoria_mes`, THE PostgreSQL SHALL retornar los datos materializados.
7. WHEN `rol_reportes` ejecuta `SELECT * FROM usuario`, THE PostgreSQL SHALL responder con error de permisos.

---

### Requisito 7 — `admin_datos`: administración de datos sin DDL ni borrado físico

**User Story:** Como administrador de datos, quiero mantener los datos de Food Store sin poder alterar el esquema, crear roles, borrar filas físicamente ni leer hashes, para que una credencial comprometida no destruya la base ni robe credenciales.

#### Criterios de Aceptación

1. THE `Sistema_Roles` SHALL otorgar `SELECT`, `INSERT` y `UPDATE` —sin `DELETE`, `TRUNCATE`, `REFERENCES` ni `TRIGGER`— sobre `categoria`, `producto`, `cliente`, `pedido` y `pedido_detalle` a `admin_datos`.
2. THE `Sistema_Roles` SHALL otorgar sobre `usuario` exactamente `SELECT (id, nombre, apellido, mail, celular, rol, activo, created_at)`, `INSERT (nombre, apellido, mail, celular, contrasena, rol, activo)` y `UPDATE (nombre, apellido, mail, celular, rol, activo)` a `admin_datos`.
3. THE `Sistema_Roles` SHALL NO otorgar `SELECT` ni `UPDATE` sobre `usuario.contrasena` a `admin_datos`; el cambio de contraseña se realiza con `fn_resetear_password`.
4. THE `Sistema_Roles` SHALL otorgar `USAGE, SELECT` sobre `categoria_id_seq`, `producto_id_seq`, `cliente_id_seq`, `pedido_id_seq` y `usuario_id_seq` a `admin_datos`.
5. THE `Sistema_Roles` SHALL otorgar `SELECT` sobre las tres vistas y la vista materializada a `admin_datos`.
6. THE `Sistema_Roles` SHALL otorgar `EXECUTE` sobre `sp_registrar_pedido` y `fn_resetear_password` a `admin_datos`.
7. THE `Sistema_Roles` SHALL NO otorgar `CREATE ON SCHEMA public`, `CREATEDB`, `CREATEROLE` ni `SUPERUSER` a `admin_datos`.
8. WHEN `admin_datos` ejecuta `DELETE FROM pedido`, THE PostgreSQL SHALL responder con error de permisos.
9. WHEN `admin_datos` ejecuta `SELECT contrasena FROM usuario`, THE PostgreSQL SHALL responder con error de permisos.
10. WHEN `admin_datos` ejecuta `UPDATE usuario SET contrasena = ...`, THE PostgreSQL SHALL responder con error de permisos.

---

### Requisito 8 — `fn_resetear_password` endurecida

**User Story:** Como DBA, quiero que el reset de contraseña se ejecute con privilegios elevados pero acotados, para que soporte pueda resetear una clave sin recibir `UPDATE` sobre toda la tabla ni acceso al hash.

#### Criterios de Aceptación

1. THE `Sistema_Roles` SHALL crear o reemplazar `fn_resetear_password(p_usuario_id BIGINT, p_nueva TEXT)` con `RETURNS VOID`, `LANGUAGE plpgsql`, `SECURITY DEFINER` y `SET search_path = public, pg_temp`.
2. THE `Sistema_Roles` SHALL ejecutar `REVOKE ALL ON FUNCTION public.fn_resetear_password(BIGINT, TEXT) FROM PUBLIC`.
3. THE `Sistema_Roles` SHALL otorgar `EXECUTE` sobre `fn_resetear_password` a `rol_soporte` y `admin_datos`.
4. THE `Sistema_Roles` SHALL transferir la propiedad de `fn_resetear_password` a `rol_owner_codigo`.
5. THE `Sistema_Roles` SHALL otorgar a `rol_owner_codigo` únicamente `SELECT (id, activo)` y `UPDATE (contrasena)` sobre `usuario`, además de `EXECUTE` sobre `crypt(TEXT, TEXT)` y `gen_salt(TEXT)`.
6. WHEN `rol_soporte` invoca `fn_resetear_password` sobre un usuario activo con rol distinto de `ADMIN`, THE función SHALL actualizar `contrasena` con `crypt(p_nueva, gen_salt('bf'))`.
7. IF `p_usuario_id` es nulo, THEN THE función SHALL lanzar una excepción.
8. IF `p_nueva` es nula o vacía, THEN THE función SHALL lanzar una excepción.
9. IF el usuario no existe, está inactivo o tiene rol `ADMIN`, THEN THE función SHALL lanzar una excepción y no modificar ninguna fila.
10. THE función SHALL NO leer ni devolver el hash almacenado.

---

### Requisito 9 — Hardening de las rutinas `SECURITY DEFINER`

**User Story:** Como DBA, quiero que ninguna rutina `SECURITY DEFINER` se ejecute con privilegios de superusuario, para que una inyección en su cuerpo no comprometa toda la base.

#### Criterios de Aceptación

1. THE `Sistema_Roles` SHALL marcar `sp_registrar_pedido(BIGINT, forma_pago_enum, JSONB, BIGINT)` como `SECURITY DEFINER`.
2. THE `Sistema_Roles` SHALL fijar `SET search_path = public, pg_temp` en `sp_registrar_pedido`.
3. THE `Sistema_Roles` SHALL transferir la propiedad de `sp_registrar_pedido` a `rol_owner_codigo`.
4. THE `Sistema_Roles` SHALL marcar todas las sobrecargas de `fn_autenticar` como `SECURITY DEFINER`, fijar su `search_path` y transferir su propiedad a `rol_owner_codigo`.
5. THE `Sistema_Roles` SHALL otorgar a `rol_owner_codigo` solo los privilegios que las rutinas necesitan: `SELECT` acotado sobre `cliente` y `producto`, `UPDATE` sobre `producto` por el `FOR UPDATE`, `INSERT` acotado sobre `pedido` y `pedido_detalle`, `USAGE` sobre `pedido_id_seq`, `USAGE` sobre `forma_pago_enum`, `SELECT (id, mail, contrasena, rol, activo)` y `UPDATE (contrasena)` sobre `usuario`.
6. THE `Sistema_Roles` SHALL revocar `CREATE ON SCHEMA public` de `rol_owner_codigo` al finalizar la transferencia de propiedad.
7. WHEN se consulta `pg_proc`, las tres rutinas SHALL mostrar `prosecdef = true`, `proconfig` con `search_path=public, pg_temp` y propietario `rol_owner_codigo`.
8. IF `rol_owner_codigo` intenta `CREATE TABLE`, THEN PostgreSQL SHALL rechazar la operación por falta de `CREATE` sobre el esquema.

---

### Requisito 10 — Privilegios por omisión para objetos futuros

**User Story:** Como DBA, quiero que las tablas, vistas, secuencias, funciones y tipos creados en el futuro no nazcan con privilegios globales, para que una tabla sensible nueva no quede expuesta por herencia.

#### Criterios de Aceptación

1. THE `Sistema_Roles` SHALL ejecutar `ALTER DEFAULT PRIVILEGES FOR ROLE <dueño> IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC`.
2. THE `Sistema_Roles` SHALL ejecutar `ALTER DEFAULT PRIVILEGES FOR ROLE <dueño> IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC`.
3. THE `Sistema_Roles` SHALL ejecutar `ALTER DEFAULT PRIVILEGES FOR ROLE <dueño> REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` sin cláusula `IN SCHEMA`, porque un `REVOKE` por esquema no puede quitar el privilegio global de `PUBLIC`.
4. THE `Sistema_Roles` SHALL ejecutar `ALTER DEFAULT PRIVILEGES FOR ROLE <dueño> REVOKE USAGE ON TYPES FROM PUBLIC`.
5. THE `Sistema_Roles` SHALL NO otorgar privilegios automáticos sobre objetos futuros a `rol_app_lectura`, `rol_app_escritura`, `rol_soporte`, `rol_reportes` ni `app_web`.
6. WHEN el dueño crea una función nueva después de aplicar el script, `pg_proc.proacl` SHALL NO incluir `=X` (EXECUTE para `PUBLIC`).
7. WHEN el dueño crea una tabla nueva después de aplicar el script, `information_schema.role_table_grants` SHALL NO mostrar privilegios para los roles de Food Store hasta que se otorgue un `GRANT` explícito.

---

### Requisito 11 — Verificación y auditoría de permisos

**User Story:** Como auditor de seguridad, quiero consultar el catálogo de PostgreSQL y comparar los privilegios efectivos contra la especificación, para demostrar que ningún rol tiene permisos de más ni de menos.

#### Criterios de Aceptación

1. THE `Sistema_Roles` SHALL incluir `sql/verificacion_roles.sql` con una consulta sobre `information_schema.role_table_grants` filtrada por los siete roles creados.
2. THE `Sistema_Roles` SHALL incluir una consulta sobre `information_schema.column_privileges` para `usuario`, que demuestre que `rol_soporte` no tiene `SELECT` sobre `contrasena`.
3. THE `Sistema_Roles` SHALL incluir consultas con `has_table_privilege`, `has_column_privilege` y `has_sequence_privilege` para verificar privilegios efectivos, incluidos los heredados por membresía.
4. THE `Sistema_Roles` SHALL incluir una consulta sobre `pg_roles` y `pg_auth_members` para verificar atributos de login y membresías.
5. THE `Sistema_Roles` SHALL incluir una consulta sobre `pg_proc` para verificar `prosecdef`, `proconfig` y propietario de las rutinas.
6. THE `Sistema_Roles` SHALL incluir una consulta sobre `pg_default_acl` para verificar la política de objetos futuros.
7. THE `Sistema_Roles` SHALL incluir el metacomando `\du` para verificar visualmente los atributos de los roles.
8. WHEN se ejecuta la matriz de checks críticos, los valores SHALL ser: `soporte_select_contrasena = false`, `soporte_select_mail = true`, `escritura_update_pedido = false`, `escritura_delete_pedido = false`, `admin_delete_pedido = false`, `admin_select_contrasena = false`, `admin_update_contrasena = false`, `reportes_select_mv = true`, `reportes_select_usuario = false`, `app_web_select_usuario = false`.

---

### Requisito 12 — Idempotencia, reversibilidad y documentación

**User Story:** Como DBA, quiero poder reaplicar el script sin perder datos ni objetos, para corregir permisos en producción sin recurrir a una reconstrucción manual.

#### Criterios de Aceptación

1. THE `Sistema_Roles` SHALL ejecutar `DROP ROLE IF EXISTS` para los siete roles antes de recrearlos.
2. THE `Sistema_Roles` SHALL ejecutar `REASSIGN OWNED BY <rol> TO CURRENT_USER` y `DROP OWNED BY <rol>` antes de `DROP ROLE`, para no borrar objetos que hubieran quedado en propiedad de un rol.
3. WHEN el script se ejecuta dos veces consecutivas sobre la misma base, THE segunda ejecución SHALL completar sin errores y sin perder filas de las tablas de Food Store.
4. THE `Sistema_Roles` SHALL documentar en comentarios SQL la precondición de ejecución como dueño/superusuario y la limitación de los roles en clústeres con múltiples bases.
5. THE `Sistema_Roles` SHALL incluir `COMMENT ON ROLE` para cada rol, de modo que `\du+` y el catálogo expliquen su propósito.
6. THE `Sistema_Roles` SHALL NO incluir contraseñas en texto plano, `GRANT ALL`, `DELETE`, `TRUNCATE`, `REFERENCES` ni `TRIGGER` para roles de aplicación.
