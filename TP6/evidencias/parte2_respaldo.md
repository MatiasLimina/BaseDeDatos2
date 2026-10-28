# Parte 2 — Pruebas de `backup_foodstore.ps1`

El script se ejecutó a mano el 28/10/2026 contra `foodstore` (PostgreSQL 17.11, `localhost:5432`), con PowerShell 5.1:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\backup_foodstore.ps1
```

| # | Caso | Cómo se provocó | Resultado esperado | Observado |
|---|---|---|---|---|
| 1 | Respaldo normal | Sin parámetros | Código 0, `.dump` y `.counts.csv`, línea `OK` | ✅ Código 0, 3,7 MB en 0,9 s, `pg_restore --list` lee 53 entradas |
| 2 | Base inexistente | `-Database no_existe` | Código 1, `ERROR`, sin archivos | ✅ |
| 3 | Sin credencial en `pgpass.conf` | `-User sin_credencial` | Código 1 **sin quedar esperando una contraseña** (`-w`) | ✅ `fe_sendauth: no password supplied`, al instante |
| 4 | Tabla bloqueada antes de los conteos | Otra sesión con `LOCK TABLE cliente IN ACCESS EXCLUSIVE MODE`; `-LockWaitTimeout 2s` | Código 1 a los 2 s, sin archivos | ✅ `lock_timeout` cancela el `COUNT(*)` |
| 5 | `pg_dump` falla después de los conteos | Un `pg_dump.cmd` antepuesto en el `PATH` toma el bloqueo sobre `cliente` y luego llama al `pg_dump` real; `-LockWaitTimeout 2s` | Código 1, `ERROR` con el mensaje de `pg_dump`, **el `.counts.csv` ya escrito se borra** | ✅ |
| 6 | Vista materializada bloqueada | Otra sesión con `REFRESH MATERIALIZED VIEW` sin confirmar; `-LockWaitTimeout 2s` | Lo ideal sería que falle a los 2 s | ⚠️ **Espera hasta que se libera el bloqueo** (11,6 s). Es un límite de `pg_dump`, ver abajo |

Archivo generado y conteos: [`parte2_archivo_generado.txt`](parte2_archivo_generado.txt). Log completo de las corridas: [`parte2_backup_foodstore.log`](parte2_backup_foodstore.log).

## Defectos encontrados al probar

1. **`$PSScriptRoot` vacío en `param()`.** En PowerShell 5.1 todavía no tiene valor cuando se evalúan los valores por defecto, así que la primera corrida terminó con `Join-Path: ... cadena vacía` antes de respaldar nada. Las carpetas pasaron a resolverse después de `param()`.
2. **Acentos desfigurados en el log** (`fall¾ la conexi¾n`). Los clientes de PostgreSQL escriben en la página de códigos ANSI (1252) y PowerShell los decodifica como OEM (850). Se corrigió pidiendo los mensajes del cliente en inglés (`LC_MESSAGES=C`) y los del servidor en UTF-8 (`PGCLIENTENCODING`), y decodificando la salida como UTF-8. Queda un resto: el `FATAL` de conexión (caso 2) llega antes de que se negocie la codificación y sus comillas `«»` siguen saliendo mal.
3. **Un respaldo podía quedar colgado sin límite.** Si otra sesión bloquea una tabla, tanto el `COUNT(*)` como `pg_dump` esperan para siempre. Para los conteos alcanza con `lock_timeout` (caso 4). En `pg_dump` no sirve, porque al conectarse pone `lock_timeout = 0`. Se usa entonces `--lock-wait-timeout` (caso 5), que solo cubre su `LOCK TABLE` inicial, del que quedan afuera las vistas materializadas (caso 6). Ese resto queda **mitigado, no resuelto**, por el tiempo máximo de 30 min de la tarea programada (`SPEC_U6.md`). Cuando el Programador de tareas mata el proceso, el `catch` no llega a ejecutarse: no hay línea `ERROR` en el log y los archivos parciales quedan en el disco, así que la falla solo aparece en el historial de la tarea.
4. **Prueba mal armada (del lado de la prueba, no del script).** El primer intento del caso 6 usaba `LOCK TABLE` sobre la vista materializada. PostgreSQL no lo permite, pero el error se perdía porque la salida de esa sesión se descartaba, y la prueba "pasaba" sin bloquear nada. Desde entonces, cada prueba de bloqueo comprueba en `pg_locks` que el bloqueo exista antes de lanzar el respaldo.

## Revisión antes del commit

Un segundo agente de revisión, de solo lectura, encontró además:

5. **Mensajes mezclados con los conteos.** El `.counts.csv` se armaba con la salida completa de `psql`, que incluye stderr. Un `WARNING` en una corrida exitosa (por ejemplo, un aviso de versión de collation) habría quedado como una fila más y la comparación de la restauración habría fallado. Ahora solo se guardan las líneas `tabla;número` y se exige que sean exactamente 5. Se probó el filtro con un `WARNING` intercalado.
6. **Conteos y respaldo de instantáneas distintas.** Se documentó en `SPEC_U6.md` como condición de la validación.
7. **`[Console]::OutputEncoding` fuera del `try`.** Si fallaba sin consola, el script terminaba sin escribir en el log. Pasó adentro del `try`.
