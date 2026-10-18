# Tasks

> **Convenciones de ejecución**
> - Base de trabajo: **solo** `tp4_foodstore` (nunca `food_store` ni `food_store_copia`). Ejecutar SQL vía MCP `postgres` (`execute`/`query`) o `psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f <archivo>`.
> - **Strict TDD**: cada unidad sigue RED → GREEN → TRIANGULATE → REFACTOR. RED se da por cumplido sólo si el test falla **por la razón esperada** (objeto inexistente o aserción falsa); anotar el mensaje de error en el resumen de la tarea. Tests en `TP4/tests/*.sql` con bloques `DO $$ ... ASSERT ... $$`; los que modifican datos van entre `BEGIN; ... ROLLBACK;` (o `SAVEPOINT`).
> - **Commits**: uno por grupo (Conventional Commits en español, scope `tp4`); los ejecuta el orquestador. Se indica el mensaje sugerido al final de cada grupo. Sin `push`.
> - **Gobernanza MEDIUM**: en cada `CHECKPOINT` detener y exponer al usuario/orquestador las decisiones no obvias antes de seguir.
> - No tocar `Proyecto_Integrador/` hasta el grupo 13 y sólo con confirmación explícita del usuario.

## 1. Preparación del entorno

- [x] 1.1 Verificar que el MCP apunta a la base correcta: `SELECT current_database()` devuelve `tp4_foodstore`; si no, detener y avisar.
- [x] 1.2 Crear las carpetas `TP4/tests/` y `TP4/evidencias/`; verificar que existen.

## 2. Parte 1 – Esquema original e instancia de ejemplo

- [x] 2.1 RED: escribir `TP4/tests/test_fnbc_esquema_original.sql` (tabla `control_lote_almacen` con exactamente las filas `(501,30,801)`, `(502,30,801)`, `(503,31,802)`; PK rechaza `(501,30,802)`; FK rechaza un `lote_id` inexistente). Ejecutarlo y verificar que falla con "relation ... does not exist".
- [x] 2.2 GREEN: crear `TP4/tp_fnbc_control_lote.sql` sección 1: encabezado estilo `schema.sql`, `DROP ... IF EXISTS ... CASCADE` de los objetos propios, tablas mínimas `lote`, `deposito`, `usuario` (`BIGINT GENERATED ALWAYS AS IDENTITY`, inserción con `OVERRIDING SYSTEM VALUE` + `setval`), tabla `control_lote_almacen` tal como la consigna e instancia de ejemplo. Ejecutar script + test → pasa.
- [x] 2.3 TRIANGULATE: ejecutar el script dos veces seguidas y luego el test; verificar que ambas ejecuciones terminan sin error y el test sigue pasando (idempotencia).
- [x] 2.4 REFACTOR: comentarios que justifiquen cada `NOT NULL`, FK y `ON DELETE RESTRICT`; re-ejecutar script + test → pasa.
- Commit sugerido: `feat(tp4): esquema original control_lote_almacen con instancia de ejemplo`

## 3. Parte 1 – Análisis de dependencias funcionales (documentación)

- [x] 3.1 Agregar al script una consulta de evidencia de la DF `Responsable → Depósito` sobre la instancia (`GROUP BY responsable_control_id HAVING count(DISTINCT deposito_id) > 1` → 0 filas) y ejecutarla; verificar 0 filas.
- [x] 3.2 Crear `TP4/informe_tp4.md` con la sección Parte 1 a)–d): DFs en notación formal; tabla de clausuras de `{L}`, `{D}`, `{R}`, `{L,D}`, `{L,R}`, `{D,R}`; claves candidatas `{L,D}` y `{L,R}`; atributos primos (los tres); 3FN sí / FNBC no con la DF violatoria `R → D` y `R⁺ = {R, D}` ≠ esquema; un párrafo por anomalía (inserción, borrado, actualización) sobre 501/502/503, 30/31, 801/802. Verificar contra los escenarios de `specs/control-lote-almacen/spec.md` (requisito "Análisis formal...").
- Commit sugerido: `docs(tp4): análisis de dependencias funcionales y violación de FNBC`

## 4. Parte 1 – Descomposición en FNBC

- [x] 4.1 RED: escribir `TP4/tests/test_fnbc_descomposicion.sql` (existen `responsable_deposito` con PK `responsable_control_id` y `control_lote` con PK `(lote_id, responsable_control_id)`; FKs con `confdeltype = 'r'` en `pg_constraint`; asignar 801 al depósito 31 es rechazado por PK; `control_lote` con responsable fuera de `responsable_deposito` es rechazado por FK). Ejecutar y verificar que falla por objeto inexistente.
- [x] 4.2 GREEN: sección 2 del script con `responsable_deposito` y `control_lote` (FK de `control_lote` hacia `responsable_deposito`, mismo nombre de columna `responsable_control_id`). Ejecutar script + test → pasa.
- [x] 4.3 TRIANGULATE: agregar al test que borrar un `deposito` referenciado por `responsable_deposito` es rechazado (`RESTRICT`) y que borrar un `lote` con controles también; ejecutar → pasa.
- [x] 4.4 Documentar en `informe_tp4.md` el punto e): algoritmo aplicado sobre `R → D`, esquemas resultantes, por qué cada uno está en FNBC (único determinante = clave) y extracto del script. Verificar que el extracto coincide con el script.
- Commit sugerido: `feat(tp4): descomposición FNBC de control_lote_almacen` (puede precederlo `test(tp4): ...` si se separa RED)

## 5. Parte 1 – Vista de compatibilidad y migración verificada

- [x] 5.1 RED: escribir `TP4/tests/test_fnbc_vista_migracion.sql` (existe `v_control_lote_almacen`; `EXCEPT` en ambos sentidos = 0 filas; mismo `count(*)` = 3; dentro de `ROLLBACK`, cambiar el depósito de 801 en `responsable_deposito` modifica una sola fila y la vista lo refleja para 501 y 502). Ejecutar y verificar que falla por vista inexistente.
- [x] 5.2 GREEN: sección 3 del script: verificación previa de la DF, migración `INSERT ... SELECT DISTINCT` a `responsable_deposito` e `INSERT ... SELECT` a `control_lote`, vista con `NATURAL JOIN`, y consultas `EXCEPT` en ambos sentidos al final. Ejecutar script + test → pasa.
- [x] 5.3 TRIANGULATE: agregar al test (y como bloque comentado/`ROLLBACK` en el script) la demostración de la DF no preservada: alta del responsable 803 en depósito 30 y control `(501, 803)` → aceptado y la vista muestra dos responsables para `(501,30)`. Ejecutar → pasa.
- [x] 5.4 Documentar en `informe_tp4.md` el punto f): unión sin pérdida por superclave del atributo común (`R` es clave de `responsable_deposito`), evidencia `EXCEPT` = 0 filas, y el costo de no preservar `{L,D} → R` con las mitigaciones posibles.
- [x] 5.5 CHECKPOINT: exponer al usuario la pregunta abierta de `design.md` (¿imponer `{L,D} → R` con disparador?). Si responde que sí, agregar RED/GREEN de ese disparador antes del commit; si no, seguir. **Resuelto: el usuario decidió SOLO documentar y demostrar la DF perdida (sin disparador).**
- [x] 5.6 Verificación de la Parte 1: ejecutar `tp_fnbc_control_lote.sql` completo dos veces y luego los tres `test_fnbc_*.sql` → todos pasan.
- Commit sugerido: `feat(tp4): vista de compatibilidad y migración verificada de control_lote`

## 6. Parte 2 – Adaptación del schema y datos de prueba

- [x] 6.1 RED: escribir `TP4/tests/test_baja_logica.sql` (`pedido.eliminado` y `pedido_detalle.eliminado` existen, `BOOLEAN NOT NULL DEFAULT false`; ningún registro existente con `eliminado` distinto de `FALSE` antes de la carga; asignar `NULL` es rechazado dentro de `ROLLBACK`). Ejecutar → falla por columna inexistente.
- [x] 6.2 RED: escribir `TP4/tests/test_dia_negocio.sql` (`fn_dia_negocio('2026-10-18 23:30-03')` = `2026-10-18` con `SET LOCAL TimeZone = 'UTC'` y con `'America/Argentina/Buenos_Aires'`; la función es `IMMUTABLE`). Ejecutar → falla por función inexistente.
- [x] 6.3 GREEN: crear `TP4/tp_desnormalizacion_top_categorias.sql` sección 1: `ALTER TABLE ... ADD COLUMN IF NOT EXISTS eliminado BOOLEAN NOT NULL DEFAULT FALSE` en ambas tablas y `fn_dia_negocio` con zona `America/Argentina/Buenos_Aires`. Ejecutar sección + ambos tests → pasan.
- [x] 6.4 RED: escribir `TP4/tests/test_datos_prueba.sql` (≥ 8 categorías con ventas no eliminadas en el día de negocio actual; ≥ 100 000 detalles no eliminados de pedidos no eliminados del día; existen pedidos y detalles del día con `eliminado = TRUE`). Ejecutar → falla por aserción (hoy hay 0 pedidos).
- [x] 6.5 CHECKPOINT: antes de cargar, exponer al usuario el volumen previsto (≈ 50 000 pedidos / ≥ 150 000 detalles del día), la creación de 7 categorías y la redistribución de productos por `id % 10` en `tp4_foodstore`.
- [x] 6.6 GREEN: sección 2 del script (marcada "solo en copia"): categorías con `ON CONFLICT (nombre) DO NOTHING`, redistribución de productos, bloque `DO` con guarda anti-duplicado que genera pedidos y detalles del día con `generate_series` (productos distintos por pedido, `subtotal = cantidad * precio_unitario`, una fracción con `eliminado = TRUE`) y `ANALYZE`. Ejecutar + `test_datos_prueba.sql` → pasa.
- [x] 6.7 TRIANGULATE: re-ejecutar la sección 2 y verificar que el conteo de detalles del día no cambia (guarda) y los tests siguen pasando.
- [x] 6.8 Documentar en `informe_tp4.md` (intro de Parte 2) las adaptaciones al schema real: `pedido_detalle`, `eliminado`, `TIMESTAMPTZ` vs `= CURRENT_DATE`, zona horaria de negocio, datos generados y fecha de medición.
- Commit sugerido: `feat(tp4): baja lógica eliminado y datos de prueba del día`

## 7. Parte 2 – Medición baseline (5.2 a)

- [x] 7.1 Agregar al script la consulta original adaptada (sección 3): `pedido_detalle`, filtro por rango del día de negocio (`fecha >= inicio AND fecha < inicio + 1 día`), `eliminado = FALSE` en pedido y detalle, `GROUP BY c.nombre ORDER BY total_vendido DESC LIMIT 5`. Ejecutarla y verificar que devuelve 5 filas.
- [x] 7.2 Ejecutar `EXPLAIN (ANALYZE, BUFFERS)` 3 veces y guardar las salidas completas en `TP4/evidencias/explain_antes.txt`; verificar que el archivo contiene 3 líneas `Execution Time` e identificar el nodo dominante.
- [x] 7.3 Documentar en `informe_tp4.md` el punto a): tiempo (mediana), nodo dominante y por qué domina (con extracto del plan).
- Commit sugerido: `test(tp4): medición baseline de la consulta top 5 normalizada`

## 8. Parte 2 – Estructura desnormalizada y disparadores (5.2 b, c)

- [x] 8.1 RED: escribir `TP4/tests/test_ventas_diarias_estructura.sql` (tabla `ventas_diarias_categoria` con PK `(fecha, categoria_id)`, FK a `categoria`, CHECKs `total_vendido >= 0` y `cantidad_lineas >= 0`; comparación inline contra la fuente con `FULL OUTER JOIN` = 0 diferencias tras la carga inicial). Ejecutar → falla por tabla inexistente.
- [x] 8.2 GREEN: sección 4 del script: transacción con `LOCK TABLE pedido, pedido_detalle, producto IN SHARE ROW EXCLUSIVE MODE`, tabla, `fn_vdc_aplicar` (upsert `ON CONFLICT DO UPDATE` + borrado de la fila al llegar a 0 líneas) y backfill de todo el histórico por `fn_dia_negocio` y categoría. Ejecutar + test → pasa.
- [x] 8.3 RED: escribir `TP4/tests/test_trigger_detalle.sql` con un escenario por caso del spec (alta +100.00; subtotal 100→250 = +150.00; cambio de producto entre categorías; baja lógica y reactivación; borrado físico; la fila desaparece al quitar la última línea; `ROLLBACK TO SAVEPOINT` no deja residuos; detalle agregado a un pedido eliminado no suma). Ejecutar → falla por aserción (sin disparador el total no cambia).
- [x] 8.4 GREEN: función y disparador `trg_vdc_pedido_detalle` (`AFTER INSERT OR UPDATE OF subtotal, producto_id, pedido_id, eliminado OR DELETE FOR EACH ROW`, quitar `OLD` + agregar `NEW`). Ejecutar + test → pasa.
- [x] 8.5 RED: escribir `TP4/tests/test_trigger_pedido_producto.sql` (baja lógica de pedido con detalles en 2 categorías y reactivación; cambio de fecha hoy→ayer; recategorización de un producto con ventas en varios días). Ejecutar → falla por aserción.
- [x] 8.6 GREEN: disparadores `trg_vdc_pedido` (`AFTER UPDATE OF eliminado, fecha ... WHEN (... IS DISTINCT FROM ...)`) y `trg_vdc_producto` (`AFTER UPDATE OF categoria_id ... WHEN (...)`). Ejecutar + test → pasa.
- [x] 8.7 REFACTOR: extraer la lógica de "contribución de una línea" común a los tres disparadores, mover la creación de disparadores dentro de la transacción con `LOCK` antes del backfill, comentarios de concurrencia; re-ejecutar los tres tests de la sección → pasan.
- [x] 8.8 RED/GREEN: escribir `TP4/tests/test_reversibilidad.sql` (dentro de `ROLLBACK`: guardar resultado de la consulta normalizada, ejecutar el bloque de reversión `DROP TRIGGER/FUNCTION/TABLE`, verificar que no quedan disparadores `trg_vdc_%` y que la consulta normalizada da el mismo resultado). Agregar el bloque de reversión comentado al final del script. Ejecutar → pasa.
- [x] 8.9 CHECKPOINT: exponer al usuario las decisiones no obvias antes del commit: categoría no congelada a la fecha de venta, `NUMERIC(14,2)`, borrado de filas en 0 líneas, fila caliente/deadlock, `TRUNCATE` no sincronizado.
- [x] 8.10 Documentar en `informe_tp4.md` el punto b) en **un solo párrafo** (evidencia medida en 7.2, mecanismo anti-desincronización, reversibilidad; por qué no vista materializada) y el punto c) (estructura, disparadores, casos borde, concurrencia, carga inicial con bloqueo). Verificar que b) es un único párrafo y responde las tres preguntas.
- Commit sugerido: `feat(tp4): tabla ventas_diarias_categoria sincronizada por disparadores`

## 9. Parte 2 – Consulta desnormalizada y medición final (5.2 d)

- [x] 9.1 RED: escribir `TP4/tests/test_reporte_top5.sql` (existe `v_top5_categorias_dia`; sus filas y su orden, vía `row_number()`, coinciden con la consulta normalizada embebida en el test; `EXCEPT` en ambos sentidos = 0). Ejecutar → falla por vista inexistente.
- [x] 9.2 GREEN: sección 5 del script: consulta suelta del reporte sobre `ventas_diarias_categoria` (unida a `categoria` sólo para el nombre, filtro `fecha = fn_dia_negocio(now())`) y vista `v_top5_categorias_dia`. Ejecutar + test → pasa.
- [x] 9.3 TRIANGULATE: agregar al test un caso dentro de `SAVEPOINT`: insertar un detalle grande para la categoría en 6.º puesto para que entre al top 5; ambas consultas vuelven a coincidir. Ejecutar → pasa.
- [x] 9.4 Ejecutar `EXPLAIN (ANALYZE, BUFFERS)` 3 veces sobre la consulta suelta y guardar en `TP4/evidencias/explain_despues.txt`; verificar que la mediana es menor que la de 7.2.
- [x] 9.5 Documentar en `informe_tp4.md` el punto d): consulta, tabla de dos columnas antes/después (tiempo y nodo dominante) y lectura de los planes.
- Commit sugerido: `feat(tp4): consulta top 5 desde estructura desnormalizada y medición final`

## 10. Parte 2 – Auditoría (5.2 e)

- [ ] 10.1 RED: escribir `TP4/tests/test_auditoria.sql` (existe `v_auditoria_ventas_diarias` y devuelve 0 filas; dentro de `ROLLBACK`, un `UPDATE` manual de `total_vendido` en una fila hace que la auditoría devuelva exactamente esa fila; borrar a mano una fila también es detectado). Ejecutar → falla por vista inexistente.
- [ ] 10.2 GREEN: sección 6 del script: consulta de auditoría (recalcula por `fn_dia_negocio` y categoría con `FULL OUTER JOIN` y `IS DISTINCT FROM` en total y líneas) y vista `v_auditoria_ventas_diarias`. Ejecutar + test → pasa; guardar la salida (0 filas) en `TP4/evidencias/auditoria.txt`.
- [ ] 10.3 TRIANGULATE: agregar la aserción "auditoría = 0 filas" al final de `test_trigger_detalle.sql` y `test_trigger_pedido_producto.sql` (antes del `ROLLBACK`); ejecutar todos los tests de Parte 2 → pasan.
- [ ] 10.4 Documentar en `informe_tp4.md` el punto e): script, criterio de comparación y evidencia del resultado vacío.
- Commit sugerido: `feat(tp4): script de auditoría de ventas_diarias_categoria`

## 11. Verificación integral e informe

- [ ] 11.1 Ejecutar `tp_fnbc_control_lote.sql` y `tp_desnormalizacion_top_categorias.sql` de punta a punta (dos veces cada uno) sobre `tp4_foodstore` sin errores, y luego todos los `TP4/tests/*.sql` → todos pasan; registrar la tabla de resultados.
- [ ] 11.2 Completar `informe_tp4.md`: encabezado (materia, integrantes según `TP3/README.md`, link al repo, fecha de medición), protocolo de trabajo sobre `tp4_foodstore`, tabla de adaptaciones consigna vs schema real, conclusiones; verificar con un checklist que cubre Parte 1 a)–f) y Parte 2 a)–e) y que cada afirmación referencia su artefacto.
- [ ] 11.3 Generar el PDF del informe si es viable (revisar `TP3/gen_pdf.py` y sus dependencias); verificar que el PDF abre y contiene las tablas. Si no es viable, dejar constancia y entregar el `.md`.
- [ ] 11.4 CHECKPOINT (orquestador): consulta al `advisor` (FINAL_DIFF) sobre `git diff` antes de declarar cerrado el apply.
- Commit sugerido: `docs(tp4): informe del TP4 con evidencias de FNBC y desnormalización`

## 12. Pruebas manuales

- [ ] 12.1 Crear `TP4/pruebas_manuales.md` con pruebas numeradas; cada una con objetivo, SQL/comando exacto, resultado esperado y casilla `[ ]`. Cubrir como mínimo: instancia original, rechazo de PK/FK, descomposición, `EXCEPT` en ambos sentidos, DF no preservada, `eliminado` por defecto, día de negocio con `TimeZone = 'UTC'`, alta/modificación/baja lógica/borrado de detalle, baja lógica y cambio de fecha de pedido, recategorización de producto, top 5 desnormalizado = normalizado, `EXPLAIN` antes/después, auditoría vacía y auditoría detectando una alteración manual, reversión. Verificar que cada prueba se ejecutó una vez y su resultado coincide con el esperado.
- [ ] 12.2 STOP: presentar `pruebas_manuales.md` al usuario y esperar su confirmación explícita de que las ejecutó y pasaron. No continuar con el grupo 13 sin esa confirmación.
- Commit sugerido: `docs(tp4): guía de pruebas manuales`

## 13. Integración al Proyecto Integrador (sólo tras confirmación del usuario)

- [ ] 13.1 Preguntar al usuario: nombres de archivo destino y si `eliminado` se incorpora a `Proyecto_Integrador/database/schema.sql` o queda como script aparte; recordar que `idx_detalle_producto_id` (usado por `trg_vdc_producto`) no está en `schema.sql`.
- [ ] 13.2 Copiar/adaptar los scripts a `Proyecto_Integrador/database/` según lo acordado; verificar que corren sobre `tp4_foodstore` sin errores. Commit separado: `feat(tp4): integrar FNBC y desnormalización al proyecto integrador`.
- [ ] 13.3 Agregar la sección TP4 a `Proyecto_Integrador/documentos/TPI_FoodStore_Informe_Tecnico_Consolidado.md`; verificar enlaces a scripts. Commit separado: `docs(tp4): incorporar TP4 al informe técnico consolidado`.

## 14. Cierre

- [ ] 14.1 Ejecutar `openspec validate tp4-fnbc-desnormalizacion --strict` y verificar que no hay errores; luego el orquestador puede lanzar `/opsx:archive`.
- [ ] 14.2 Recordar explícitamente al usuario, como último mensaje, que restaure la configuración del MCP `postgres` en `C:\Users\matia\.claude.json`: `PG_ALLOW_WRITE=false` y `DATABASE_URL` apuntando nuevamente a `food_store_copia`. Verificar que el aviso quedó en la respuesta final.
