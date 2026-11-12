# Code Review con IA de los scripts de la cursada

> **Nota metodológica y de integridad:**
> La revisión exhaustiva de código fue realizada por un agente de solo lectura de Claude (`research`), sin acceso de escritura ni conexión a las bases de datos activas. Los scripts analizados pertenecen a la totalidad de la cursada de Bases de Datos II (TP1 a TP6 y Proyecto Integrador, TP7 y TP8, todos en este repositorio (TP7 y TP8 fueron importados desde el repositorio original del TP7)). Ningún dato personal real figura en este documento.

---

## 1. Inventario completo de scripts

Total de scripts analizados: **107 scripts** distribuidos en 9 componentes.

### TP1 (1 script)
- `../../TP1/schema.sql`

### TP2 (2 scripts)
- `../../TP2/restricciones_tp2.sql`
- `../../TP2/seed.sql`

### TP3 (5 scripts)
- `../../TP3/gen_pdf.py`
- `../../TP3/indices.sql`
- `../../TP3/materializadas.sql`
- `../../TP3/queries.sql`
- `../../TP3/views.sql`

### TP4 (17 scripts)
- `../../TP4/gen_pdf.py`
- `../../TP4/tests/test_auditoria.sql`
- `../../TP4/tests/test_baja_logica.sql`
- `../../TP4/tests/test_concurrencia.sql`
- `../../TP4/tests/test_datos_prueba.sql`
- `../../TP4/tests/test_dia_negocio.sql`
- `../../TP4/tests/test_fnbc_descomposicion.sql`
- `../../TP4/tests/test_fnbc_esquema_original.sql`
- `../../TP4/tests/test_fnbc_restricciones_indices.sql`
- `../../TP4/tests/test_fnbc_vista_migracion.sql`
- `../../TP4/tests/test_reporte_top5.sql`
- `../../TP4/tests/test_reversibilidad.sql`
- `../../TP4/tests/test_trigger_detalle.sql`
- `../../TP4/tests/test_trigger_pedido_producto.sql`
- `../../TP4/tests/test_ventas_diarias_estructura.sql`
- `../../TP4/tp_desnormalizacion_top_categorias.sql`
- `../../TP4/tp_fnbc_control_lote.sql`

### TP5 (12 scripts)
- `../../TP5/scripts/anonimizar_log.py`
- `../../TP5/scripts/test_anonimizar_log.py`
- `../../TP5/sql/auditoria_config.sql`
- `../../TP5/sql/auditoria_test.sql`
- `../../TP5/sql/equivalencia_usuario_anon.sql`
- `../../TP5/sql/roles.sql`
- `../../TP5/sql/simulacro_incidente.sql`
- `../../TP5/sql/test_roles.sql`
- `../../TP5/sql/test_usuario_anon.sql`
- `../../TP5/sql/usuario_anon.sql`
- `../../TP5/sql/usuario_autenticacion.sql`
- `../../TP5/sql/verificacion_roles.sql`

### TP6 (7 scripts)
- `../../TP6/backup_foodstore.ps1`
- `../../TP6/health_check.sql`
- `../../TP6/informe/generar_pdf.sh`
- `../../TP6/maintenance.sql`
- `../../TP6/restore_test.ps1`
- `../../TP6/tests/test_maintenance.sh`
- `../../TP6/tests/test_restore.sh`

### Proyecto Integrador (27 scripts)
- `../../Proyecto_Integrador/database/consultas_avanzadas.sql`
- `../../Proyecto_Integrador/database/generar_registros_adaptado.sql`
- `../../Proyecto_Integrador/database/indices_parciales_soft_delete.sql`
- `../../Proyecto_Integrador/database/materializadas.sql`
- `../../Proyecto_Integrador/database/procedures.sql`
- `../../Proyecto_Integrador/database/schema.sql`
- `../../Proyecto_Integrador/database/seed.sql`
- `../../Proyecto_Integrador/database/test_procedures.sql`
- `../../Proyecto_Integrador/database/tests_tp4/test_auditoria.sql`
- `../../Proyecto_Integrador/database/tests_tp4/test_baja_logica.sql`
- `../../Proyecto_Integrador/database/tests_tp4/test_concurrencia.sql`
- `../../Proyecto_Integrador/database/tests_tp4/test_datos_prueba.sql`
- `../../Proyecto_Integrador/database/tests_tp4/test_dia_negocio.sql`
- `../../Proyecto_Integrador/database/tests_tp4/test_fnbc_descomposicion.sql`
- `../../Proyecto_Integrador/database/tests_tp4/test_fnbc_esquema_original.sql`
- `../../Proyecto_Integrador/database/tests_tp4/test_fnbc_restricciones_indices.sql`
- `../../Proyecto_Integrador/database/tests_tp4/test_fnbc_vista_migracion.sql`
- `../../Proyecto_Integrador/database/tests_tp4/test_reporte_top5.sql`
- `../../Proyecto_Integrador/database/tests_tp4/test_reversibilidad.sql`
- `../../Proyecto_Integrador/database/tests_tp4/test_trigger_detalle.sql`
- `../../Proyecto_Integrador/database/tests_tp4/test_trigger_pedido_producto.sql`
- `../../Proyecto_Integrador/database/tests_tp4/test_ventas_diarias_estructura.sql`
- `../../Proyecto_Integrador/database/tp4_datos_prueba_top_categorias.sql`
- `../../Proyecto_Integrador/database/tp4_desnormalizacion_top_categorias.sql`
- `../../Proyecto_Integrador/database/tp4_fnbc_control_lote.sql`
- `../../Proyecto_Integrador/database/triggers.sql`
- `../../Proyecto_Integrador/database/views.sql`

### TP7 (11 scripts)
- `../consultas_mongodb.js`
- `../consultas_postgresql.sql`
- `../informe/generar_pdf.sh`
- `../migracion/generar_insert_pedidos.sql`
- `../mongodb/01_crear_coleccion.js`
- `../mongodb/02_insert_pedidos.js`
- `../sql/00_estado_pedido.sql`
- `../sql/01_seleccion_pedidos.sql`
- `../sql/test_estado_pedido.sql`
- `../tests/test_consultas.sh`
- `../tests/test_migracion.sh`

### TP8 (25 scripts)
- `movil/casos/c2_aceptar.sql`
- `movil/casos/c2_borrador.sql`
- `movil/casos/c3_borrador.sql`
- `movil/casos/c4_borrador.sql`
- `movil/casos/c5_c6.sql`
- `movil/importar_snapshot.sql`
- `movil/pruebas_sqlite.sql`
- `movil/schema_sqlite.sql`
- `movil/semaforo.sql`
- `scripts/correr_casos.sh`
- `sql/01_v_snapshot_movil.sql`
- `sql/02_exportar_snapshot.sql`
- `sql/casos/preparar_c2.sql`
- `sql/casos/preparar_c4.sql`
- `sql/casos/productos_casos.sql`
- `sql/casos/restaurar_casos.sql`
- `sql/linea_base.sql`
- `sql/verificacion_final.sql`
- `tests/test_carga_cache.sh`
- `tests/test_casos.sh`
- `tests/test_esquema_sqlite.sh`
- `tests/test_importacion.sh`
- `tests/test_pruebas_sqlite.sh`
- `tests/test_semaforo.sh`
- `tests/test_vista_snapshot.sh`

---

## 2. Prompt enviado al agente revisor de IA

```text
Sos un agente de code review de solo lectura. Se te solicita realizar una revision tecnica de los scripts de la cursada de Bases de Datos II, especialmente de TP7 y TP8 (en este repo) y de TP1 a TP6 / Proyecto Integrador (en este mismo repo, en las carpetas `TP1/` a `TP6/` y `Proyecto_Integrador/`).

Criterios de analisis:
1. Correctitud: consultas, tipos, comparaciones.
2. Integridad: claves foraneas, restricciones de dominio, checks, unicidad.
3. Seguridad: escape de cadenas, inyecciones de codigo, sanitizacion de identificadores.
4. Idempotencia y transacciones: re-ejecucion segura, rollback ante fallos, atomicidad.

Examina en detalle:
- TP7: ../migracion/generar_insert_pedidos.sql, ../sql/00_estado_pedido.sql, ../mongodb/01_crear_coleccion.js, ../consultas_postgresql.sql
- TP8: movil/schema_sqlite.sql, movil/importar_snapshot.sql, movil/semaforo.sql, sql/01_v_snapshot_movil.sql, scripts/correr_casos.sh
- Muestra representativa de TP1 a TP6 y Proyecto Integrador.

Genera una lista estructurada de hallazgos indicando para cada uno:
- ID de hallazgo
- Unidad y archivo
- Categoria (Correctitud, Integridad, Seguridad, Idempotencia)
- Descripcion del problema o posible vulnerabilidad
- Evaluacion de impacto y recomendacion de solucion.

No incluyas datos personales reales. Devuelve un informe estructurado y exhaustivo.
```

---

## 3. Respuesta cruda del agente revisor

El subagente de Claude de solo lectura emitió el siguiente dictamen técnico:

- **[SEC-01] Interpolación directa de cadenas en generador JS sin `to_json()`** (TP7 — `migracion/generar_insert_pedidos.sql`): `format()` inyecta `p.estado` y `p.forma_pago` directamente con `%s` sin `to_json()`.
- **[SEC-02] Concatenación no parametrizada en script de prueba** (TP7 — `tests/test_migracion.sh`): Interpola `$ids_csv` directamente en la consulta SQL `WHERE p.id IN ($ids_csv)`.
- **[CORR-01] Aprobación fantasma de stock por evaluación desacoplada** (TP8 — `movil/semaforo.sql`): El semáforo evalúa cada solicitud de forma aislada contra `s.stock`; si existen dos solicitudes pendientes para un mismo producto que superan el stock sumado, ambas simulan aprobado.
- **[CORR-02] Agrupación exhaustiva sobre la tabla completa en vista comparativa** (TP7 — `consultas_postgresql.sql`): La vista temporal `pedido_total` agrupa las 621.853 filas de `pedido_detalle` antes de filtrar por los 9 pedidos migrados.
- **[CORR-03] Ruta de binarios tipográficamente errónea en orquestador bash** (TP8 — `scripts/correr_casos.sh`): Declara `PosgresSQL` (falta la letra `t`).
- **[INTEG-01] Volatilidad de claves foráneas por sesión en SQLite** (TP8 — `movil/schema_sqlite.sql`): `PRAGMA foreign_keys = ON;` debe ejecutarse en cada conexión, no persiste en el archivo `.db`.
- **[INTEG-02] Redundancia no controlada de subtotal en modelo relacional** (TP1-TP6 / Proyecto Integrador — `pedido_detalle`): `subtotal` sin `CHECK (subtotal = round(cantidad * precio_unitario, 2))`.
- **[INTEG-03] Generador sintético con sesgo severo de distribución** (TP3-TP4 / Proyecto Integrador — `generar_registros_adaptado.sql`): 200.000 pedidos asignados al cliente 4812 y 4 productos en el 78% de pedidos.
- **[INTEG-04] Validación estricta y canónica de UUIDs en SQLite (Fortaleza técnica)** (TP8 — `movil/schema_sqlite.sql`): Check exhaustivo con GLOB y longitud que garantiza formato canónico.
- **[IDEM-01] DDL destructivo incondicional en script de inicialización NoSQL** (TP7 — `mongodb/01_crear_coleccion.js`): `db.pedidos.drop()` incondicional.
- **[IDEM-02] Bloqueo masivo y generación de tuplas muertas en migración DDL** (TP7 — `sql/00_estado_pedido.sql`): `UPDATE` masivo genera 200.001 tuplas muertas; `ANALYZE` no recupera espacio.
- **[IDEM-03] Mecanismo transaccional con control de integridad de snapshot (Fortaleza técnica)** (TP8 — `movil/importar_snapshot.sql`): Guarda con tabla temporal `ok = 1` y upsert con lápidas.

---

## 4. Tabla completa de decisiones y motivos

| ID | Unidad y archivo | Categoría | Decisión | Motivo de la decisión |
|---|---|---|---|---|
| **SEC-01** | TP7: `migracion/generar_insert_pedidos.sql` | Seguridad | **Descartado (como riesgo) / Aceptado (como higiene)** | `p.estado` y `p.forma_pago` provienen de tipos `ENUM` de PostgreSQL estrictamente alfanuméricos en mayúsculas (`PENDIENTE`, `EFECTIVO`, etc.), siendo imposible inyectar código. |
| **SEC-02** | TP7: `tests/test_migracion.sh` | Seguridad | **Aceptado** | Restringido al script de test local; se recomienda validar que `$ids_csv` contenga solo dígitos y comas. |
| **CORR-01** | TP8: `movil/semaforo.sql` | Correctitud | **Descartado con fundamento** | En la tablet offline la evaluación es una **simulación local**, no una venta confirmada ni reserva de stock. Controlar el stock entre varias ventas le corresponde al servidor al confirmar la venta, fuera del TP8. Ver sección 5. |
| **CORR-02** | TP7: `consultas_postgresql.sql` | Rendimiento | **Aceptado** | Medido con `EXPLAIN ANALYZE`: el filtro temprano baja de 621.201 filas y 2.621 buffers a 12 filas y 64 buffers, con el mismo resultado. Ver sección 5. |
| **CORR-03** | TP8: `scripts/correr_casos.sh` | Correctitud | **Descartado con refutación** | La carpeta en el disco del host está instalada literalmente como `D:\DevTools\PosgresSQL`. Modificarla hubiera roto la ejecución en este entorno. Se agregaron ambas rutas para portabilidad (`evidencias/code_review_3.txt`). |
| **INTEG-01** | TP8: `movil/schema_sqlite.sql` | Integridad | **Aceptado** | Comprobado en la base: sin el PRAGMA se acepta un ítem de un producto inexistente; con él, falla. Todos los scripts de `movil/` ya lo activan. Ver sección 5. |
| **INTEG-02** | TP1–TP6: `pedido_detalle` | Integridad | **Aceptado (histórico)** | Falta de restricción `CHECK` o columna generada en el esquema original. No se modifica el repo `BaseDeDatos2` por ser externo y cerrado. |
| **INTEG-03** | TP3–TP4: `generar_registros_adaptado.sql` | Integridad / Calidad | **Aceptado (histórico)** | Sesgo sintético severo hacia el cliente 4812. Se documenta como lección aprendida para pruebas de carga. No se modifica el repo externo. |
| **INTEG-04** | TP8: `movil/schema_sqlite.sql` | Integridad | **Aceptado (fortaleza)** | Excelente práctica de validación canónica de UUIDs en modo STRICT. |
| **IDEM-01** | TP7: `mongodb/01_crear_coleccion.js` | Idempotencia | **Aceptado** | Comportamiento aceptado para scripts de inicialización de laboratorio; en producción requeriría flag de confirmación. |
| **IDEM-02** | TP7: `sql/00_estado_pedido.sql` | Idempotencia / Bloat | **Aceptado** | Para producción se recomienda `VACUUM ANALYZE` para limpiar las tuplas muertas generadas por el `UPDATE` masivo. |
| **IDEM-03** | TP8: `movil/importar_snapshot.sql` | Idempotencia | **Aceptado (fortaleza)** | Patrón transaccional robusto con guarda de integridad y preservación de lápidas. |

---

## 5. Hallazgos desarrollados y comprobaciones empíricas

### Hallazgo 1 (TP8): [CORR-01] Supuesta "Aprobación fantasma de stock" en el semáforo
* **Descripción de la IA:** El semáforo clasifica solicitudes de forma individual contra `s.stock`. Dos solicitudes concurrentes de 2 unidades frente a un stock de 3 resultarían ambas en `SIMULADO_APROBADO`.
* **Decisión:** **DESCARTADO con fundamento comprobable**.
* **Comprobación y refutación empírica:** Registrada en [`evidencias/code_review_1.txt`](../evidencias/code_review_1.txt). Se comprobó en SQLite que ambas solicitudes simulan aprobado, y es lo esperado, porque la evaluación es una simulación:
  1. Cada tablet opera desconectada y monousuario en la feria; el semáforo es solo una **propuesta de simulación**, nunca una venta ni reserva de inventario.
  2. Si la tablet descontara stock localmente sin comunicación bidireccional, múltiples tablets generarían inventarios locales divergentes y falsas sensaciones de stock.
  3. Controlar el stock entre varias ventas le corresponde al servidor cuando la venta se confirme. Eso queda fuera del TP8: la tablet nunca escribe en PostgreSQL.

### Hallazgo 2 (TP7): [CORR-02] Agrupación de toda la tabla en la vista comparativa
* **Descripción de la IA:** En `consultas_postgresql.sql`, `CREATE TEMP VIEW pedido_total` agrupa todo `pedido_detalle` antes de emparejar con los 9 pedidos de la muestra de MongoDB.
* **Decisión:** **ACEPTADO** (como recomendación; `consultas_postgresql.sql` es del TP7 y no se modificó).
* **Comprobación en la base:** `EXPLAIN (ANALYZE, BUFFERS)` de la consulta d) en `food_store_copia`, con `scripts/medir_corr02.sql`. Salida completa en [`evidencias/code_review_2_explain.txt`](../evidencias/code_review_2_explain.txt) y resumen en [`evidencias/code_review_2.txt`](../evidencias/code_review_2.txt). Se usó la copia porque, por regla del change (`openspec/changes/archive/2026-11-01-tp8-tablet-sqlite-sync/tasks.md`), el TP8 solo usa esa base para no tocar la original, y la `foodstore` del TP7 no existe en esta máquina; la consulta se midió sin `pedido.estado`, que la copia no tiene y la vista no usa.

  | | Vista original | Con filtro temprano |
  |---|---|---|
  | Filas de `pedido_detalle` | 621.201 | 12 |
  | Buffers | 2.621 | 64 |
  | Tiempo de ejecución | 206,6 ms | 0,088 ms |

  Las dos versiones devuelven el mismo pedido (10167). En el TP7 la consulta d) devuelve 1, 20 y 26 (`../evidencias/parte2_salida_postgresql.txt`): la copia tiene otros datos de detalle para los mismos 9 pedidos, así que la medición muestra el efecto del filtro, no la salida del TP7.
* **Lo que no coincidía:** la IA había dado ~24.000 → 18 buffers, ~85 → < 0,2 ms y un Index Scan sobre `pk_pedido_detalle`, sin ningún `EXPLAIN` que lo respalde; el plan real usa `idx_detalle_subtotal`. Sus 621.853 filas y 31 filas sí corresponden a la `foodstore` del TP7 (`../docs/modelo_documental.md` y `../evidencias/parte1_coleccion.txt`); en la copia son 621.201 y 12. El diagnóstico (PostgreSQL no lleva la condición del JOIN a través del `GROUP BY`) sí era correcto.

### Hallazgo 3 (TP8): [INTEG-01] Claves foráneas que SQLite no hace cumplir por defecto
* **Descripción de la IA:** `PRAGMA foreign_keys = ON;` debe ejecutarse en cada conexión; no queda guardado en el archivo `.db`.
* **Decisión:** **ACEPTADO** (ya mitigado).
* **Comprobación en la base:** Registrada en [`evidencias/code_review_integ01.txt`](../evidencias/code_review_integ01.txt), generada por `scripts/demo_pragma_fk.sh` sobre una base temporal creada con `movil/schema_sqlite.sql`:
  1. Conexión sin el PRAGMA (`foreign_keys = 0`): insertar en `item_borrador` un `producto_id = 999999`, que no existe en `producto_cache`, funciona (`changes() = 1`). Solo `PRAGMA foreign_key_check` detecta el huérfano después.
  2. Conexión con el PRAGMA (`foreign_keys = 1`): la misma inserción falla con `FOREIGN KEY constraint failed` y no queda ninguna fila.
  3. Mitigación: la misma evidencia lista la primera sentencia SQL de cada script de `movil/`, y en todos es `PRAGMA foreign_keys = ON;`. Cualquier cliente nuevo que abra la base tiene que hacer lo mismo.

CORR-03 sigue en la tabla como descartado: la carpeta del host se llama literalmente `PosgresSQL` (`evidencias/code_review_3.txt`). No se desarrolla aquí porque se comprobó en el disco y no en la base.

