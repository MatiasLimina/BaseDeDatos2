# Informe de auditoría — Food Store (Unidad 5, Parte B)

## 1. Configuración del servidor (B.1)

### Entorno

| Dato | Valor |
|---|---|
| Motor | PostgreSQL 17.11 (Windows), compatible con el mínimo exigido (16+) |
| Servidor | Clúster de desarrollo propio, aislado, puerto `55432` |
| Base | `foodstore_tp5`, armada con `Proyecto_Integrador/database/` + `sql/usuario_autenticacion.sql` + `sql/roles.sql` |
| Script aplicado | `sql/auditoria_config.sql` (`ALTER SYSTEM`) y reinicio con `pg_ctl restart` |

### 1.1 Parámetros modificados

| Parámetro | Antes | Después | Para qué |
|---|---|---|---|
| `log_connections` | `off` | `on` | Registra cada intento de conexión, cómo se autenticó y qué regla de `pg_hba.conf` se aplicó. |
| `log_disconnections` | `off` | `on` | Registra el cierre de cada sesión con su duración. |
| `log_statement` | `none` | `mod` | Registra DDL y `INSERT`/`UPDATE`/`DELETE`/`TRUNCATE`/`COPY FROM`. No registra `SELECT`. |
| `log_line_prefix` | `%m [%p] ` | `%m [%p] sesion=%c user=%u db=%d app=%a client=%h ` | Sin este cambio el log no dice **quién** (`%u`), **en qué base** (`%d`), **con qué programa** (`%a`) ni **desde dónde** (`%h`). `%c` permite unir las líneas de una misma sesión. |
| `logging_collector` | `off` | `on` | Hace que el servidor escriba su propio archivo de log en lugar de depender de la salida de error del proceso. Requiere reinicio. |
| `log_directory` | `log` | `log` | Sin cambios: el log queda en `<PGDATA>/log/`. |
| `log_filename` | `postgresql-%Y-%m-%d_%H%M%S.log` | `postgresql-%Y-%m-%d.log` | Un archivo por día. |
| `log_file_mode` | `0640` | `0600` | Solo el usuario del sistema operativo dueño del servidor puede leerlo (ver §4). |

`ALTER SYSTEM` escribe estos valores en `postgresql.auto.conf`. Se revierten con `ALTER SYSTEM RESET <parámetro>` y un reinicio.

### 1.2 `pg_hba.conf`

Con autenticación `trust` no puede existir un "inicio de sesión fallido": el servidor acepta a cualquiera. Por eso se exige `scram-sha-256` a todos los roles por TCP y solo el DBA local conserva `trust`. Las reglas `host` quedaron así:

```text
host    all             postgres        127.0.0.1/32            trust
host    all             all             127.0.0.1/32            scram-sha-256
host    all             postgres        ::1/128                 trust
host    all             all             ::1/128                 scram-sha-256
```

`sql/auditoria_test.sql` comprueba esta configuración antes de ejecutar nada (sección 1) y aborta si falta algo. Antes de aplicarla, el script falló en la primera aserción (`log_connections debe estar activo`).

## 2. Secuencia de prueba y fragmento de log (B.2)

`sql/auditoria_test.sql` (corrida `20261028T151117`) se conecta de verdad como cada rol:

1. **Lectura:** `app_web` consulta 3 productos de `vw_productos_vigentes`.
2. **Inserción:** `app_web` da de alta un cliente (datos sintéticos).
3. **Actualización:** `admin_datos` corrige el teléfono de ese cliente.
4. **Inicio de sesión fallido:** `app_web` intenta conectarse con una clave incorrecta.

Las claves de `app_web` y `admin_datos` se generan al azar en cada corrida, no se guardan y se asignan con `log_statement = 'none'` para esa transacción. La corrida no dejó ningún `ALTER ROLE` ni ninguna clave en el log; se verificó con `grep`.

El fragmento completo, sin editar, está en `docs/log_auditoria_prueba.txt` (27 líneas entre los marcadores `TP5-B inicio` y `TP5-B fin`). Correspondencia con cada paso:

| Paso | Líneas del log | ¿Quedó registrado? |
|---|---|---|
| Conexión de `app_web` | `connection received` → `connection authenticated: identity="app_web" method=scram-sha-256` → `connection authorized` | Sí |
| 1. Lectura | — | **No.** `mod` no registra `SELECT`. |
| 2. Inserción | `user=app_web ... LOG:  statement: INSERT INTO cliente (...) VALUES ('Prueba', 'Auditoria', ...)` | Sí, con los valores literales |
| Conexión de `admin_datos` | `connection authenticated: identity="admin_datos" ...` | Sí |
| 3. Actualización | `user=admin_datos ... LOG:  statement: UPDATE cliente SET telefono = '+54 261 555-1111' WHERE id = 20006;` | Sí |
| 4. Login fallido | `user=app_web ... FATAL:  password authentication failed for user "app_web"` + `DETAIL: Connection matched ... line 123` | Sí |
| Cierres de sesión | `disconnection: session time: 0:00:00.076 user=app_web ...` | Sí |

## 3. Qué sirve para auditar y qué queda afuera (B.3)

### Lo útil: quién, qué, cuándo y desde dónde

- **Quién:** `user=app_web` / `user=admin_datos` en cada línea, y `identity="app_web" method=scram-sha-256` dice además **cómo** se autenticó. El login fallido identifica el rol atacado (`password authentication failed for user "app_web"`).
- **Qué:** el texto completo de cada modificación (`INSERT INTO cliente ...`, `UPDATE cliente SET telefono ... WHERE id = 20006`).
- **Cuándo:** marca de tiempo con milisegundos y zona (`2026-10-28 15:11:17.324 -03`) y duración de cada sesión en la desconexión.
- **Desde dónde:** `client=::1` y el puerto de origen (`host=::1 port=54053`), la aplicación (`app=tp5_auditoria_test`) y la regla de `pg_hba.conf` que se aplicó.
- **Correlación:** `sesion=6ae23ac5.6204` agrupa todas las líneas de una conexión; con eso se reconstruye la secuencia login → operación → desconexión.

### Lo que este mecanismo no ve

1. **Las lecturas.** El `SELECT` del paso 1 no dejó rastro. Una extracción masiva de datos personales (el escenario de la Parte C) pasa desapercibida con `mod`. Subir a `all` la registraría, pero también volcaría al log cada consulta, con sus datos.
2. **Lo que pasa dentro de rutinas.** Se probó aparte, dentro de una transacción revertida, `SELECT fn_resetear_password(2, ...)` como `rol_soporte` y `CALL sp_registrar_pedido(...)` como `rol_app_escritura`. El pedido se registró (`Pedido #200002 registrado exitosamente`), pero entre los marcadores del experimento el log no tiene **ninguna** línea de ninguna de las dos operaciones: ni el cambio de contraseña ni el pedido con su descuento de stock. Las dos se invocan con `SELECT`/`CALL`, que `mod` no clasifica como modificación, y `log_statement` solo ve la sentencia de nivel superior, no el `UPDATE` que corre adentro.
3. **Los inicios de sesión fallidos de la aplicación.** `fn_autenticar` con una clave incorrecta devuelve 0 filas. Para el motor es un `SELECT` exitoso, no un error, así que no queda registro. El log solo ve los logins fallidos **del motor** (roles `LOGIN`), no los de los usuarios de Food Store.
4. **El antes y el después.** El `UPDATE` muestra el valor nuevo, pero no el teléfono anterior ni cuántas filas cambió. El `INSERT` muestra la expresión, pero no el `id` que se generó.
5. **El resultado de la transacción.** La sentencia se registra al ejecutarse; el log no dice si después hubo `COMMIT` o `ROLLBACK`.
6. **El cambio de identidad dentro de la sesión.** `SET ROLE` no se registra con `mod`: todas las líneas del experimento figuran como `user=postgres`, aunque las operaciones corrieron como `rol_soporte` y `rol_app_escritura`.

### Qué agregaría pgaudit (nociones)

La extensión **pgaudit** produce registros de auditoría (`AUDIT: SESSION,...` / `AUDIT: OBJECT,...`) en el mismo log, con más granularidad:

- **Por clase de sentencia** (`pgaudit.log = 'read, write, function, role, ddl'`): puede registrar `READ` (los `SELECT` que hoy no se ven), `FUNCTION` (llamadas a rutinas) y `ROLE` (`GRANT`, `REVOKE`, `ALTER ROLE`), por separado.
- **Sentencias anidadas:** registra también lo que se ejecuta dentro de funciones y procedimientos. El `UPDATE usuario` dentro de `fn_resetear_password` y los `INSERT` de `sp_registrar_pedido` aparecerían.
- **Auditoría por objeto** (`pgaudit.role`): solo registra el acceso a las tablas que se le indican (por ejemplo, cada lectura de `usuario.contrasena` o de `cliente.email`), sin volcar todo el tráfico.
- **Nombre del objeto y tipo de acción** en cada registro, lo que facilita filtrar.

Aun así, pgaudit no guarda el valor anterior de cada fila. Para el "detalle fila por fila" con valores previos y nuevos se necesitan disparadores de auditoría o decodificación lógica (CDC).

## 4. ¿El log es un activo sensible? (B.4)

Sí. El fragmento capturado contiene datos personales en texto plano (el `INSERT` deja nombre, email y teléfono del cliente), los nombres de los roles con privilegios, las direcciones de origen y hasta rutas internas del servidor (la ruta completa de `pg_hba.conf`, que incluye el usuario del sistema). Con `log_statement` en `ddl`, `mod` o `all`, también podría guardar contraseñas en claro si alguien ejecuta `ALTER ROLE ... PASSWORD 'clave'`; por eso el script desactiva el registro para esa transacción. Solo debería leerlo la cuenta del sistema operativo que ejecuta PostgreSQL (archivo `0600` dentro de `PGDATA`, o en Windows una ACL de NTFS limitada a la cuenta del servicio, donde `log_file_mode` no aplica) y, dentro del motor, solo un superusuario o un miembro de `pg_read_server_files` (por ejemplo, con `pg_read_file`). Ningún rol de la aplicación (`app_web`, `admin_datos`, `rol_soporte`) debe tener acceso; los auditores deberían trabajar sobre una copia exportada a un repositorio de solo escritura con retención definida.
