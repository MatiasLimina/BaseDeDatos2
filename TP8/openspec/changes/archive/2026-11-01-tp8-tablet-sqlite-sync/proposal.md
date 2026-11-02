# Proposal: TP8 – Food Store en la feria: la base de la tablet (SQLite) y el cierre de la capa de datos

## Why

La consigna del TP Unidad 8 ("Food Store en la feria", último TP antes del segundo parcial) pide que el food truck pueda vender en una feria sin señal: una tablet con SQLite que **consulta el catálogo y arma borradores sin conexión**, y una **sincronización simulada** con PostgreSQL mediante el semáforo (RECHAZADO / CONFLICTO / SIMULADO_APROBADO). La regla de oro es *"el móvil propone, el servidor dispone"*: la tablet nunca cambia el precio ni el stock del servidor ni confirma ventas. Además cierra la capa de datos del proyecto: mapa de los tres motores (PostgreSQL, MongoDB de la Unidad 7 y SQLite), agregado al plan de mantenimiento de la Unidad 6, code review con IA de todos los scripts de la cursada, requisitos EARS ligados a casos, bitácora de IA, DUIA y README que reconstruye todo desde cero. Ninguna afirmación se acepta sin el script y la salida que la demuestran.

## What Changes

**Consigna 1 – La base de la tablet (`TP8/movil/`)**
- `schema_sqlite.sql`: empieza con `PRAGMA foreign_keys = ON;` y crea desde cero, en modo `STRICT`, `producto_cache`, `pedido_borrador`, `item_borrador` y `cola_sync` con sus `CHECK` (centavos enteros no negativos, banderas 0/1, forma de pago EFECTIVO/TARJETA/TRANSFERENCIA, cantidad > 0, estados válidos) y claves foráneas; también la tabla de aterrizaje `snapshot_servidor`, tipada y `STRICT`.
- Tabla "qué datos viajan / cuáles no" y quién es la fuente de verdad (1.a).
- `pruebas_sqlite.sql`: borrador completo con `BEGIN ... COMMIT`, otra operación deshecha con `ROLLBACK`, caso **C1** (catálogo disponible sin servidor) y caso **C7** (cantidad 0 y producto inexistente fallan sin dejar filas).

**Consigna 2 – Sincronizar y resolver**
- En la copia de pruebas de PostgreSQL (`food_store_copia`): vista `v_snapshot_movil` que **deriva** `disponible = activo AND stock > 0` y `eliminado = NOT activo` (sin alterar tablas del servidor), con el precio ya en centavos y banderas 1/0, incluyendo los productos dados de baja (lápidas) y la fecha de la copia. Exportación con `\copy` a `TP8/movil/servidor_snapshot.csv`.
- Importación con `.import --csv --skip 1` a `snapshot_servidor` y carga de `producto_cache` por *upsert* (nunca borra: las bajas quedan como lápidas).
- `semaforo.sql`: evalúa **solo** las solicitudes `PENDIENTE` contra `snapshot_servidor` y guarda estado y motivo en `cola_sync`. La expresión `CASE` del semáforo la escribe el humano (modo aprendizaje); el resto del script queda como andamiaje.
- Casos **C2** (precio sube → CONFLICTO; aceptación → SIMULADO_APROBADO), **C3** (más unidades que el stock → RECHAZADO), **C4** (baja lógica → RECHAZADO; desaparece del catálogo pero la fila queda), **C5** (sin cambios → SIMULADO_APROBADO) y **C6** (mismo UUID → error de PK; repetir la simulación no reevalúa). Cada caso con comando, resultado y explicación.
- Scripts de preparación y **restauración** de los cambios en la copia (`TP8/sql/`) y consulta final que demuestra que la cantidad de pedidos, el stock (y la huella del catálogo) de PostgreSQL no cambiaron.

**Consigna 3 – Integrar y revisar**
- Mapa de los tres motores: tabla con una fila por dato y una columna por motor (PostgreSQL / MongoDB U7 / SQLite tablet), cada celda "manda", "copia (solo lectura)" o "no está", más un dibujo chico del flujo (PostgreSQL → CSV → SQLite; PostgreSQL `foodstore` → MongoDB; de la tablet no vuelve nada). Aclara de qué copia sale cada dato: MongoDB tiene 9 pedidos / 31 líneas migrados desde `foodstore` (TP7, con `estado`); la tablet trabaja sobre `food_store_copia`, copia de pruebas sin `estado`.
- Agregado al plan de mantenimiento de la Unidad 6 (respaldo diario de PostgreSQL y prueba de restauración semanal), en `TP8/docs/plan_mantenimiento_tp8.md` y en el informe, sin editar el TP6: qué se respalda y cómo se prueba la restauración, qué hacen las tablets si se restaura un respaldo viejo de PostgreSQL, y cada cuánto y quién revisa CONFLICTO/RECHAZADO.
- Code review con IA de todos los scripts de la cursada: TP1–TP6 y `Proyecto_Integrador/database/` del otro repo (`../../BaseDeDatos2`, solo lectura), TP7 (`../`) y TP8. Tabla de hallazgos con decisión y motivo; los de TP1–TP6 solo se registran con su decisión (no se corrigen desde este repo). Al menos tres desarrollados, comprobados en la base, salen del TP7 y del TP8 (dos unidades), y al menos uno se descarta con fundamento.

**Consigna 4 – Spec, bitácora y README** (el ensayo de defensa oral queda fuera de alcance: la cátedra no lo va a requerir en principio)
- Requisitos en notación EARS (≥ 4, cada uno con "Se prueba con: Cx"), diseño y tareas, exportados a `TP8/docs/kiro/{requirements,design,tasks}.md` a partir de estos artefactos de OpenSpec.
- `TP8/docs/bitacora_ia.md` (≥ 3 entradas, con algo descartado), `TP8/docs/DUIA.md`, `TP8/README.md` con el orden para crear todo desde cero, `TP8/docs/informe.pdf` (≤ 6 páginas: 1.a, 2.c, 3.a, 3.b y 3.c) y etiqueta `tp8` en el repositorio.

**Desvío conocido de la consigna**: no se usan Kiro ni OpenCode. El ciclo completo se hace con Claude Code + OpenSpec (OPSX); la revisión de código 3.c la hace un agente de Claude de solo lectura en lugar del agente Plan de OpenCode. Se declara explícitamente en el diseño, la bitácora y la DUIA.

No hay cambios **BREAKING**: en PostgreSQL solo se agrega una vista en la copia de pruebas; los cambios de datos de los casos se revierten al final.

## Capabilities

### New Capabilities
- `movil-base-tablet`: base SQLite de la tablet: esquema STRICT con sus reglas, borradores transaccionales (todo o nada), catálogo disponible consultable sin servidor y rechazo de datos inválidos.
- `movil-instantanea-servidor`: instantánea del catálogo del servidor (vista derivada en PostgreSQL, exportación CSV, importación tipada en SQLite) y recarga de `producto_cache` conservando lápidas.
- `movil-semaforo-sincronizacion`: simulación de la sincronización: clasificación de solicitudes pendientes en RECHAZADO / CONFLICTO / SIMULADO_APROBADO, idempotencia por UUID, aceptación de un conflicto y garantía de que PostgreSQL no cambia.
- `gobierno-capa-datos`: cierre de la capa de datos: mapa de los tres motores y quién manda, agregado al plan de mantenimiento para las tablets, code review con IA con decisiones, requisitos EARS trazados a casos, bitácora, DUIA y README reproducible.

### Modified Capabilities
<!-- Ninguna: las specs existentes (control-lote-almacen, ventas-diarias-categoria) no cambian. -->

## Impact

- **PostgreSQL (solo la copia `food_store_copia`)**: nueva vista `v_snapshot_movil`. Cambios temporales de datos para C2 (precio de un producto) y C4 (`activo = false` de otro), revertidos por script. Nunca se toca `foodstore` ni `food_store`. Línea base: 50.005 productos (2 inactivos), 200.002 pedidos, `sum(stock) = 5.012.740`; debe quedar idéntica.
- **SQLite (nuevo)**: `TP8/movil/foodstore_movil.db` regenerable desde los scripts; sin datos personales reales (el `usuario` del borrador es un alias inventado).
- **Archivos nuevos**: todo bajo `TP8/` (`movil/`, `sql/`, `tests/`, `evidencias/`, `docs/`, `informe/`, `README.md`).
- **Herramientas**: PostgreSQL 16+ (`psql -X -w` con `pgpass.conf`), sqlite3 3.37+ (laboratorio: 3.51.0), Git Bash para los tests, Chrome sin interfaz para el PDF (como en el TP7).
- **Repositorio**: etiqueta `tp8` al cierre en el repo del TP7 (`nicolasmonjelardi/BaseDeDatos2-TP7-NoSQL`), donde vive `TP8/`; la crea el orquestador tras la confirmación del usuario, y el `push` requiere permiso de escritura en ese repo.
