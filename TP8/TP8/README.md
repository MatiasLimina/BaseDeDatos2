# TP8 — Food Store en la feria: la base de la tablet y el cierre de la capa de datos

**Integrantes:** Matias Limina, Nicolas Monjelardi y Lautaro Aguero.

TP Unidad 8 de Bases de Datos II. El food truck vende en una feria sin señal. La tablet tiene una base SQLite donde solo consulta el catálogo y arma borradores; la sincronización con PostgreSQL se **simula** con un semáforo. **El móvil propone, el servidor dispone**: precio, stock y ventas los decide PostgreSQL, y `SIMULADO_APROBADO` no es una venta.

El TP vive en la carpeta `TP8/` del repositorio del TP7, rama `tp8`, etiqueta `tp8`.

## Contenido

| Consigna | Qué | Archivos |
|---|---|---|
| 1.a | Qué datos viajan a la tablet | [`docs/informe.pdf`](docs/informe.pdf) (sección 1.a) |
| 1.b | Esquema SQLite: 4 tablas `STRICT` + `snapshot_servidor` | [`movil/schema_sqlite.sql`](movil/schema_sqlite.sql) |
| 1.c | Borrador con `COMMIT`, `ROLLBACK`, casos C1 y C7 | [`movil/pruebas_sqlite.sql`](movil/pruebas_sqlite.sql) |
| 2.a | Vista `v_snapshot_movil`, CSV e importación | [`sql/01_v_snapshot_movil.sql`](sql/01_v_snapshot_movil.sql), [`sql/02_exportar_snapshot.sql`](sql/02_exportar_snapshot.sql), [`movil/servidor_snapshot.csv`](movil/servidor_snapshot.csv), [`movil/importar_snapshot.sql`](movil/importar_snapshot.sql) |
| 2.b | Semáforo | [`movil/semaforo.sql`](movil/semaforo.sql) |
| 2.c | Casos C2 a C6 y verificación en PostgreSQL | [`scripts/correr_casos.sh`](scripts/correr_casos.sh), [`movil/casos/`](movil/casos/), [`sql/casos/`](sql/casos/), [`sql/linea_base.sql`](sql/linea_base.sql), [`sql/verificacion_final.sql`](sql/verificacion_final.sql) |
| 3.a, 3.b | Mapa de los tres motores y plan de mantenimiento | [`docs/informe.pdf`](docs/informe.pdf), [`docs/plan_mantenimiento_tp8.md`](docs/plan_mantenimiento_tp8.md) |
| 3.c | Code review con IA | [`docs/code_review_ia.md`](docs/code_review_ia.md) |
| 4.a | Spec (EARS), diseño y tareas | [`docs/kiro/`](docs/kiro/) (derivados de [`openspec/changes/tp8-tablet-sqlite-sync/`](openspec/changes/tp8-tablet-sqlite-sync/)) |
| 4.b | Bitácora de IA y DUIA | [`docs/bitacora_ia.md`](docs/bitacora_ia.md), [`docs/DUIA.md`](docs/DUIA.md) |

La base de la tablet ya armada es [`movil/foodstore_movil.db`](movil/foodstore_movil.db). Las salidas de cada paso están en [`evidencias/`](evidencias/).

Al terminar `scripts/correr_casos.sh`, los dos archivos de `movil/` quedan en momentos distintos, a propósito:

- `servidor_snapshot.csv` es S0 exportada de nuevo con el servidor ya restaurado: coincide con `food_store_copia`.
- `foodstore_movil.db` es la tablet después del último caso: `cola_sync` tiene los resultados de C2 a C6, y `snapshot_servidor` y `producto_cache` son los de C4 (producto 1 a 299000 y producto 3 como lápida, `eliminado = 1`). No se reimporta S0 para no borrar esa lápida.

**Desvío de herramientas.** La consigna pide Kiro y OpenCode. Se usaron Claude Code y OpenSpec: la spec se escribió y commiteó antes que el código, y `docs/kiro/` se derivó de ella. Ver [`docs/DUIA.md`](docs/DUIA.md).

## Requisitos

- PostgreSQL 16 o superior, con la base de pruebas **`food_store_copia`** (una copia de `foodstore`, con datos inventados). Nunca se usa la base real.
- `pgpass.conf` con una línea para esa base (`localhost:5432:food_store_copia:postgres:<clave>`): los scripts usan `psql -w` y no piden contraseña.
- `sqlite3` 3.37 o superior (para `STRICT`).
- Git Bash.
- Para el PDF: Google Chrome o Microsoft Edge, y Python con `pypdf`.

## Orden para crear todo desde cero

Todo se ejecuta **desde `TP8/`**:

```bash
export PATH="$PATH:/d/DevTools/PosgresSQL/bin:/d/DevTools/miniconda3/Library/bin"   # ajustar a tu instalación
export PGCLIENTENCODING=UTF8
P="psql -X -w -h localhost -U postgres -d food_store_copia -v ON_ERROR_STOP=1"
```

**1. Línea base del servidor (solo lectura).** Se toma una vez, **antes** de tocar nada: es la referencia contra la que se comprueba al final que PostgreSQL no cambió.

```bash
$P -At -f sql/linea_base.sql > evidencias/linea_base.txt
```

**2. Tests que no necesitan el servidor** (usan CSV de prueba en `tests/fixtures/`):

```bash
bash tests/test_esquema_sqlite.sh     # -> test_esquema_sqlite: OK
bash tests/test_importacion.sh        # -> test_importacion: OK
bash tests/test_carga_cache.sh        # -> test_carga_cache: OK
bash tests/test_pruebas_sqlite.sh     # -> test_pruebas_sqlite: OK
bash tests/test_semaforo.sh           # -> test_semaforo: OK
```

**3. Vista e instantánea en PostgreSQL** (consigna 2.a). La vista es lo único que se crea en el servidor:

```bash
$P -f sql/01_v_snapshot_movil.sql
$P -f sql/02_exportar_snapshot.sql    # -> COPY 50005, en movil/servidor_snapshot.csv
bash tests/test_vista_snapshot.sh     # -> test_vista_snapshot: OK
```

**4. Base de la tablet** (consignas 1.b, 1.c y 2.a):

```bash
rm -f movil/foodstore_movil.db
sqlite3 movil/foodstore_movil.db < movil/schema_sqlite.sql
sqlite3 movil/foodstore_movil.db < movil/importar_snapshot.sql
sqlite3 movil/foodstore_movil.db < movil/pruebas_sqlite.sql   # C1 y C7 muestran errores a propósito
```

**5. Casos C1 a C7** (consigna 2.c). El script rehace los pasos 3 y 4 y corre C5, C6, C2, C3 y C4. Para C2 y C4 cambia la copia del servidor (sube un precio, da de baja un producto) y la **restaura** al final, también si falla o se corta con Ctrl+C. Termina comparando contra la línea base y falla si PostgreSQL quedó distinto:

```bash
bash scripts/correr_casos.sh   # -> verificacion_final: PostgreSQL igual a la linea base
bash tests/test_casos.sh       # -> test_casos: OK
```

**6. Informe:**

```bash
bash informe/generar_pdf.sh    # -> docs/informe.pdf, falla si supera 6 páginas
bash tests/test_docs.sh        # -> test_docs: OK
```

Para generar un UUID en SQLite (por ejemplo, para una solicitud nueva): `SELECT lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)));`
