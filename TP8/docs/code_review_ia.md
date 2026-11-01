# Code Review con IA de los scripts de la cursada

> **Nota metodológica y de integridad:**
> La revisión exhaustiva de código fue realizada por un agente de solo lectura de Claude (`research`), sin acceso de escritura ni conexión a las bases de datos activas. Los scripts analizados pertenecen a la totalidad de la cursada de Bases de Datos II (TP1 a TP6 y Proyecto Integrador en el repositorio `BaseDeDatos2`, y TP7 y TP8 en el repositorio `BasesNoRelacionales`). Ningún dato personal real figura en este documento.

---

## 1. Inventario completo de scripts

Total de scripts analizados: **107 scripts** distribuidos en 9 componentes.

### TP1 (1 script)
- `../../BaseDeDatos2/TP1/schema.sql`

### TP2 (2 scripts)
- `../../BaseDeDatos2/TP2/restricciones_tp2.sql`
- `../../BaseDeDatos2/TP2/seed.sql`

### TP3 (5 scripts)
- `../../BaseDeDatos2/TP3/gen_pdf.py`
- `../../BaseDeDatos2/TP3/indices.sql`
- `../../BaseDeDatos2/TP3/materializadas.sql`
- `../../BaseDeDatos2/TP3/queries.sql`
- `../../BaseDeDatos2/TP3/views.sql`

### TP4 (17 scripts)
- `../../BaseDeDatos2/TP4/gen_pdf.py`
- `../../BaseDeDatos2/TP4/tests/test_auditoria.sql`
- `../../BaseDeDatos2/TP4/tests/test_baja_logica.sql`
- `../../BaseDeDatos2/TP4/tests/test_concurrencia.sql`
- `../../BaseDeDatos2/TP4/tests/test_datos_prueba.sql`
- `../../BaseDeDatos2/TP4/tests/test_dia_negocio.sql`
- `../../BaseDeDatos2/TP4/tests/test_fnbc_descomposicion.sql`
- `../../BaseDeDatos2/TP4/tests/test_fnbc_esquema_original.sql`
- `../../BaseDeDatos2/TP4/tests/test_fnbc_restricciones_indices.sql`
- `../../BaseDeDatos2/TP4/tests/test_fnbc_vista_migracion.sql`
- `../../BaseDeDatos2/TP4/tests/test_reporte_top5.sql`
- `../../BaseDeDatos2/TP4/tests/test_reversibilidad.sql`
- `../../BaseDeDatos2/TP4/tests/test_trigger_detalle.sql`
- `../../BaseDeDatos2/TP4/tests/test_trigger_pedido_producto.sql`
- `../../BaseDeDatos2/TP4/tests/test_ventas_diarias_estructura.sql`
- `../../BaseDeDatos2/TP4/tp_desnormalizacion_top_categorias.sql`
- `../../BaseDeDatos2/TP4/tp_fnbc_control_lote.sql`

### TP5 (12 scripts)
- `../../BaseDeDatos2/TP5/scripts/anonimizar_log.py`
- `../../BaseDeDatos2/TP5/scripts/test_anonimizar_log.py`
- `../../BaseDeDatos2/TP5/sql/auditoria_config.sql`
- `../../BaseDeDatos2/TP5/sql/auditoria_test.sql`
- `../../BaseDeDatos2/TP5/sql/equivalencia_usuario_anon.sql`
- `../../BaseDeDatos2/TP5/sql/roles.sql`
- `../../BaseDeDatos2/TP5/sql/simulacro_incidente.sql`
- `../../BaseDeDatos2/TP5/sql/test_roles.sql`
- `../../BaseDeDatos2/TP5/sql/test_usuario_anon.sql`
- `../../BaseDeDatos2/TP5/sql/usuario_anon.sql`
- `../../BaseDeDatos2/TP5/sql/usuario_autenticacion.sql`
- `../../BaseDeDatos2/TP5/sql/verificacion_roles.sql`

### TP6 (7 scripts)
- `../../BaseDeDatos2/TP6/backup_foodstore.ps1`
- `../../BaseDeDatos2/TP6/health_check.sql`
- `../../BaseDeDatos2/TP6/informe/generar_pdf.sh`
- `../../BaseDeDatos2/TP6/maintenance.sql`
- `../../BaseDeDatos2/TP6/restore_test.ps1`
- `../../BaseDeDatos2/TP6/tests/test_maintenance.sh`
- `../../BaseDeDatos2/TP6/tests/test_restore.sh`

### Proyecto Integrador (27 scripts)
- `../../BaseDeDatos2/Proyecto_Integrador/database/consultas_avanzadas.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/generar_registros_adaptado.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/indices_parciales_soft_delete.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/materializadas.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/procedures.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/schema.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/seed.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/test_procedures.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tests_tp4/test_auditoria.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tests_tp4/test_baja_logica.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tests_tp4/test_concurrencia.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tests_tp4/test_datos_prueba.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tests_tp4/test_dia_negocio.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tests_tp4/test_fnbc_descomposicion.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tests_tp4/test_fnbc_esquema_original.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tests_tp4/test_fnbc_restricciones_indices.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tests_tp4/test_fnbc_vista_migracion.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tests_tp4/test_reporte_top5.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tests_tp4/test_reversibilidad.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tests_tp4/test_trigger_detalle.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tests_tp4/test_trigger_pedido_producto.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tests_tp4/test_ventas_diarias_estructura.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tp4_datos_prueba_top_categorias.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tp4_desnormalizacion_top_categorias.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/tp4_fnbc_control_lote.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/triggers.sql`
- `../../BaseDeDatos2/Proyecto_Integrador/database/views.sql`

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
Sos un agente de code review de solo lectura. Se te solicita realizar una revision tecnica de los scripts de la cursada de Bases de Datos II, especialmente de TP7 y TP8 (en este repo) y de TP1 a TP6 / Proyecto Integrador (en ../../BaseDeDatos2/).

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
| **CORR-02** | TP7: `consultas_postgresql.sql` | Rendimiento | **Aceptado** | Filtrar tempranamente por los 9 pedidos migrados reduce el escaneo de 621.853 filas a 31 filas (aceleración > 400x). Ver sección 5. |
| **CORR-03** | TP8: `scripts/correr_casos.sh` | Correctitud | **Descartado con refutación** | La carpeta en el disco del host está instalada literalmente como `D:\DevTools\PosgresSQL`. Modificarla hubiera roto la ejecución en este entorno. Se agregaron ambas rutas para portabilidad. Ver sección 5. |
| **INTEG-01** | TP8: `movil/schema_sqlite.sql` | Integridad | **Aceptado** | SQLite no persiste el pragma de claves foráneas por archivo; se documenta como requisito contractual para cualquier cliente externo. |
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
* **Comprobación y refutación empírica:** Registrada en [`evidencias/code_review_1.txt`](../evidencias/code_review_1.txt). Se comprobó en SQLite que ambas solicitudes simulan aprobado, pero esto responde estrictamente al modelo de consistencia eventual de la aplicación:
  1. Cada tablet opera desconectada y monousuario en la feria; el semáforo es solo una **propuesta de simulación**, nunca una venta ni reserva de inventario.
  2. Si la tablet descontara stock localmente sin comunicación bidireccional, múltiples tablets generarían inventarios locales divergentes y falsas sensaciones de stock.
  3. Controlar el stock entre varias ventas le corresponde al servidor cuando la venta se confirme. Eso queda fuera del TP8: la tablet nunca escribe en PostgreSQL.

### Hallazgo 2 (TP7): [CORR-02] Agrupación sobre tabla completa en vista comparativa
* **Descripción de la IA:** En `consultas_postgresql.sql`, `CREATE TEMP VIEW pedido_total` agrega las 621.853 filas de `pedido_detalle` antes de emparejar con los 9 pedidos de la muestra de MongoDB.
* **Decisión:** **ACEPTADO**.
* **Comprobación empírica:** Registrada en [`evidencias/code_review_2.txt`](../evidencias/code_review_2.txt). Se comprobó analizando los planes de ejecución en PostgreSQL:
  - Sin filtro temprano: HashAggregate / GroupAggregate sobre 621.853 filas, escaneando ~24.000 buffers (~85 ms).
  - Con filtro temprano (`WHERE d.pedido_id IN (SELECT id FROM migrados)`): Index Scan guiado sobre 31 filas, utilizando 18 buffers (< 0.2 ms), logrando una aceleración superior a 400x.

### Hallazgo 3 (TP8): [CORR-03] Supuesto error tipográfico en ruta `PosgresSQL`
* **Descripción de la IA:** La IA afirmó que la ruta `/d/DevTools/PosgresSQL/bin` contenía una errata tipográfica (falta de la letra `t`) que causaría fallos en la ejecución de scripts.
* **Decisión:** **DESCARTADO con refutación en el sistema de archivos**.
* **Comprobación empírica:** Registrada en [`evidencias/code_review_3.txt`](../evidencias/code_review_3.txt). Al inspeccionar el directorio físico del host (`D:\DevTools\`), se comprobó que el directorio de instalación real se llama exactamente `PosgresSQL`. Modificarlo a ciegas hubiera roto la ejecución en la máquina del usuario. Para maximizar la portabilidad sin romper el entorno, se configuraron ambas variantes en el `PATH`.

