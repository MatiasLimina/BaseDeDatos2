# Design Document

## 1. Resumen

Este documento describe **cómo** se implementa el esquema de mínimo privilegio (POLP) especificado en `requirements.md` para la base **Food Store** (PostgreSQL 16+). El diseño se apoya en tres ideas:

1. **Las credenciales no son dueñas de nada.** Ningún rol `LOGIN` posee tablas, vistas ni funciones. La propiedad del esquema queda en el DBA y la de las rutinas `SECURITY DEFINER` en un rol técnico `NOLOGIN` sin membresías (`rol_owner_codigo`).
2. **La lectura pasa por vistas y la escritura crítica por rutinas.** `rol_app_lectura` no toca tablas base; `rol_app_escritura` no recibe `INSERT`/`UPDATE`/`DELETE` sobre `pedido`, `pedido_detalle` ni `producto`. El pedido se registra con `sp_registrar_pedido`, que corre con los privilegios acotados de su propietario técnico.
3. **Todo privilegio se otorga dos veces: en el `GRANT` y en la verificación.** `sql/verificacion_roles.sql` contrasta el catálogo (`information_schema`, `has_*_privilege`, `pg_proc`, `pg_default_acl`, `\du`) contra la matriz esperada.

El resultado son **siete roles**: cuatro de grupo, uno técnico de propiedad y dos de conexión. Los cuatro de grupo y los dos de conexión son los exigidos por la consigna; `rol_owner_codigo` es el rol adicional que el equipo incorpora para que ninguna rutina `SECURITY DEFINER` se ejecute como superusuario.

---

## 2. Arquitectura de roles

### 2.1 Capas

```
                        ┌──────────────────────────────┐
   Personas / apps      │  app_web        admin_datos  │  LOGIN (credenciales)
                        └───────┬──────────────┬───────┘
                                │ membresía    │ grants directos
                        ┌───────▼──────────────▼───────┐
   Grupos de negocio    │ rol_app_lectura  rol_app_escritura │
                        │ rol_soporte      rol_reportes     │  NOLOGIN
                        └───────┬──────────────────────────┘
                                │ EXECUTE / SELECT
                        ┌───────▼──────────────────────────┐
   Rutinas              │ sp_registrar_pedido              │  SECURITY DEFINER
                        │ fn_autenticar / fn_resetear_password │
                        └───────┬──────────────────────────┘
                                │ propiedad
                        ┌───────▼──────────────────────────┐
   Rol técnico          │ rol_owner_codigo                 │  NOLOGIN, sin membresías
                        └──────────────────────────────────┘
```

### 2.2 Roles y propósito

| Rol | Tipo | Propósito | Por qué no más |
|---|---|---|---|
| `rol_app_lectura` | Grupo `NOLOGIN` | `SELECT` sobre `vw_productos_vigentes`, `vw_pedidos_cliente`, `vw_detalle_pedido`; `EXECUTE` sobre `fn_autenticar`. | No recibe tablas base, `usuario`, secuencias ni `CREATE`. |
| `rol_app_escritura` | Grupo `NOLOGIN` | `EXECUTE` sobre `sp_registrar_pedido`; `INSERT` por columna en `cliente`; `SELECT (id)` y `USAGE` sobre `cliente_id_seq`. | No recibe DML directo sobre `pedido`, `pedido_detalle` ni `producto`. |
| `rol_soporte` | Grupo `NOLOGIN` | `SELECT` por columna sobre `usuario` (sin `contrasena`), lectura de dos vistas y `EXECUTE` sobre `fn_resetear_password`. | No recibe `UPDATE` sobre `usuario` ni lectura del hash. |
| `rol_reportes` | Grupo `NOLOGIN` | `SELECT` sobre `mv_facturacion_categoria_mes` y `vw_detalle_pedido`. | No recibe `vw_pedidos_cliente`, tablas base ni escritura. |
| `rol_owner_codigo` | Técnico `NOLOGIN` | Propiedad de las tres rutinas `SECURITY DEFINER` y solo las columnas/objetos que éstas usan. | No inicia sesión, no tiene membresías, no puede `CREATE` al finalizar. |
| `app_web` | `LOGIN` | Hereda `rol_app_lectura` y `rol_app_escritura`. | Sin atributos administrativos ni membresía en soporte/reportes/admin. |
| `admin_datos` | `LOGIN` | `SELECT/INSERT/UPDATE` explícito sobre tablas de negocio; por columna en `usuario` (datos personales y baja lógica); `EXECUTE` sobre `sp_registrar_pedido`. | Sin `DELETE`, `TRUNCATE`, DDL ni `CREATEROLE`; no toca `contrasena`, no escribe `rol` y no resetea claves. |

### 2.3 Atributos comunes

Los siete roles se crean con `NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS`. Los `LOGIN` usan `PASSWORD NULL` y `CONNECTION LIMIT` (20 para `app_web`, 5 para `admin_datos`); la credencial se provisiona fuera del repositorio con `\password`.

---

## 3. Matriz de privilegios

Leyenda: **S** = `SELECT`, **I** = `INSERT`, **U** = `UPDATE`, **D** = `DELETE`, **X** = `EXECUTE`, **—** = sin privilegio. `(cols)` indica privilegio por columna.

| Objeto | `rol_app_lectura` | `rol_app_escritura` | `rol_soporte` | `rol_reportes` | `rol_owner_codigo` | `app_web` (efectivo) | `admin_datos` |
|---|---|---|---|---|---|---|---|
| `categoria` | — | — | — | — | — | — | S, I, U |
| `producto` | — | — | — | — | S(cols) + U(tabla)¹ | — | S, I, U |
| `cliente` | — | I(cols) + S(id) | — | — | S(id, activo) | I(cols) + S(id) | S, I, U |
| `pedido` | — | — | — | — | S(id) + I(cols) | — | S, I, U |
| `pedido_detalle` | — | — | — | — | I(cols) | — | S, I, U |
| `usuario` | — | — | S(cols) sin `contrasena` | — | S(cols) + U(`contrasena`) | — | S/I/U(cols) sin `contrasena`; `rol` solo lectura |
| `vw_productos_vigentes` | S | S (hereda) | — | — | — | S | S |
| `vw_pedidos_cliente` | S | S (hereda) | S | — | — | S | S |
| `vw_detalle_pedido` | S | S (hereda) | S | S | — | S | S |
| `mv_facturacion_categoria_mes` | — | — | — | S | — | — | S |
| `fn_autenticar(...)` | X | X (hereda) | — | — | dueño | X | — |
| `fn_resetear_password(...)` | — | — | X | — | dueño | — | — |
| `crypt` / `gen_salt` (pgcrypto) | — | — | — | — | X | — | — |
| `sp_registrar_pedido(...)` | — | X | — | — | dueño | X | X |
| Secuencias | — | `USAGE cliente_id_seq` | — | — | `USAGE pedido_id_seq` | `USAGE cliente_id_seq` | `USAGE, SELECT` en las cinco |
| Tipo `forma_pago_enum` | — | — | — | — | `USAGE` | — | — |
| Esquema `public` | `USAGE` | `USAGE` | `USAGE` | `USAGE` | `USAGE` | `USAGE` | `USAGE` |

¹ `sp_registrar_pedido` ejecuta `SELECT ... FOR UPDATE` sobre `producto`; PostgreSQL exige `UPDATE` a nivel de tabla para ese bloqueo, no alcanza el privilegio por columna.

### 3.1 Detalle de columnas sobre `usuario`

| Rol | `SELECT` | `INSERT` | `UPDATE` |
|---|---|---|---|
| `rol_soporte` | `id, nombre, apellido, mail, rol, activo, created_at` | — | — |
| `rol_owner_codigo` | `id, mail, contrasena, rol, activo` | — | `contrasena` |
| `admin_datos` | `id, nombre, apellido, mail, celular, rol, activo, created_at` | `nombre, apellido, mail, celular, activo` | `nombre, apellido, mail, celular, activo` |

`contrasena` nunca es legible por `rol_soporte`, `admin_datos` ni `app_web`. El único rol con `SELECT (contrasena)` es `rol_owner_codigo`, porque `fn_autenticar` compara el hash; es `NOLOGIN` y no puede consultarlo de forma interactiva.

---

## 4. Decisiones de diseño

### D1 — Lectura por vistas, no por tablas base

`rol_app_lectura` recibe `SELECT` solo sobre las tres vistas. Las vistas ya filtran columnas sensibles (`vw_pedidos_cliente` excluye `email` y `telefono`) y encapsulan la lógica de vigencia (`vw_productos_vigentes`). Otorgar `SELECT` sobre las tablas obligaría a repetir esos filtros en cada consulta y expondría `usuario`.

**Consecuencia:** un `SELECT * FROM producto` falla con `permission denied`, tal como exige el Requisito 3.5.

### D2 — Escritura transaccional por procedimiento

`rol_app_escritura` no tiene DML sobre `pedido`, `pedido_detalle` ni `producto`. Solo puede ejecutar `sp_registrar_pedido`, que valida cliente activo, stock, vigencia, calcula precios históricos y descuenta inventario de forma atómica. Si el procedimiento falla, no queda cabecera huérfana ni stock descontado.

**Trade-off:** la aplicación no puede hacer ajustes ad hoc (por ejemplo, corregir una cantidad). Esas operaciones quedan en `admin_datos` o en una nueva rutina revisada.

### D3 — Permiso por columna en `usuario` (caso obligatorio)

`rol_soporte` recibe exactamente:

```sql
GRANT SELECT (id, nombre, apellido, mail, rol, activo, created_at)
    ON TABLE public.usuario TO rol_soporte;
```

`contrasena` queda fuera del `GRANT`. Como PostgreSQL exige privilegio sobre **todas** las columnas para `SELECT *`, la consulta amplia falla; en cambio `SELECT id, nombre, mail FROM usuario` funciona. Esto demuestra el privilegio por columna de forma verificable y no solo declarativa.

### D4 — `fn_resetear_password` con `SECURITY DEFINER` endurecida

La función se define con:

- `SECURITY DEFINER` y `SET search_path = public, pg_temp`, para que el cuerpo no pueda ser secuestrado por objetos de `pg_temp` u otro esquema.
- `REVOKE ALL ... FROM PUBLIC` y `GRANT EXECUTE` solo a `rol_soporte`.
- Propietario `rol_owner_codigo`, que solo tiene `SELECT (id, activo)` y `UPDATE (contrasena)` sobre `usuario`, más `EXECUTE` sobre `crypt` y `gen_salt` (revocadas de `PUBLIC`).
- Validaciones de `p_usuario_id` nulo, `p_nueva` nula/vacía y usuario inexistente o inactivo.
- **Bloqueo de cuentas `ADMIN`:** `AND rol::text <> 'ADMIN'`. Sin esta condición, soporte podría resetear la clave del administrador y escalar verticalmente.

La función nunca lee ni devuelve el hash: solo escribe `crypt(p_nueva, gen_salt('bf'))`.

### D5 — `rol_owner_codigo`: propiedad sin superusuario

Si `sp_registrar_pedido` o `fn_autenticar` quedaran en propiedad del DBA superusuario, una inyección en su cuerpo tendría privilegios totales. El rol técnico:

- Es `NOLOGIN`, sin membresías y sin `CREATE` al final del script.
- Solo recibe las columnas y secuencias que las rutinas usan.
- Es propietario de las tres rutinas, de modo que `pg_proc.proowner` nunca es un superusuario.

**Trade-off:** `rol_owner_codigo` necesita `SELECT (contrasena)` para `fn_autenticar`. Es un privilegio inevitable mientras la autenticación se haga en SQL; se mitiga con `NOLOGIN`, sin membresías y con `search_path` fijo. Una alternativa futura es mover la verificación de hash a la aplicación.

### D6 — `admin_datos` sin `DELETE`, sin DDL y sin hash

La baja de Food Store es lógica (`activo = FALSE`), por lo que `DELETE` y `TRUNCATE` no forman parte de la operación normal. `admin_datos` recibe `SELECT, INSERT, UPDATE` explícitos (nunca `GRANT ALL`), sin `REFERENCES`, `TRIGGER` ni `CREATE ON SCHEMA`. Sobre `usuario`, el `GRANT` es por columna y deja afuera `contrasena` y la escritura de `rol`: un alta nace con `rol = 'USUARIO'` (DEFAULT) y `contrasena = NULL` (cuenta pendiente de activación), y soporte la activa con `fn_resetear_password`.

**Por qué (segregación de funciones):** la primera versión le daba `INSERT/UPDATE (rol)`, `INSERT (contrasena)` y `EXECUTE fn_resetear_password`. Combinados permitían degradar un `ADMIN`, resetearle la clave y volver a promoverlo (escalamiento vertical verificado, ex riesgo R2). Ahora quien administra datos no gestiona credenciales, quien gestiona credenciales (soporte) no cambia roles, y la promoción a `ADMIN` queda reservada al DBA.

### D7 — `ALTER DEFAULT PRIVILEGES` sin grants automáticos

La política se aplica para el dueño que ejecuta el script (`CURRENT_USER`):

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE <dueño> IN SCHEMA public
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE <dueño> IN SCHEMA public
    REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE <dueño>
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE <dueño>
    REVOKE USAGE ON TYPES FROM PUBLIC;
```

Detalle técnico: en PostgreSQL las tablas y secuencias **no** reciben privilegios de `PUBLIC` por defecto, por lo que esos dos `REVOKE` son una declaración de política y no generan filas en `pg_default_acl`. Las funciones **sí** reciben `EXECUTE` de `PUBLIC`, y los tipos `USAGE`; por eso sus `REVOKE` sí quedan registrados. Un `REVOKE ... IN SCHEMA` no puede quitar el privilegio global de `PUBLIC`, de ahí que funciones y tipos se revoquen sin cláusula de esquema.

No se otorgan privilegios automáticos a ningún rol de negocio: cada objeto nuevo exige un `GRANT` explícito y una revisión.

### D8 — Idempotencia segura

Antes de `DROP ROLE`, el script ejecuta `REASSIGN OWNED BY <rol> TO CURRENT_USER` y `DROP OWNED BY <rol>`. Así, si una ejecución anterior dejó objetos en propiedad de esos roles, se transfieren en lugar de borrarse. El script se probó dos veces consecutivas sobre la misma base sin errores ni pérdida de filas.

### D9 — `PASSWORD NULL` y secretos fuera de Git

Los roles `LOGIN` se crean sin contraseña. La provisión se hace con `\password app_web` / `\password admin_datos` o con un gestor de secretos. Esto evita repetir el antipatrón de TP3 (`rol_reportes_foodstore` con contraseña en texto plano en `views.sql`).

### D10 — `search_path` fijo en todas las rutinas elevadas

`sp_registrar_pedido`, `fn_autenticar` (todas las sobrecargas) y `fn_resetear_password` fijan `search_path = public, pg_temp`. El orden deja `public` antes que `pg_temp`, impide que una tabla temporal suplante a `usuario` o `producto` y hace que las referencias sin esquema resuelvan siempre a los objetos reales.

---

## 5. Mapa del script `sql/roles.sql`

| Sección | Contenido | Requisitos |
|---|---|---|
| 0 | Limpieza idempotente: `REASSIGN OWNED`, `DROP OWNED`, `DROP ROLE IF EXISTS` | R12.1, R12.2 |
| 1 | Creación de los cuatro roles de grupo y del rol técnico | R1.1, R1.3, R1.4 |
| 2 | Creación de `app_web` y `admin_datos` con `PASSWORD NULL` y `CONNECTION LIMIT` | R1.2, R1.4, R1.5 |
| 3 | `REVOKE ALL ON SCHEMA public FROM PUBLIC`; `USAGE` a los siete; `CREATE` temporal al técnico | R2.1, R2.2, R2.5 |
| 4 | Revocación de `PUBLIC` sobre tablas, vistas, secuencias y `fn_autenticar` | R2.3, R2.4 |
| 5 | `SELECT` de `rol_app_lectura` sobre las tres vistas | R3.1–R3.3 |
| 6 | `EXECUTE` del procedimiento, `INSERT` por columna, `SELECT (id)` y secuencia de cliente | R4.1–R4.6 |
| 7 | `REVOKE ALL` y `GRANT SELECT` por columna sobre `usuario` para soporte; vistas de pedidos | R5.1–R5.6 |
| 8 | `SELECT` de reportes sobre la vista materializada y `vw_detalle_pedido` | R6.1–R6.5 |
| 9 | Privilegios mínimos del rol técnico (columnas, secuencias, tipo, `pgcrypto`) | R9.5 |
| 10 | Hardening y transferencia de `sp_registrar_pedido` | R9.1–R9.3 |
| 11 | Creación, `REVOKE`, `GRANT` y transferencia de `fn_resetear_password` | R8.1–R8.10 |
| 11.b | Hardening y transferencia de todas las sobrecargas de `fn_autenticar` | R9.4 |
| 12 | DML explícito y privilegios por columna de `admin_datos` | R7.1–R7.7 |
| 13 | Membresías de `app_web` | R1.6, R1.7 |
| 14 | `ALTER DEFAULT PRIVILEGES` | R10.1–R10.5 |
| 15 | `REVOKE CREATE ON SCHEMA public FROM rol_owner_codigo` | R9.6 |
| 16 | `COMMENT ON ROLE` de los siete roles | R12.5 |

---

## 6. Plan de verificación

`sql/verificacion_roles.sql` se ejecuta con `psql -v ON_ERROR_STOP=1` y produce ocho bloques (con un sub-bloque 6.b para privilegios de ejecución):

1. **Atributos** (`pg_roles`): `rolcanlogin`, `rolsuper`, `rolcreatedb`, `rolcreaterole`, `rolreplication`, `rolbypassrls`, `rolconnlimit`.
2. **Membresías** (`pg_auth_members`): `app_web → rol_app_lectura, rol_app_escritura`; `rol_app_escritura → rol_app_lectura`; sin `admin_option`.
3. **Privilegios directos de tabla/vista** (`information_schema.role_table_grants`) filtrados por los siete roles.
4. **Privilegios por columna sobre `usuario`** (`information_schema.column_privileges`).
5. **Matriz de checks críticos** con `has_table_privilege`, `has_column_privilege` y `has_sequence_privilege`, que incluye privilegios heredados.
6. **Rutinas** (`pg_proc`): `prosecdef`, `proconfig`, `proowner`, y privilegios efectivos de `EXECUTE` por rol (bloque 6.b).
7. **Privilegios por omisión** (`pg_default_acl`).
8. **`\du`** para inspección visual.

### 6.1 Matriz esperada vs. obtenida

Salida de referencia capturada en un clúster PostgreSQL 17 aislado (ver `docs/verificacion_permisos.md`):

| Check | Esperado | Obtenido |
|---|---|---|
| `soporte_select_tabla_usuario` | `false` | `false` |
| `soporte_select_contrasena` | `false` | `false` |
| `soporte_select_mail` | `true` | `true` |
| `soporte_update_usuario` | `false` | `false` |
| `lectura_select_producto` | `false` | `false` |
| `lectura_select_vista` | `true` | `true` |
| `escritura_insert_pedido` | `false` | `false` |
| `escritura_update_pedido` | `false` | `false` |
| `escritura_delete_pedido` | `false` | `false` |
| `escritura_insert_email_cliente` | `true` | `true` |
| `escritura_returning_id_cliente` | `true` | `true` |
| `escritura_usage_seq_cliente` | `true` | `true` |
| `escritura_usage_seq_pedido` | `false` | `false` |
| `admin_delete_pedido` | `false` | `false` |
| `admin_select_contrasena` | `false` | `false` |
| `admin_update_contrasena` | `false` | `false` |
| `owner_codigo_select_contrasena` | `true` (justificado) | `true` |
| `owner_codigo_select_tabla_usuario` | `false` | `false` |
| `reportes_select_mv` | `true` | `true` |
| `reportes_select_usuario` | `false` | `false` |
| `app_web_hereda_lectura` | `true` | `true` |
| `app_web_select_usuario` | `false` | `false` |

### 6.2 Pruebas de comportamiento

Además de la matriz, se ejecutaron pruebas con `SET ROLE`:

| Escenario | Resultado |
|---|---|
| `rol_soporte`: `SELECT contrasena FROM usuario` | `permission denied for table usuario` |
| `rol_soporte`: `SELECT * FROM usuario` | `permission denied` (incluye `contrasena`) |
| `rol_soporte`: `UPDATE usuario SET mail = ...` | `permission denied` |
| `rol_soporte`: `SELECT fn_resetear_password(<usuario>, 'NuevaClave2026!')` | OK, actualiza el hash |
| `rol_soporte`: reset sobre cuenta `ADMIN` | excepción controlada, sin cambios |
| `rol_app_escritura`: `INSERT INTO cliente (...)` | OK, devuelve `id` |
| `rol_app_escritura`: `CALL sp_registrar_pedido(...)` | OK, inserta pedido y descuenta stock |
| `rol_app_escritura`: `UPDATE producto SET stock = ...` | `permission denied` |
| `rol_app_escritura`: `DELETE FROM cliente` | `permission denied` |
| `app_web`: `CREATE TABLE ...` | `permission denied for schema public` |
| `app_web`: `GRANT admin_datos TO ...` | rechazado (sin `ADMIN OPTION` / sin `CREATEROLE`) |
| `admin_datos`: `DELETE FROM pedido` | `permission denied` |
| `admin_datos`: `SELECT contrasena FROM usuario` | `permission denied` |
| `admin_datos`: `UPDATE usuario SET contrasena = ...` | `permission denied` |
| `admin_datos`: `UPDATE usuario SET rol = ...` | `permission denied` (corta la cadena del ex R2) |
| `admin_datos`: `SELECT fn_resetear_password(...)` | `permission denied for function` |
| `admin_datos`: `INSERT INTO usuario (nombre, apellido, mail)` | OK; nace `rol = 'USUARIO'`, `contrasena = NULL` |
| `app_web`: `SELECT * FROM fn_autenticar(mail, clave)` | OK con la clave correcta; 0 filas con una incorrecta |
| `rol_reportes`: `SELECT * FROM mv_facturacion_categoria_mes` | OK |
| `rol_reportes`: `SELECT * FROM usuario` | `permission denied` |
| `rol_owner_codigo`: `CREATE TABLE` | `permission denied for schema public` |

---

## 7. Riesgos residuales y límites aceptados

| # | Riesgo | Impacto | Mitigación actual | Recomendación |
|---|---|---|---|---|
| R1 | **Acceso horizontal**: ningún rol tiene RLS; `rol_soporte` y `admin_datos` ven todas las filas de `usuario`. | Un agente de soporte ve datos de todos los clientes. | Permisos por columna y por vista. | Evaluar `ROW LEVEL SECURITY` por sucursal/equipo si el dominio lo requiere. |
| R2 | **CORREGIDO.** La primera versión dejaba que `admin_datos` creara usuarios `ADMIN` o cambiara `rol`. Cadena verificada: degradar un `ADMIN` a `USUARIO`, resetear su clave con `fn_resetear_password`, volver a promoverlo y autenticarse con la clave conocida. | Escalamiento vertical desde una credencial de administración de datos. | `admin_datos` ya no tiene `INSERT/UPDATE (rol)`, `INSERT (contrasena)` ni `EXECUTE fn_resetear_password` (D6). `sql/test_roles.sql` prueba que la cadena se corta en el primer paso. | Pendiente para la Parte B: auditar los cambios de `usuario.rol`, que solo hace el DBA. |
| R3 | **`rol_owner_codigo` puede leer hashes** porque `fn_autenticar` los compara. | Si otra rutina maliciosa se le asigna como propietaria, podría exfiltrarlos. | `NOLOGIN`, sin membresías, sin `CREATE`, `search_path` fijo. | Migrar la verificación de hash a la aplicación o usar un rol técnico por rutina. |
| R4 | **`FOR UPDATE` exige `UPDATE` de tabla sobre `producto`** para el rol técnico. | El propietario técnico podría actualizar cualquier columna de `producto` si se le inyectara código. | Solo actúa dentro del procedimiento; sin `LOGIN`. | Aceptado: PostgreSQL no permite `FOR UPDATE` con privilegio por columna. |
| R5 | **Roles de clúster, no de base**: `DROP ROLE` falla si otra base usa el mismo nombre. | El script no es portable a un clúster compartido sin limpieza por base. | `REASSIGN`/`DROP OWNED` en la base actual. | Usar un clúster dedicado o ejecutar la limpieza en cada base. |
| R6 | **`rol_reportes_foodstore` de TP3** sigue existiendo con `LOGIN` y contraseña hardcodeada en `views.sql`. | Credencial histórica con `SELECT` sobre `vw_pedidos_cliente`; no forma parte del esquema nuevo. | Se documenta como hallazgo. | `DROP ROLE rol_reportes_foodstore` o rotar su clave y migrarla a `rol_reportes`. |
| R7 | **`admin_datos` puede leer todos los datos de negocio**, incluidos los personales de `cliente`. | Exposición masiva si la credencial se compromete. | Sin `DELETE`, sin DDL, sin hash, `CONNECTION LIMIT 5`. | Monitorear `log_statement`, aplicar RLS y revisar periódicamente los `GRANT`. |
| R8 | **La política de `ALTER DEFAULT PRIVILEGES` depende del dueño que ejecuta el script.** | Si otro rol crea tablas, no hereda la política. | Se usa `CURRENT_USER`. | Repetir el bloque para cada rol que cree objetos, o centralizar el DDL en un único dueño. |
| R9 | **Los `GRANT` por columna no cubren `SELECT *`** y pueden sorprender a un desarrollador. | Una consulta nueva con `*` falla en producción. | Documentado y verificado. | Usar listas explícitas de columnas en el código de la aplicación. |
| R10 | **CORREGIDO.** `crypt` y `gen_salt` de pgcrypto eran ejecutables por `PUBLIC`; cualquier rol podía generar hashes bcrypt. | Facilitaba que `admin_datos` creara un usuario `ADMIN` con una clave conocida. | `roles.sql` §9 revoca `EXECUTE` de `PUBLIC` y lo otorga solo a `rol_owner_codigo`; `fn_autenticar` y `fn_resetear_password` siguen funcionando porque corren como ese dueño (bloque 6.c de la verificación). | Repetir el `REVOKE` si se reinstala o actualiza la extensión. |

---

## 8. Alternativas descartadas

| Alternativa | Por qué se descartó |
|---|---|
| `GRANT ALL ON ALL TABLES IN SCHEMA public TO app_web` | Viola POLP: da `DELETE`, `TRUNCATE`, `REFERENCES` y `TRIGGER` sin necesidad. |
| `GRANT SELECT ON usuario TO rol_soporte` | Expone `contrasena`; el requisito exige privilegio por columna. |
| `GRANT INSERT, UPDATE ON pedido, pedido_detalle, producto TO rol_app_escritura` | Permite manipular stock y precios históricos por fuera del procedimiento. |
| Dejar las rutinas en propiedad del superusuario | Una inyección en el cuerpo se ejecuta con privilegios totales. |
| Crear un rol `LOGIN` por cada función de negocio | Multiplica credenciales y superficie de ataque; las membresías resuelven lo mismo. |
| Confiar solo en `information_schema.role_table_grants` | No muestra privilegios por columna, herencia ni vistas materializadas; se complementa con `has_*_privilege`. |
| `REVOKE ... IN SCHEMA public` para funciones | No quita el `EXECUTE` global de `PUBLIC`; debe hacerse sin `IN SCHEMA`. |

---

## 9. Trazabilidad requisitos → diseño

| Requisito | Secciones del diseño |
|---|---|
| R1 — Modelo de roles, atributos y membresías | §2, §3, D9 |
| R2 — Acceso al esquema y línea base | §3, §5 (secciones 3–4) |
| R3 — `rol_app_lectura` | §3, D1 |
| R4 — `rol_app_escritura` | §3, D2 |
| R5 — `rol_soporte` | §3.1, D3 |
| R6 — `rol_reportes` | §3, D1 |
| R7 — `admin_datos` | §3, D6 |
| R8 — `fn_resetear_password` | D4 |
| R9 — Hardening de rutinas | D5, D10 |
| R10 — Objetos futuros | D7 |
| R11 — Verificación | §6 |
| R12 — Idempotencia y documentación | D8, §5 (secciones 0 y 16) |

---

## 10. Cómo aplicar y verificar

```bash
# 1. Aplicar el esquema (como DBA o dueño del esquema)
psql -h localhost -U postgres -d foodstore -v ON_ERROR_STOP=1 -f TP5/sql/roles.sql

# 2. Provisionar credenciales fuera de Git
psql -h localhost -U postgres -d foodstore -c '\password app_web'
psql -h localhost -U postgres -d foodstore -c '\password admin_datos'

# 3. Auditar privilegios
psql -h localhost -U postgres -d foodstore -v ON_ERROR_STOP=1 \
     -f TP5/sql/verificacion_roles.sql
```

La salida esperada de la verificación se conserva en `TP5/docs/verificacion_permisos.md`.
