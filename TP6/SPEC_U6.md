# SPEC U6 — Plan de mantenimiento, respaldo y recuperación de Food Store

Integrantes: Matias Limina - Nicolas Monjelardi - Lautaro Aguero

**Entorno.** PostgreSQL 16 o superior (laboratorio: 17) en `localhost:5432`, usuario `postgres`. Base principal: `foodstore`. Base de ensayo: `foodstore_restore_test`. Scripts en PowerShell (Windows), ejecutados desde `TP6/`; copias en `TP6/backups/` y registros en `TP6/logs/`. Ninguna de las dos carpetas se versiona.

## Tareas automatizadas

| Tarea | Script | Frecuencia | Condición de éxito (evidencia) |
|---|---|---|---|
| Respaldo | `backup_foodstore.ps1` | Diaria, 02:00 | `pg_dump` termina con código 0; `backups/foodstore_AAAAMMDD_HHMMSS.dump` existe, pesa más de 0 bytes y `pg_restore --list` lo lee; el log tiene una línea `OK` con el archivo, el tamaño y la duración. |
| Chequeo de salud | `health_check.sql` | Diaria, después del respaldo | Corre con `ON_ERROR_STOP` sin errores y su salida queda en `logs/`. Controles: tamaño de la base, conexiones y transacciones, estado de las tablas (tuplas vivas/muertas, último autovacuum/autoanalyze) y consultas activas. |
| Revisión de mantenimiento | `maintenance.sql` | Semanal, domingo | Muestra tuplas muertas frente al umbral de autovacuum, la configuración de autovacuum y la antigüedad de las estadísticas. Solo ejecuta `VACUUM (ANALYZE)` o `ANALYZE` sobre las tablas que superan el umbral en esa misma observación. |
| Restauración de prueba | `restore_test.ps1` | Semanal, domingo, después de la revisión | La última copia se restaura en `foodstore_restore_test`. Los conteos por tabla coinciden con los que se registraron antes del respaldo y los controles de productos y detalles inválidos devuelven 0. Se registran el RTO y el RPO observados. |

Programación prevista: Programador de tareas de Windows. Antes de programarse, cada script se ejecuta y se verifica a mano.

## Reglas de seguridad

1. **Sin contraseñas en el repositorio.** La autenticación sale de `%APPDATA%\postgresql\pgpass.conf`, que es personal y no se versiona. Los scripts usan `-w` (no preguntar nunca): si falta la credencial, fallan en lugar de quedar esperando. No se usa `PGPASSWORD`.
2. **`foodstore` no se borra, no se reemplaza ni se restaura.** El ensayo solo crea, borra y restaura `foodstore_restore_test`. El script se niega a continuar si el destino es otra base.
3. **Respaldo en formato custom (`-Fc`)**, que es el que puede leer `pg_restore`. Se restaura con `--no-owner --no-privileges`, porque los roles son del clúster y no viajan dentro de la copia.
4. **Fallo visible.** Si `pg_dump` falla, el script borra el archivo parcial, escribe una línea `ERROR` en el log y termina con un código distinto de 0.
5. **Mantenimiento no bloqueante.** `VACUUM FULL` está excluido del plan periódico, porque toma un bloqueo exclusivo y reescribe la tabla. Todo `VACUUM` o `ANALYZE` manual debe justificarse con la observación previa del estado de las tablas.
6. **Revisión humana.** Los scripts los genera un asistente de IA (Claude Code) a partir de esta SPEC y de `AGENTS.md`. Ningún comando suyo se ejecuta sin haberlo leído antes, y todo script se prueba (incluido su caso de error) antes de aceptarlo.

## Validación de la restauración

Los conteos de `categoria`, `cliente`, `producto`, `pedido` y `pedido_detalle` se toman inmediatamente antes de `pg_dump` y quedan junto a la copia. En el esquema la tabla de detalle se llama `pedido_detalle`, no `detalle_pedido` como en la consigna. Además se ejecutan los controles `precio < 0 OR stock < 0` sobre `producto` y `cantidad <= 0 OR precio_unitario < 0` sobre `pedido_detalle`.

## Objetivos de recuperación (laboratorio)

- **RPO previsto: 24 h.** Con un respaldo diario, se puede perder como máximo lo ocurrido desde la última copia. El valor observado es la antigüedad de la copia al comenzar el simulacro.
- **RTO previsto: 10 min.** Se mide desde inmediatamente antes de crear `foodstore_restore_test` hasta que terminan bien las validaciones.

**Fuera de alcance:** recuperación a un punto en el tiempo (archivado de WAL), copias fuera del equipo y retención automática de copias viejas.
