# Informe de incidente — simulacro de acceso indebido (Unidad 5, Parte C)

> El simulacro se ejecutó **solo** contra el clúster de desarrollo propio (PostgreSQL 17, puerto `55432`, base `foodstore_tp5`). Ningún paso se dirigió a sistemas de terceros ni a bases de otros equipos.

## 1. Qué se ejecutó (C.1)

Script: `sql/simulacro_incidente.sql`, corrida oficial `20261028T152428`. Escenario: se filtró la credencial de la aplicación (`app_web`) y el atacante la usa con `psql`.

| # | Acción del atacante (lo que realmente se ejecutó) | Hora (`-03`) | Resultado |
|---|---|---|---|
| 1 | Conexión como `app_web` con la clave filtrada | 15:24:28.193 | Autenticado (`scram-sha-256`) |
| 2 | 5 llamadas a `fn_autenticar('cuenta7@…', clave)` con `123456`, `password`, `foodstore`, `FoodStore2026` y `FoodStore#2026` | .205 – .218 | 5 fallidas |
| 3 | 6.ª llamada con la clave correcta (`FoodStore#7`) | .221 | Éxito: `usuario_id=7`, rol `USUARIO` |
| 4 | `SELECT * FROM usuario;` y `SELECT id, nombre, apellido, mail, celular FROM usuario;` | .221 – .222 | `permission denied for table usuario` |
| 5 | `GRANT admin_datos TO app_web;` | .222 | `permission denied to grant role "admin_datos"` |
| 6 | `SET ROLE admin_datos;` | .222 | `permission denied to set role "admin_datos"` |
| 7 | `UPDATE usuario SET rol = 'ADMIN' WHERE mail = 'cuenta7@…';` | .222 | `permission denied for table usuario` |
| 8 | Desconexión | .261 | Sesión de 87 ms |

Las claves de la tabla son las que **se ejecutaron**. No aparecen en el log, y eso es intencional (ver §3).

## 2. ¿El escalamiento falló? (C.2)

**Sí.** Al terminar, el DBA verificó desde otra conexión que `pg_has_role('app_web', 'admin_datos', 'MEMBER') = false` y que el rol de la cuenta 7 seguía siendo `USUARIO`. Si el escalamiento hubiera funcionado, el script habría terminado con `ERROR: HALLAZGO: el escalamiento NO falló ...`.

Para comprobar que esa verificación no es decorativa, se forzó a mano `GRANT admin_datos TO app_web` y se volvió a correr el simulacro: el script se detuvo con `HALLAZGO` (y después se revirtió el `GRANT`). En esa prueba apareció defensa en profundidad: aun siendo miembro de `admin_datos`, el atacante **no** pudo promover la cuenta a `ADMIN`, porque después de la corrección R2 (Parte A) `admin_datos` ya no tiene `UPDATE (rol)`.

## 3. Hallazgo durante el simulacro: el log guardaba las claves

Con `log_statement = 'mod'`, las llamadas a `fn_autenticar` (son `SELECT`) no dejan rastro (informe de auditoría, §3). Para hacerlas visibles, `fn_autenticar` registra cada intento.

La primera versión usaba `RAISE LOG`. En el log del servidor, el nivel LOG supera `log_min_error_statement`, así que PostgreSQL agregaba una línea `STATEMENT:` con la sentencia completa: **las seis claves probadas, incluida la correcta, quedaron en texto plano** en la corrida `20261028T152221`. Se detectó al leer ese log crudo, antes de anonimizarlo o de entregarlo a la IA. El test de la Parte A no lo había detectado porque armaba la clave concatenando, de modo que nunca aparecía literal en la sentencia.

**Corrección** (commit `bf5edf0`): el registro pasa a `RAISE WARNING`, que queda por debajo de `log_min_error_statement` y no arrastra `STATEMENT`, con `client_min_messages = error` en la función para no avisarle al cliente. El test ahora usa la clave como literal y falla si llega al log. La corrida oficial `20261028T152428` no contiene ninguna de las seis claves (verificado con `grep`). La corrida con la fuga se descartó como evidencia; queda solo en el log del clúster de pruebas.

## 4. Anonimización (C.3)

`scripts/anonimizar_log.py` sobre el fragmento crudo (39 líneas) → `docs/log_simulacro_anonimizado.txt` (29 líneas):

| Qué | Cómo | Por qué |
|---|---|---|
| Mails (`cuenta7@foodstore.test`) | → `usuario7@ejemplo.test`, con el criterio de `usuario_anon` (`'usuario' \|\| id \|\| '@ejemplo.test'`), a partir de un mapa generado desde la base | Dato personal. Se conserva la correspondencia con `usuario_id=7`, igual que en `usuario_anon`. |
| Rutas del servidor (`C:/Users/<usuario>/...`) | → `<PGDATA>` | Exponían el usuario del sistema operativo. |
| Sesiones del DBA (marcadores `TP5-C`, verificación final) | Se quitan las 10 líneas | Son el andamiaje del simulacro: le darían a la IA un contexto que el incidente real no tendría. |
| Fechas, horas, PIDs, ids de sesión, roles, `::1`, nombre de la base | Se conservan | Hacen falta para reconstruir la secuencia; no identifican a una persona. |

Verificación: 0 coincidencias de `foodstore.test`, del nombre de usuario del sistema, de `user=postgres` y de `TP5-C` en el archivo anonimizado. Ninguna clave.

## 5. Contraste: la IA frente a lo ejecutado (C.5)

Respuesta completa en `docs/ia/opencode_reconstruccion_incidente.md` (OpenCode, `gemini-3.5-flash`, sin acceso a nada más que el log).

### Lo que acertó

- La **secuencia completa** y su orden: conexión, 5 intentos fallidos, éxito en el 6.º, dos lecturas de `usuario`, `GRANT`, `SET ROLE` y `UPDATE ... rol = 'ADMIN'`, todo con el resultado correcto.
- Horas, PID, id de sesión y duración (87 ms), tomados bien del log.
- Que el control de acceso del motor **contuvo** el ataque: ninguna lectura ni escalamiento tuvo éxito.
- Que hay que rotar la clave de `app_web` y forzar el cambio de la clave de la cuenta 7.

### Lo que omitió

1. **Que el compromiso principal es la credencial `app_web`.** Su diagnóstico dice "ataque exitoso a nivel de aplicación: se comprometieron las credenciales de usuario7". La cuenta 7 es la consecuencia; la causa es que alguien tenía la credencial de la base de la aplicación y la usó con `psql` (`application_name=psql`), algo que la aplicación legítima nunca hace. La IA lo menciona como "investigar cómo el atacante ejecutó la conexión", pero no lo pone como hallazgo central ni le da prioridad uno.
2. **Que el ritmo prueba la automatización.** Reporta "5 intentos en 13 ms" y una sesión de 87 ms, pero no concluye que es un script (ningún humano escribe a esa velocidad), un dato que sí cambia la respuesta: hay una herramienta o un código preparado, no un error de tipeo.
3. **Los límites del propio log.** No advierte que con `log_statement = 'mod'` una lectura **exitosa** no se registra. `app_web` sí puede leer `vw_pedidos_cliente` (que incluye nombres de clientes) y esa lectura no dejaría rastro (probado en la Parte B). Por eso "no hubo extracción de datos" no se puede afirmar solo con este log.

### Afirmaciones que el log no sustenta

1. **"Intento de reconocimiento y extracción de datos ... Falló"** y "ataque fallido a nivel de base de datos": el log solo prueba que fallaron las sentencias **registradas**. Que no se haya leído nada más es una inferencia que el log no puede respaldar (omisión 3). En este caso es cierto porque el equipo sabe lo que ejecutó; la IA no tenía cómo saberlo.
2. **"Restringir permisos de ejecución de herramientas de cliente SQL en el servidor de aplicación":** supone que la conexión vino del servidor de aplicación. El log dice `client=::1`, o sea, **el mismo host que el servidor de base de datos**. Nada en el log habla de un servidor de aplicación separado.
3. **"Invalidar cualquier token o sesión activa asociada al usuario_id=7":** el log no muestra tokens ni sesiones de la aplicación. Es una recomendación genérica, no una lectura del log.
4. **"Se comprometieron las credenciales ... por fuerza bruta":** el patrón 5 fallos + 1 éxito lo sugiere fuertemente, pero el log no muestra las claves probadas (a propósito, §3). Que fuera un diccionario y no una clave conocida que se tipeó mal es una hipótesis razonable, no un hecho registrado.

No cometió errores de fecha ni inventó pasos: todo lo que describe como ocurrido está en el log. Sus fallas son de **jerarquía** (qué es la causa y qué la consecuencia) y de **alcance** (afirmar lo que el log no puede ver).

## 6. Decisión de contención del equipo (C.6)

> Esta decisión es **del equipo**, tomada a partir de la evidencia de §1–§5 y confirmada el 2026-10-28. No es una ejecución automática de lo que sugirió la IA: se tomaron algunas de sus propuestas, se descartaron otras y se agregaron medidas que la IA no planteó. En este simulacro las medidas quedan documentadas, no aplicadas, porque el atacante era el propio equipo.

| # | Medida | Por qué | Origen |
|---|---|---|---|
| 1 | **Rotar ya la clave de `app_web`** (`\password app_web` o el gestor de secretos), actualizar la aplicación y cortar las sesiones abiertas de `app_web` con `application_name = 'psql'` (`pg_terminate_backend`). | La credencial de la aplicación es el compromiso raíz (omisión 1). Mientras siga válida, el atacante puede volver. | IA (como punto 2) + equipo (prioridad 1) |
| 2 | **Restringir `app_web` en `pg_hba.conf`** a la dirección de la aplicación y quitarla de `::1`. | El atacante entró desde el host del servidor de base de datos; la aplicación no necesita conectarse desde ahí. | Equipo |
| 3 | **Forzar el cambio de clave de la cuenta 7** con `fn_resetear_password` (rol de soporte) y avisarle al titular. | Su clave quedó adivinada. No se da de baja la cuenta (`activo = false`) porque el titular es víctima, no atacante. | IA + equipo (sin baja) |
| 4 | **No revertir roles ni membresías.** | La verificación C.2 muestra que no cambió nada: `app_web` no es miembro de `admin_datos` y la cuenta 7 sigue siendo `USUARIO`. Revertir algo que no ocurrió sería actuar sin evidencia. | Equipo |
| 5 | **No bloquear el origen por IP.** | El origen es `::1` (localhost): bloquearlo cortaría también al DBA. La medida correcta es la 2 más investigar quién tiene acceso al host. | Equipo (descarta un "bloquear el origen" automático) |
| 6 | **Asumir el peor caso en las lecturas** y tratar como expuestos los datos que `app_web` puede leer (`vw_pedidos_cliente`: nombre y apellido de los clientes y sus pedidos). En adelante, auditar los `SELECT` sobre vistas con datos personales (pgaudit `READ` por objeto). No subir `log_statement` a `all`. | Con `mod` no se puede saber si `app_web` leyó esa vista (omisión 3), y en este servidor tampoco hay `pg_stat_statements` instalada, así que no existe ningún registro de lecturas que revisar. `all` registraría todas las consultas, con sus datos personales. | Equipo |
| 7 | **Limitar intentos en `fn_autenticar`** (bloqueo temporal tras N fallos) y alertar ante ráfagas de `fn_autenticar: intento fallido`. | 5 intentos en 13 ms: sin límite, el diccionario no tiene freno. | IA (mediano plazo) |
| — | *Descartado:* "restringir clientes SQL en el servidor de aplicación". | Se basa en una suposición que el log no sustenta (afirmación no sustentada 2). | — |
