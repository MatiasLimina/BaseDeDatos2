# TP Unidad 6 — Mantenimiento, respaldo y recuperación de Food Store

Integrantes: Matias Limina - Nicolas Monjelardi - Lautaro Aguero

La consigna está en `TPUnidad_6_Mantenimiento_FoodStore.pdf` y el plan, en [`SPEC_U6.md`](SPEC_U6.md). El uso de IA está registrado en [`BITACORA.md`](BITACORA.md): todo el TP se hizo con Claude Code, no con OpenCode.

## Contenido

| Parte | Entregable | Archivo | Evidencia |
|---|---|---|---|
| 1 | Especificación y plan de mantenimiento | [`SPEC_U6.md`](SPEC_U6.md) | — |
| 2 | Respaldo automatizable | [`backup_foodstore.ps1`](backup_foodstore.ps1) | [`evidencias/parte2_respaldo.md`](evidencias/parte2_respaldo.md) |
| 3 | Chequeo de salud | [`health_check.sql`](health_check.sql) | [`evidencias/parte3_monitoreo_mantenimiento.md`](evidencias/parte3_monitoreo_mantenimiento.md) |
| 3 | Revisión de mantenimiento y su test | [`maintenance.sql`](maintenance.sql), [`tests/test_maintenance.sh`](tests/test_maintenance.sh) | ídem |
| 4 | Restauración de prueba y su test (opcional en la consigna) | [`restore_test.ps1`](restore_test.ps1), [`tests/test_restore.sh`](tests/test_restore.sh) | [`evidencias/parte4_simulacro.md`](evidencias/parte4_simulacro.md) |
| 5 | Informe post-incidente (una página) | [`informe_u6.pdf`](informe_u6.pdf), con su fuente en [`informe/`](informe/) | — |

Los `.dump` y los logs no se versionan (`backups/` y `logs/` están en `.gitignore`). La consigna lo permite si se entrega evidencia de su creación, su tamaño y su restauración: está en `evidencias/`.

## Resultado del simulacro

Se restauró `foodstore_20261028_181449.dump` (3,7 MB) en `foodstore_restore_test`. **RPO observado: 42 min 49 s** (previsto: 24 h). **RTO observado: 13,0 s** (previsto: 10 min). Las 7 validaciones dieron bien y `foodstore` quedó intacta.

## Orden de ejecución

Todo se ejecuta desde `TP6/`. Requiere:
- PostgreSQL 16 o superior, con `psql`, `pg_dump`, `pg_restore`, `createdb` y `dropdb` en el `PATH`;
- Windows PowerShell 5.1 para los `.ps1`;
- Git Bash para los tests y para generar el PDF;
- el `pgpass.conf` descripto abajo.

```bash
# Parte 2: respaldo (backups/foodstore_<fecha>_<hora>.dump y .counts.csv; log en logs/)
powershell -NoProfile -ExecutionPolicy Bypass -File ./backup_foodstore.ps1

# Parte 3: chequeo de salud y mantenimiento (agregar -v solo_revision=1 para ver el plan sin ejecutarlo)
psql -X -w -h localhost -U postgres -d foodstore -v ON_ERROR_STOP=1 -f health_check.sql -o logs/health_$(date +%Y%m%d).txt
psql -X -w -h localhost -U postgres -d foodstore -v ON_ERROR_STOP=1 -f maintenance.sql -o logs/maintenance_$(date +%Y%m%d).txt
bash tests/test_maintenance.sh      # -> test_maintenance: OK (usa la base descartable foodstore_maint_test)

# Parte 4: simulacro (solo sobre foodstore_restore_test)
bash tests/test_restore.sh          # -> test_restore: OK (necesita un respaldo previo)
powershell -NoProfile -ExecutionPolicy Bypass -File ./restore_test.ps1

# Parte 5: regenerar el informe y verificar que ocupe una página
bash informe/generar_pdf.sh
```

Los tests crean y borran sus propias bases descartables. Ninguno escribe en `foodstore`: `test_maintenance.sh` la usa solo como plantilla de `createdb -T`.

## Preparación del entorno (28/10/2026)

- **Servidor:** PostgreSQL 17.11, `localhost:5432`, usuario `postgres`.
- **Contraseña:** sale de `%APPDATA%\postgresql\pgpass.conf`, un archivo personal que no se versiona. Una línea `localhost:5432:*:postgres:<clave>`, guardada sin BOM.
- **Base vieja:** ya existía una `foodstore` con un esquema anterior (`pedido_producto`, una fila por tabla). No se borró: se renombró con `ALTER DATABASE foodstore RENAME TO foodstore_legacy`.
- **Base nueva:** se cargó con el esquema del proyecto integrador, en el orden del paso 1 de [`TP5/README.md`](../TP5/README.md). Lo que se cargó:

| Tabla | Filas |
|---|---|
| categoria | 3 |
| cliente | 20 003 |
| producto | 50 005 |
| pedido | 200 001 |
| pedido_detalle | 621 853 |

  La base pesa 100 MB y los controles de productos y detalles inválidos devuelven 0.
