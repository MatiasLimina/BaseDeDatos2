# TP Unidad 5 — Administración y seguridad de Food Store

Integrantes: Matias Limina - Nicolas Monjelardi - Lautaro Aguero

Roles y permisos de mínimo privilegio, auditoría, simulacro de incidente con reconstrucción por IA y anonimización con verificación de equivalencia. La consigna está en `Trabajo Practico Unidad 5.pdf`; el uso de IA, en [`BITACORA.md`](BITACORA.md).

## Contenido

| Parte | Entregable | Archivo |
|---|---|---|
| A | Especificación Kiro (requirements + design) | [`docs/kiro_roles_spec/`](docs/kiro_roles_spec/) |
| A | Tabla `usuario` y `fn_autenticar` reconstruidas (prerrequisito) | [`sql/usuario_autenticacion.sql`](sql/usuario_autenticacion.sql) |
| A | Roles y permisos | [`sql/roles.sql`](sql/roles.sql) |
| A | Pruebas de regresión del esquema de permisos | [`sql/test_roles.sql`](sql/test_roles.sql) |
| A | Verificación (`\du`, `role_table_grants`, …), salida e informe | [`sql/verificacion_roles.sql`](sql/verificacion_roles.sql), [`docs/verificacion_roles_salida.txt`](docs/verificacion_roles_salida.txt), [`docs/verificacion_permisos.md`](docs/verificacion_permisos.md) |
| B | Configuración de la auditoría del servidor | [`sql/auditoria_config.sql`](sql/auditoria_config.sql) |
| B | Secuencia de prueba, log capturado e informe | [`sql/auditoria_test.sql`](sql/auditoria_test.sql), [`docs/log_auditoria_prueba.txt`](docs/log_auditoria_prueba.txt), [`docs/informe_auditoria.md`](docs/informe_auditoria.md) |
| C | Simulacro de incidente | [`sql/simulacro_incidente.sql`](sql/simulacro_incidente.sql) |
| C | Anonimización del log (con sus pruebas) y log anonimizado | [`scripts/anonimizar_log.py`](scripts/anonimizar_log.py), [`scripts/test_anonimizar_log.py`](scripts/test_anonimizar_log.py), [`docs/log_simulacro_anonimizado.txt`](docs/log_simulacro_anonimizado.txt) |
| C | Respuesta de la IA, contraste y contención | [`docs/ia/opencode_reconstruccion_incidente.md`](docs/ia/opencode_reconstruccion_incidente.md), [`docs/informe_incidente.md`](docs/informe_incidente.md) |
| D | `usuario_anon`, su test y la verificación de equivalencia | [`sql/usuario_anon.sql`](sql/usuario_anon.sql), [`sql/test_usuario_anon.sql`](sql/test_usuario_anon.sql), [`sql/equivalencia_usuario_anon.sql`](sql/equivalencia_usuario_anon.sql), [`docs/verificacion_equivalencia.md`](docs/verificacion_equivalencia.md) |
| A–E | Bitácora de uso de IA | [`BITACORA.md`](BITACORA.md) |
| — | Evidencia literal de las sesiones de OpenCode | [`docs/ia/`](docs/ia/) |

Toda la evidencia ya está capturada en `docs/`: no hace falta ejecutar nada para corregir. Los pasos de abajo sirven para **reproducirla**.

## Antes de ejecutar

- **Solo en un entorno propio.** El simulacro de la Parte C reproduce un ataque: nunca debe correrse contra sistemas de terceros ni bases de otros equipos.
- **Un clúster dedicado.** Los roles de PostgreSQL son del clúster, no de la base: si otra base del mismo clúster ya usa `app_web`, `admin_datos`, etc., `roles.sql` no puede recrearlos (riesgo R5 de `design.md`). Lo más simple es un clúster nuevo con `initdb`.
- **PostgreSQL 16 o superior** con la extensión `pgcrypto` (viene en `contrib`), `psql` y `pg_ctl` en el `PATH`, y Python 3 para la Parte C. Los comandos son de bash (Linux, macOS o Git Bash en Windows).
- **Superusuario.** Los scripts se ejecutan como DBA. Si el DBA se autentica con contraseña, conviene un `~/.pgpass`: `auditoria_test.sql` y `simulacro_incidente.sql` se reconectan como DBA en medio del script.
- **No ejecutar** `Proyecto_Integrador/database/tp4_fnbc_control_lote.sql` en esta base: crea **otra** tabla `usuario` y borra la existente con `DROP TABLE usuario CASCADE`.

Variables que usan todos los comandos (ajustar a tu instalación):

```bash
export PGHOST=localhost PGPORT=5432 PGUSER=postgres PGDATABASE=foodstore_tp5
export PGDATA=/ruta/al/datadir       # el del clúster dedicado
```

## Pasos

Todos los comandos se ejecutan desde la raíz del repositorio. Cada test termina con una línea `...: OK`; si algo falla, `ON_ERROR_STOP` corta en el primer error.

### 1. Base de Food Store (Unidades 1 a 4)

```bash
createdb foodstore_tp5
for f in schema seed procedures views; do
  psql -X -v ON_ERROR_STOP=1 -f Proyecto_Integrador/database/$f.sql
done
# La consulta informativa del final de este archivo falla (usa "tablename" en
# pg_stat_user_indexes); los índices se crean antes. Se ejecuta sin ON_ERROR_STOP.
psql -X -f Proyecto_Integrador/database/indices_parciales_soft_delete.sql
for f in materializadas generar_registros_adaptado triggers; do
  psql -X -v ON_ERROR_STOP=1 -f Proyecto_Integrador/database/$f.sql
done
```

`views.sql` crea además el rol `rol_reportes_foodstore` (TP3) con una contraseña fija en el código: es el hallazgo R6 de la Parte A.

### 2. Configuración del servidor (Parte B.1)

Va antes que los tests de la Parte A porque `test_roles.sql` lee el log del servidor.

```bash
psql -X -v ON_ERROR_STOP=1 -f TP5/sql/auditoria_config.sql
```

En `$PGDATA/pg_hba.conf`, exigir `scram-sha-256` a todos los roles por TCP. Sin esto no puede haber un "inicio de sesión fallido". El DBA puede conservar su método, con una línea propia **antes** de la general:

```text
host    all             postgres        127.0.0.1/32            trust
host    all             all             127.0.0.1/32            scram-sha-256
host    all             postgres        ::1/128                 trust
host    all             all             ::1/128                 scram-sha-256
```

y quitar las reglas `host all all ... trust` que tuviera. Después, reiniciar (`logging_collector` lo exige):

```bash
pg_ctl -D "$PGDATA" restart
```

### 3. Roles y permisos (Parte A)

```bash
psql -X -v ON_ERROR_STOP=1 -f TP5/sql/usuario_autenticacion.sql
psql -X -v ON_ERROR_STOP=1 -f TP5/sql/roles.sql      # idempotente: puede repetirse
psql -X -v ON_ERROR_STOP=1 -f TP5/sql/test_roles.sql  # -> test_roles: OK
psql -X -v ON_ERROR_STOP=1 -f TP5/sql/verificacion_roles.sql > TP5/docs/verificacion_roles_salida.txt
```

Si se modifica `usuario_autenticacion.sql`, hay que volver a ejecutar `roles.sql`: `CREATE OR REPLACE` deja `fn_autenticar` sin `SECURITY DEFINER` hasta que `roles.sql` la endurece de nuevo. Las contraseñas de `app_web` y `admin_datos` no se versionan: para usarlas fuera de los scripts, asignarlas con `\password`.

### 4. Prueba de auditoría (Parte B.2)

```bash
psql -X -f TP5/sql/auditoria_test.sql    # imprime: auditoria_test: secuencia ejecutada, corrida <ID>
```

El fragmento de log de esa corrida va entre los marcadores `TP5-B inicio <ID>` y `TP5-B fin <ID>`:

```bash
ID=<ID impreso por el script>
awk -v r="$ID" '$0 ~ "TP5-B inicio " r {on=1} on {print} on && $0 ~ "STATEMENT:.*TP5-B fin" {exit}' \
    "$PGDATA"/log/postgresql-$(date +%F).log > TP5/docs/log_auditoria_prueba.txt
```

### 5. Simulacro de incidente (Parte C)

```bash
psql -X -f TP5/sql/simulacro_incidente.sql    # -> simulacro_incidente: escalamiento rechazado; corrida <ID>
```

Si el escalamiento **no** falla, el script termina con `ERROR: HALLAZGO: ...`: es un defecto de `roles.sql` que hay que corregir antes de seguir.

Extraer el fragmento y anonimizarlo. Los mails pasan a `usuario<id>@ejemplo.test` (criterio de `usuario_anon`), las rutas del servidor a `<PGDATA>` y se quitan las sesiones del DBA. Antes conviene correr las pruebas del anonimizador:

```bash
python -I TP5/scripts/test_anonimizar_log.py   # -> OK
ID=<ID impreso por el script>
awk -v r="$ID" '$0 ~ "TP5-C inicio " r {on=1} on {print} on && $0 ~ "TP5-C fin " r {f=1} f && $0 ~ "STATEMENT:" {exit}' \
    "$PGDATA"/log/postgresql-$(date +%F).log > simulacro_crudo.txt
psql -X -At -F, -c "SELECT mail, 'usuario' || id || '@ejemplo.test' FROM usuario" > mapa_mails.csv
python -I TP5/scripts/anonimizar_log.py simulacro_crudo.txt mapa_mails.csv > TP5/docs/log_simulacro_anonimizado.txt
rm simulacro_crudo.txt mapa_mails.csv     # contienen datos reales: no versionarlos
```

El log anonimizado se le entregó a OpenCode desde una carpeta aislada, sin acceso al repositorio ni a la memoria del proyecto (ver `docs/ia/opencode_reconstruccion_incidente.md`).

### 6. Anonimización y equivalencia (Parte D)

```bash
psql -X -v ON_ERROR_STOP=1 -f TP5/sql/usuario_anon.sql
psql -X -v ON_ERROR_STOP=1 -f TP5/sql/test_usuario_anon.sql          # -> test_usuario_anon: OK
psql -X -v ON_ERROR_STOP=1 -f TP5/sql/equivalencia_usuario_anon.sql  # -> equivalencia_usuario_anon: OK
```

## Datos de prueba

`usuario_autenticacion.sql` carga 30 cuentas sintéticas (`cuenta1@foodstore.test` … `cuenta30@foodstore.test`, clave de prueba `FoodStore#<id>`): la 1 es `ADMIN`, cada quinta está dada de baja y las altas son semanales desde el 5 de enero de 2026. Son credenciales de desarrollo, no de personas reales.
