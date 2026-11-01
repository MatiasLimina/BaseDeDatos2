# Design: TP8 – La base de la tablet (SQLite) y el cierre de la capa de datos

## Context

Motivación y alcance: ver `proposal.md`. Requisitos: `specs/movil-base-tablet/spec.md`, `specs/movil-instantanea-servidor/spec.md`, `specs/movil-semaforo-sincronizacion/spec.md` y `specs/gobierno-capa-datos/spec.md`. Consigna: `TP_U8` (PDF de 6 páginas, "Food Store en la feria").

Estado verificado (consulta de solo lectura vía MCP `postgres`, 2026-11-01):

- Base de pruebas: **`food_store_copia`** (copia; nunca se toca `foodstore` —usada en el TP7— ni `food_store`). `producto(id bigint, nombre varchar (máx. 22 caracteres), precio numeric (máx. 4 999,99), stock int, activo bool, categoria_id bigint, created_at timestamptz)`. **No existen** columnas `disponible` ni `eliminado`.
- `pedido(id, fecha, forma_pago, cliente_id, created_at)` con enum `forma_pago` = `EFECTIVO, TARJETA, TRANSFERENCIA, OTRO`; `pedido_detalle(pedido_id, producto_id, cantidad, precio_unitario, subtotal)`. Vistas existentes: `vw_productos_vigentes`, `vw_pedidos_cliente`, `vw_detalle_pedido`.
- Línea base: **50 005 productos (2 inactivos, 112 con stock 0), 200 002 pedidos, `sum(stock) = 5 012 740`**.
- Herramientas: `psql` en `D:/DevTools/PosgresSQL/bin/psql` (convención del TP7: `psql -X -w -h localhost -U postgres`, autenticación por `pgpass.conf`, sin `PGPASSWORD`); `sqlite3` 3.51.0 (≥ 3.37 para `STRICT`, ≥ 3.33 para `UPDATE ... FROM`); Git Bash para los tests; Chrome sin interfaz para el PDF.
- **Restricción de entorno observada:** desde la sesión del agente `psql -w` falla con `fe_sendauth: no password supplied` (el `pgpass.conf` existe pero no se aplica a esta sesión), y el MCP `postgres` es de solo lectura sobre `food_store_copia`. Las escrituras en PostgreSQL (crear la vista, preparar y restaurar C2/C4) las ejecuta el humano o una sesión con `pgpass` funcionando; el agente puede verificar por MCP.
- Repositorio: `TP8/` vive dentro del repo del TP7 (`nicolasmonjelardi/BaseDeDatos2-TP7-NoSQL`); los archivos del TP7 están en la raíz (`../` desde `TP8/`). TP1–TP6 y `Proyecto_Integrador/` están en otro repo de la materia (`../../BaseDeDatos2/`), que este change **solo lee** para el code review 3.c (Decisión 11) y nunca edita.
- MongoDB del TP7 (colección `foodstore.pedidos`): 9 pedidos / 31 líneas migrados desde la base `foodstore` de PostgreSQL (que tiene `pedido.estado`, agregado en el TP7). Las líneas van embebidas con su `precio_unitario` histórico; los datos esenciales de cliente y producto van copiados y embebidos con su id; el resto (teléfono, activo, precio actual, stock) no se embebe y lo administra PostgreSQL. La colección se borra y se recrea: la fuente de verdad es PostgreSQL. `food_store_copia` (la base del TP8) es anterior al TP7 y su `pedido` **no tiene** `estado`.
- Convenciones a reutilizar, tomadas del TP7 (`../`): tests en Bash como `../tests/*.sh`, que imprimen `test_x: OK` o `test_x: FALLA - motivo` y salen ≠ 0; evidencias en `evidencias/*.txt`; informe HTML → PDF con Chrome sin interfaz y control de páginas con `pypdf`, con `../informe/generar_pdf.sh` como modelo.
- Formatos de documentación (definidos acá, sin depender de archivos de otros TP):
  - **Bitácora de IA**: tabla con columnas pedido / respuesta relevante / qué se aceptó / qué se descartó y por qué / verificación (comando o prueba que lo confirmó).
  - **DUIA**: herramientas y modelo usados; para qué se usaron; qué hizo el humano; datos compartidos (ninguno personal real); desvío Kiro/OpenCode → Claude Code + OpenSpec.
  - **`docs/kiro/requirements.md`**: un requisito por bloque `REQ-xx` en notación EARS (`WHEN ... THE SYSTEM SHALL ...`), con la línea "Se prueba con: Cx" y la ruta de su evidencia en `evidencias/`.

## Goals / Non-Goals

**Goals:**
- Que la base de la tablet se reconstruya desde cero con scripts (sin pasos manuales en DB Browser) y que cada caso C1–C7 deje evidencia reproducible en `TP8/evidencias/`.
- Que el semáforo sea correcto por construcción ante los tipos de SQLite (nada de comparar enteros con texto) e idempotente.
- Que PostgreSQL termine exactamente igual a la línea base (conteo de pedidos, suma de stock y huella del catálogo).
- Test primero: cada script tiene su test escrito y fallando antes de existir.

**Non-Goals:**
- App de celular, interfaz o simulador en Python (la consigna lo permite opcional; se hace todo en SQL).
- Sincronización real (subir borradores a PostgreSQL, crear pedidos, descontar stock). `SIMULADO_APROBADO` nunca es una venta.
- Alterar tablas o columnas del servidor, ni tocar `foodstore` / `food_store`.
- Corregir hallazgos del code review de TP1–TP6: están en otro repo (`../../BaseDeDatos2/`), que se lee pero no se edita; se registran solo con su decisión y motivo.
- Usar Kiro u OpenCode (ver Decisión 12).

## Decisions

### 1. Árbol de entregables bajo `TP8/` (decisión del usuario)
Se replica el árbol del PDF (`food-store/`) dentro de `TP8/` y se agregan carpetas de soporte con las convenciones del TP7:

```
TP8/
├── README.md                      orden para crear todo desde cero (4.c)
├── movil/
│   ├── schema_sqlite.sql          1.b
│   ├── pruebas_sqlite.sql         1.c (transacciones, C1, C7)
│   ├── importar_snapshot.sql      2.a (.import + recarga de producto_cache)
│   ├── semaforo.sql               2.b
│   ├── casos/                     2.c: c2_*.sql … c6_*.sql (lado SQLite)
│   ├── servidor_snapshot.csv      2.a (última instantánea exportada)
│   └── foodstore_movil.db         estado final tras los casos
├── sql/                           lado PostgreSQL (solo food_store_copia)
│   ├── 01_v_snapshot_movil.sql    vista
│   ├── 02_exportar_snapshot.sql   \copy a movil/servidor_snapshot.csv
│   ├── linea_base.sql             conteos + huella (antes y después)
│   ├── casos/                     preparar_c2.sql, preparar_c4.sql, restaurar_casos.sql
│   └── verificacion_final.sql     pedidos y stock sin cambios
├── scripts/correr_casos.sh        orquesta C2–C6 y guarda evidencias
├── tests/                         test_*.sh (test primero)
├── evidencias/                    salidas de cada paso y caso
├── informe/                       informe.html + generar_pdf.sh
└── docs/
    ├── informe.pdf                1.a, 2.c, 3.a, 3.b, 3.c (≤ 6 páginas)
    ├── kiro/{requirements,design,tasks}.md
    ├── code_review_ia.md          3.c: tabla completa + prompt y respuesta cruda
    ├── plan_mantenimiento_tp8.md  3.b: agregado al plan de la Unidad 6
    ├── bitacora_ia.md
    └── DUIA.md
```
Etiqueta final `tp8` en el repo del TP7 (`nicolasmonjelardi/BaseDeDatos2-TP7-NoSQL`), donde vive `TP8/`: la crea el orquestador con confirmación del usuario, y subirla (`push`) requiere permiso de escritura en ese repo. `servidor_snapshot.csv` (~3 MB) y `foodstore_movil.db` se versionan porque son entregables. Todos los comandos se ejecutan desde `TP8/`.

### 2. Base de pruebas y protección del servidor
Todo lo de PostgreSQL corre sobre `food_store_copia`. Cada script que escribe empieza con una guarda que aborta si `current_database() <> 'food_store_copia'` (así un script lanzado por error contra `foodstore` o `food_store` no cambia nada) y corre con `-v ON_ERROR_STOP=1`. La tablet y el semáforo **no tienen conexión** a PostgreSQL: el único canal es el CSV. Así la regla "la tablet nunca cambia el servidor" se cumple por arquitectura, no por disciplina.

### 3. Vista `v_snapshot_movil`: derivar, no alterar (decisión del usuario)
```sql
CREATE OR REPLACE VIEW v_snapshot_movil AS
SELECT p.id,
       p.nombre,
       round(p.precio * 100)::bigint                      AS precio_centavos,
       p.stock,
       (p.activo AND p.stock > 0)::int                    AS disponible,
       (NOT p.activo)::int                                AS eliminado,
       to_char(now() AT TIME ZONE 'UTC',
               'YYYY-MM-DD"T"HH24:MI:SS"Z"')              AS copiado_en,
       count(*) OVER ()                                   AS filas_copia
FROM producto p;
```
- `disponible`/`eliminado` se derivan (`eliminado = NOT activo`, `disponible = activo AND stock > 0`): no se agrega ninguna columna al servidor. Salen como **enteros 1/0** y el precio ya en **centavos**: la pista del PDF advierte que en el CSV de psql los booleanos vienen como `t`/`f`, y una tabla STRICT entera los rechazaría.
- `round(...)` antes del cast evita depender del redondeo implícito; con `NUMERIC(10,2)` es exacto.
- `copiado_en` sale de `now()`, que es constante dentro de la transacción del `\copy`: una única fecha de copia por instantánea, en ISO-8601 UTC (ordenable como texto en SQLite). Es "la fecha de la copia" que pide 2.a.
- `filas_copia` (`count(*) OVER ()`) hace que el CSV lleve su propio total esperado: la importación verifica que no se perdió ninguna fila (Decisión 5).
- Se incluyen **todos** los productos (50 005), también los inactivos: son las lápidas que le avisan a la tablet de una baja (C4). Alternativas descartadas: filtrar `activo` (la tablet nunca se enteraría de las bajas; C4 no podría mostrar la lápida) o limitar a una categoría "de feria" (un borrador podría referir a un producto fuera de la instantánea y caer en rojo por "inexistente" sin serlo). 50 005 filas ≈ 3 MB es manejable en SQLite y en git.
- Sin columnas de cliente ni `created_at`/`categoria_id`: lo que no se usa en la tablet no viaja (1.a).
- Exportación (`sql/02_exportar_snapshot.sql`, desde `TP8/`, con `PGCLIENTENCODING=UTF8`): `\copy (SELECT * FROM v_snapshot_movil ORDER BY id) TO 'movil/servidor_snapshot.csv' CSV HEADER`.

### 4. Esquema SQLite (`movil/schema_sqlite.sql`)
- Primera línea `PRAGMA foreign_keys = ON;`; después `DROP TABLE IF EXISTS` en orden inverso de dependencias y `CREATE TABLE ... STRICT` (re-ejecutable).
- `producto_cache(id INTEGER PRIMARY KEY` (= id del servidor, sin `AUTOINCREMENT`), `nombre TEXT NOT NULL`, `precio_centavos INTEGER NOT NULL CHECK (>= 0)`, `stock_visto INTEGER NOT NULL CHECK (>= 0)`, `disponible`/`eliminado INTEGER NOT NULL CHECK (IN (0,1))`, `copiado_en TEXT NOT NULL)`.
- `pedido_borrador(id_local TEXT PRIMARY KEY` con `CHECK` de UUID canónico (largo 36, guiones en 9/14/19/24, resto hexadecimal en minúsculas), `usuario TEXT NOT NULL` (alias inventado, p. ej. `vendedor_feria_1`), `forma_pago TEXT NOT NULL CHECK (IN ('EFECTIVO','TARJETA','TRANSFERENCIA'))`, `fecha TEXT NOT NULL DEFAULT` ISO-8601 UTC`)`. `OTRO` del enum del servidor queda fuera a propósito: la consigna limita la tablet a tres formas.
- `item_borrador(id_local → pedido_borrador, producto_id → producto_cache, cantidad INTEGER CHECK (> 0), precio_centavos_visto INTEGER CHECK (>= 0), PRIMARY KEY (id_local, producto_id))`. La PK compuesta replica `pk_pedido_detalle` del servidor y garantiza que el semáforo vea un ítem por producto.
- `cola_sync(solicitud_uuid TEXT PRIMARY KEY` (mismo `CHECK` de UUID), `id_local → pedido_borrador`, `estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (IN (4 estados))`, `motivo TEXT`, `creada_en TEXT NOT NULL DEFAULT`, `evaluada_en TEXT`, `snapshot_copiado_en TEXT)`. Las dos últimas registran cuándo y contra qué instantánea se evaluó (trazabilidad para la revisión de 3.b).
- `snapshot_servidor`: ver Decisión 5.
- Claves foráneas sin `ON DELETE CASCADE` (comportamiento por defecto, que impide borrar): en la tablet nada se borra físicamente; los borradores y solicitudes son historia.
- Fechas como `TEXT` ISO-8601 (`strftime('%Y-%m-%dT%H:%M:%SZ','now')`): SQLite no tiene tipo fecha y STRICT solo admite `INTEGER/REAL/TEXT/BLOB/ANY`.
- **`PRAGMA foreign_keys` vale por conexión**: cada script que escribe (`pruebas_sqlite.sql`, `importar_snapshot.sql`, `semaforo.sql`, `casos/*.sql`) lo repite en su primera línea, y los tests verifican que devuelva 1. Sin eso, C7 "producto inexistente" pasaría en silencio.
- UUIDs: los casos usan **UUIDs v4 literales fijos** (evidencia reproducible y comparable entre corridas). En el README se documenta la expresión con `randomblob(16)` para generarlos en uso real. Alternativa descartada: depender de una función `uuid()` de una extensión que no todas las instalaciones de sqlite3 traen.

### 5. `snapshot_servidor` se crea antes del `.import`, tipada y STRICT
Se crea en `schema_sqlite.sql` con las mismas columnas y el mismo orden que la vista (`id, nombre, precio_centavos, stock, disponible, eliminado, copiado_en, filas_copia`), STRICT, con los `CHECK` de dominio y sin claves foráneas (es una tabla de aterrizaje).

Por qué no dejar que `.import` la cree: sin tabla previa, sqlite3 crea **todas las columnas como TEXT**. En SQLite cualquier INTEGER es menor que cualquier TEXT, así que `i.cantidad > s.stock` sería siempre falso (nunca habría rojo por stock) y `i.precio_centavos_visto <> s.precio_centavos` siempre verdadero (todo sería amarillo): un semáforo que aprueba lo que no debe sin dar ningún error. Con la tabla STRICT previa, `.import` convierte `'123'` en `123` y **rechaza** `t`/`f` o `12.50` en columnas enteras.

`movil/importar_snapshot.sql` (en una transacción): `PRAGMA foreign_keys = ON`, `.bail on`, `DELETE FROM snapshot_servidor`, `.import --csv --skip 1 movil/servidor_snapshot.csv snapshot_servidor`, y una **guarda**: como `.import` informa las filas fallidas pero sigue, se inserta `count(*) = max(filas_copia)` (y que no haya `copiado_en` con `char(13)`) en una tabla temporal con `CHECK (ok = 1)`; si no coincide, el `CHECK` falla, `.bail` corta y la transacción abierta se deshace al salir, así que el caché no se recarga con una instantánea incompleta. Alternativa descartada: verificar solo desde el test (la protección tiene que estar en el script que se ejecuta en la feria).

### 6. Recarga de `producto_cache`: upsert, nunca borrar
En el mismo script, después de la guarda:
```sql
INSERT INTO producto_cache (id, nombre, precio_centavos, stock_visto, disponible, eliminado, copiado_en)
SELECT id, nombre, precio_centavos, stock, disponible, eliminado, copiado_en
FROM snapshot_servidor WHERE true          -- "WHERE true" evita la ambigüedad de parseo de SELECT + ON CONFLICT
ON CONFLICT (id) DO UPDATE SET nombre = excluded.nombre, precio_centavos = excluded.precio_centavos,
  stock_visto = excluded.stock, disponible = excluded.disponible,
  eliminado = excluded.eliminado, copiado_en = excluded.copiado_en;
UPDATE producto_cache SET eliminado = 1, disponible = 0
WHERE id NOT IN (SELECT id FROM snapshot_servidor);
```
No se borra porque (a) `item_borrador` referencia el producto y la FK lo impediría, y (b) C4 pide que "la fila quede". El catálogo disponible (C1) es `WHERE disponible = 1 AND eliminado = 0`. Alternativa descartada: `DELETE` + `INSERT` (rompe borradores y pierde la lápida).

### 7. Semáforo (`movil/semaforo.sql`)
Un único `UPDATE cola_sync ... FROM (evaluación) ...` dentro de `BEGIN ... COMMIT`, que toca solo `estado = 'PENDIENTE'` y solo si `EXISTS (SELECT 1 FROM snapshot_servidor)`:

- Evaluación: `cola_sync c` (PENDIENTE) `LEFT JOIN item_borrador i USING (id_local)` `LEFT JOIN snapshot_servidor s ON s.id = i.producto_id`, `GROUP BY c.solicitud_uuid`, con contadores: `n_items = count(i.producto_id)`, `n_rojo = sum(` producto inexistente `OR eliminado = 1 OR disponible = 0 OR cantidad > stock)` (solo sobre ítems existentes) y `n_amarillo = sum(i.precio_centavos_visto <> s.precio_centavos)`; `motivo = group_concat(...)` por ítem con prioridad inexistente > baja > no disponible > stock > precio (ej. `producto 123: pide 5, stock 2`; `producto 77: precio visto 150000, actual 165000`).
- Prioridades: borrador sin ítems → RECHAZADO ("borrador vacío", decisión propia: sin esto quedaría PENDIENTE para siempre); rojo antes que amarillo; si no, verde.
- Se setean `evaluada_en` y `snapshot_copiado_en` (= `max(copiado_en)` de la instantánea).
- Idempotencia: como solo mira PENDIENTE, una segunda corrida modifica 0 filas; el script imprime `SELECT changes()` para dejarlo en la evidencia (C6).
- **Modo aprendizaje (decisión del usuario):** la expresión `CASE` que decide rojo/amarillo/verde (consigna 2.b) la escribe **el humano**. El agente deja el andamiaje completo (transacción, subconsulta con los contadores, motivo, guarda de instantánea vacía, `changes()`) con un bloque marcado `-- TODO(humano): CASE del semáforo` y escribe antes el test que la valida.
- Alternativa descartada: simulador en Python (agrega dependencia y esconde la lógica que se defiende en vivo).

### 8. Secuencia de casos y aislamiento de las corridas
Cada corrida del semáforo evalúa todas las PENDIENTE; para que la evidencia de cada caso sea limpia, `scripts/correr_casos.sh` deja pendiente solo la solicitud del caso en curso:

1. `sql/linea_base.sql` → `evidencias/linea_base.txt` (pedidos, `sum(stock)`, huella `md5(string_agg(id‖nombre‖precio‖stock‖activo‖categoria_id ORDER BY id))`).
2. Instantánea S0: exportar, importar, cargar caché.
3. `pruebas_sqlite.sql`: el borrador confirmado con `BEGIN ... COMMIT` **es el borrador de C5** (documentado en el script), la operación con `ROLLBACK`, C1 y C7.
4. **C5**: semáforo → SIMULADO_APROBADO. **C6**: reinsertar el mismo `solicitud_uuid` → error de PK; semáforo de nuevo → `changes() = 0`.
5. **C2**: borrador del producto A + solicitud; `preparar_c2.sql` sube su precio; exportar/importar/cargar; semáforo → CONFLICTO. Aceptación: en una transacción, `UPDATE item_borrador SET precio_centavos_visto = <precio de la instantánea>` + solicitud nueva; semáforo → SIMULADO_APROBADO (la anterior sigue CONFLICTO).
6. **C3**: borrador del producto B por `stock_visto + 1`; exportar/importar/cargar (sin cambios en el servidor: la consigna pide preparar "más unidades de las que quedan", y el stock del servidor **no se toca**); semáforo → RECHAZADO.
7. **C4**: borrador del producto C; `preparar_c4.sql` → `activo = false`; exportar/importar/cargar; semáforo → RECHAZADO; el catálogo ya no lo muestra y la fila sigue en `producto_cache` con `eliminado = 1`.
8. `restaurar_casos.sql` (precio original de A y `activo = true` de C, con valores originales literales y aserción de que existían) y `verificacion_final.sql` → `evidencias/verificacion_final.txt`; el test compara con la línea base.

Los productos A (C2), B (C3), C (C4) y D (borrador de C5) se eligen en el apply con una consulta de solo lectura (activos, con stock chico para B, ids distintos) y quedan fijos como variables de psql y literales en los scripts de casos; los scripts de preparación verifican el valor original antes de cambiarlo (`UPDATE ... WHERE id = :a AND precio = <original>` + aserción de 1 fila). `restaurar_casos.sql` es idempotente y el orquestador lo ejecuta también desde un `trap` si la corrida se corta. La protección real de C6 en un sistema de verdad (parada 8): clave única de idempotencia sobre `solicitud_uuid` **en el servidor** (tabla de solicitudes recibidas con `UNIQUE` e `INSERT ... ON CONFLICT DO NOTHING` en la misma transacción que crea el pedido), no solo en la tablet.

El `foodstore_movil.db` entregado queda en el estado final de los casos (con la lápida de C4, aunque el servidor ya se haya restaurado: el caché está desactualizado hasta la próxima sincronización, y así se explica).

### 9. Test primero para SQL (Strict TDD)
Cada entregable tiene un `TP8/tests/test_*.sh` escrito **antes** del script y ejecutado en RED (falla por archivo/objeto inexistente o aserción falsa). Los tests de SQLite trabajan sobre una copia temporal (`mktemp -d`) para no ensuciar `foodstore_movil.db`; los de PostgreSQL son de solo lectura salvo el de casos, que valida la evidencia y la línea base. Tests previstos: `test_esquema_sqlite.sh`, `test_pruebas_sqlite.sh` (transacción, C1, C7), `test_vista_snapshot.sh`, `test_importacion.sh` (incluye un CSV de fixture con `t`/`f` que debe fallar y uno con `\r\n`), `test_carga_cache.sh`, `test_semaforo.sh` (fixtures sintéticos: cada rama, prioridad rojo > amarillo, precio que baja, borrador vacío, instantánea vacía, idempotencia, estado final estable), `test_casos.sh` (estados esperados C2–C6 y línea base igual) y `test_docs.sh` (≥ 4 EARS con "Se prueba con: C", bitácora ≥ 3 entradas con un descarte, PDF ≤ 6 páginas). Formato de salida: `test_x: OK` / `test_x: FALLA - motivo`, salida ≠ 0 en falla.

### 10. Mapa de los tres motores y plan de mantenimiento
**Mapa (3.a)**: tabla con **una fila por dato y una columna por motor**; cada celda dice "manda", "copia (solo lectura)" o "no está". Leída por columna responde "qué guarda cada uno"; leída por fila, "quién manda". Cada fila tiene exactamente un "manda".

| Dato | PostgreSQL | MongoDB U7 | SQLite tablet |
|------|------------|------------|---------------|
| Catálogo y precio actual | manda | no está ¹ | copia (solo lectura) en `producto_cache` |
| Stock | manda | no está | copia (solo lectura) (`stock_visto`) |
| Pedidos confirmados (ventas) | manda | copia (solo lectura): copia documental `foodstore.pedidos`, se regenera desde `foodstore` | no está |
| Estado del pedido | manda (`pedido.estado` en `foodstore`) | copia (solo lectura) | no está |
| Clientes y datos personales | manda | copia (solo lectura) del subconjunto esencial, dentro de cada pedido ² | no está (nunca viajan) |
| `snapshot_servidor` (instantánea CSV) | manda (`v_snapshot_movil`) | no está | copia (solo lectura) |
| Borradores (`pedido_borrador`, `item_borrador`) | no está | no está | manda |
| Solicitudes (`cola_sync`) | no está | no está | manda (la sincronización solo se simula) |
| Resultado del semáforo | no está | no está | manda, pero es solo una simulación: `SIMULADO_APROBADO` nunca es una venta |

¹ Cada línea de MongoDB guarda el `precio_unitario` histórico de la venta (parte del pedido), no el precio actual del catálogo. ² Se copian embebidos con su id los datos esenciales de cliente y producto; teléfono, activo, precio actual y stock no se embeben.

Nota de origen, que va junto al mapa: "MongoDB: 9 pedidos / 31 líneas migrados desde `foodstore` (TP7, con `estado`); la tablet trabaja sobre `food_store_copia`, copia de pruebas sin `estado`." Para describir la colección con precisión se leen `../README.md` y `../docs/modelo_documental.md` (TP7, en este mismo repo).

Dibujo chico del flujo (complementa la tabla en el informe):
```
PostgreSQL food_store_copia ─ v_snapshot_movil ─ \copy ─► servidor_snapshot.csv ─ .import ─► SQLite (tablet)
PostgreSQL foodstore ─ migración TP7 (insertMany) ─► MongoDB foodstore.pedidos
SQLite (tablet) ─ ✗ ─► no vuelve nada al servidor (cola_sync solo se simula)
```

**Plan (3.b)**: **no se edita el TP6** (ya entregado). El agregado vive en el informe y en `TP8/docs/plan_mantenimiento_tp8.md`, y parte del plan de mantenimiento de la Unidad 6 tal como está —respaldo diario de PostgreSQL y prueba de restauración semanal, sin cambios— para extenderlo a los tres motores: MongoDB no se respalda aparte (se regenera desde PostgreSQL con la migración del TP7); SQLite: al cierre de cada jornada se respaldan los borradores y la cola con `VACUUM INTO` y se prueba abriendo la copia y comparando conteos. Si se restaura un respaldo viejo de PostgreSQL, las tablets no confían en su caché ni en sus resultados simulados: recargan una instantánea nueva (la `copiado_en` posterior a la restauración) y recién entonces se evalúa lo pendiente. CONFLICTO y RECHAZADO los revisa el encargado del food truck al cierre de cada jornada de feria (y antes de la siguiente sincronización).

### 11. Code review con IA (3.c)
Inventario (rutas relativas a `TP8/`): todos los `.sql`, `.ps1`, `.sh`, `.py` y `.js` de la cursada, en dos repos:
- `../../BaseDeDatos2/` (otro repo de la materia): `TP1/` … `TP6/` y `Proyecto_Integrador/database/`, como entrada **de solo lectura** (la consigna pide "todos los scripts de la cursada").
- Este repo: TP7 en la raíz (`../`, sin `../TP8/`) y TP8 (`./`).

El inventario lista cada archivo con su ruta relativa y un conteo por unidad. La revisión la hace **un agente de Claude de solo lectura** (herramientas de lectura y búsqueda sobre los dos repos; sin escritura ni acceso a la base). El prompt y la respuesta cruda se guardan en `docs/code_review_ia.md`; el humano decide cada hallazgo (aceptado / corregido / descartado) con su motivo. Los hallazgos de TP1–TP6 solo se registran con su decisión: no se corrigen desde este repo. Los ≥ 3 hallazgos desarrollados salen del TP7 y del TP8 (dos unidades distintas, lo que cumple "al menos dos unidades") y se comprueban en la base con una consulta o prueba cuya salida va a `evidencias/code_review_*.txt`. Al menos uno se descarta con fundamento comprobado.

### 12. Desvío conocido de la consigna: Claude Code + OpenSpec en lugar de Kiro + OpenCode (decisión del usuario)
La consigna pide escribir la spec en Kiro antes de generar código y generar esquema y simulación con OpenCode desde esas tareas; 3.c pide el agente Plan de OpenCode. El equipo usa **Claude Code + OpenSpec (OPSX)**: este change (proposal, specs, design, tasks) cumple el rol de la spec de Kiro y se escribe **antes** del apply (el historial de git lo muestra si este change se commitea antes del primer script). Para respetar el árbol de entrega, una tarea genera `TP8/docs/kiro/{requirements,design,tasks}.md` derivados de estos artefactos: `requirements.md` en formato EARS (`WHEN ... THE SYSTEM SHALL ...`, ≥ 4 requisitos, cada uno con "Se prueba con: Cx" y la ruta de su evidencia), con el formato definido en Context. La revisión 3.c se hace con un agente de Claude de solo lectura en lugar de OpenCode Plan. El desvío se declara en el README, el informe, la bitácora y la DUIA, sin presentar nada como hecho con Kiro u OpenCode.

Requisitos EARS previstos (se exportan a `docs/kiro/requirements.md`):
- REQ-01 WHEN el precio actual de algún ítem es distinto del precio visto y no hay causa de rechazo THE SYSTEM SHALL marcar la solicitud como CONFLICTO. Se prueba con: C2
- REQ-02 WHEN algún ítem pide más unidades que el stock de la instantánea THE SYSTEM SHALL marcar la solicitud como RECHAZADO. Se prueba con: C3
- REQ-03 WHEN un producto del borrador fue dado de baja en el servidor THE SYSTEM SHALL marcar la solicitud como RECHAZADO y conservar la fila del producto fuera del catálogo disponible. Se prueba con: C4
- REQ-04 WHEN todos los ítems coinciden con la instantánea THE SYSTEM SHALL marcar la solicitud como SIMULADO_APROBADO sin crear pedidos ni cambiar stock en el servidor. Se prueba con: C5
- REQ-05 WHEN se reenvía una solicitud con un UUID ya registrado THE SYSTEM SHALL rechazarla por clave primaria y no reevaluar la existente. Se prueba con: C6
- REQ-06 WHEN no hay conexión con el servidor THE SYSTEM SHALL listar el catálogo disponible desde la base local. Se prueba con: C1
- REQ-07 WHEN un ítem tiene cantidad 0 o un producto inexistente THE SYSTEM SHALL rechazarlo sin dejar filas nuevas. Se prueba con: C7

### 13. Bitácora, DUIA, README e informe
- `docs/bitacora_ia.md`: con el formato de bitácora definido en Context (pedido / respuesta relevante / qué se aceptó / qué se descartó y por qué / verificación), ≥ 3 entradas, al menos una con algo descartado (candidatas reales: crear `snapshot_servidor` con `.import` sin tabla previa; usar `DELETE` para recargar el caché; un hallazgo del code review descartado).
- `docs/DUIA.md`: con el formato de DUIA definido en Context, declarando Claude Code (modelo) + OpenSpec, el agente revisor de solo lectura, el modo aprendizaje (el `CASE` del semáforo lo escribió el humano) y que no se compartieron datos personales reales.
- `README.md`: requisitos, orden completo desde cero (vista → exportar → esquema → importar → pruebas → casos → restaurar → verificar → tests → PDF), salida esperada de cada test, desvío Kiro/OpenCode, fecha de la copia usada.
- Informe: `informe/informe.html` → `docs/informe.pdf` con `informe/generar_pdf.sh`, hecho sobre el modelo de `../informe/generar_pdf.sh` del TP7 (Chrome sin interfaz + `pypdf`, falla si supera 6 páginas). Cubre 1.a, 2.c (comando, resultado y explicación por caso + verificación final + oración de C6 sobre la protección real), 3.a, 3.b y 3.c.

## Risks / Trade-offs

- [El agente no puede escribir en PostgreSQL (`psql -w` sin credencial en su sesión; MCP de solo lectura)] → Las tareas que crean la vista, preparan/restauran casos y exportan quedan marcadas para ejecutar con `pgpass` funcionando (humano o sesión configurada con `PGPASSFILE`); el agente verifica por MCP. Nunca se lee ni se versiona `pgpass.conf`.
- [Una corrida cortada deja C2/C4 aplicados en `food_store_copia`] → `restaurar_casos.sql` idempotente, invocado desde `trap` en `correr_casos.sh`; la verificación final con la huella lo detecta.
- [`.import` sigue ante filas con error y la instantánea queda incompleta] → guarda `count(*) = filas_copia` con `CHECK` + `.bail on` (Decisión 5) y test con fixture inválido.
- [CSV con `\r\n` o en otra codificación desde Windows] → `PGCLIENTENCODING=UTF8`; la guarda y el test verifican que `copiado_en` no contenga `char(13)`.
- [Comparaciones INTEGER vs TEXT en SQLite que aprueban en silencio] → tablas STRICT tipadas antes del `.import`; test de semáforo con stock insuficiente que debe dar rojo.
- [`PRAGMA foreign_keys` olvidado en una sesión] → primera línea de cada script que escribe + aserción en los tests.
- [El semáforo depende de una parte escrita por el humano] → el test de semáforo se entrega antes y define el contrato; el agente revisa el `CASE` contra el test y la spec, sin reescribirlo salvo pedido.
- [CSV de ~3 MB y `.db` binario en git] → aceptado (son entregables); el `.db` es regenerable desde el README.
- [El informe supera 6 páginas] → `generar_pdf.sh` falla si pasa el límite; las tablas largas (code review completo) van en `docs/code_review_ia.md` y el informe muestra los desarrollados.
- [Mezclar evidencia de casos porque el semáforo evalúa todas las PENDIENTE] → secuencia de la Decisión 8, una solicitud pendiente por corrida.

## Migration Plan

1. Commitear este change de OpenSpec antes del primer script (evidencia de "spec antes de código").
2. Crear la vista en `food_store_copia` (solo agrega un objeto). Rollback: `DROP VIEW IF EXISTS v_snapshot_movil;`.
3. Los cambios de datos de C2/C4 se revierten con `restaurar_casos.sql`; la verificación final prueba que la copia volvió a la línea base.
4. La base SQLite se regenera desde cero en cualquier momento (`rm movil/foodstore_movil.db` + README).

## Open Questions

- Ids concretos de los productos A, B y C de los casos y sus valores originales: se fijan en el apply con una consulta de solo lectura (no cambian el diseño).
- Rol exacto del responsable de revisar CONFLICTO/RECHAZADO (encargado del food truck por defecto): el equipo puede ajustarlo en la redacción de 3.b.
