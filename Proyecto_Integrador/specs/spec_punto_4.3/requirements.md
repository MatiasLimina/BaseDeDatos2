# Requirements Document

## Introduction

Esta especificación cubre la creación de la **vista materializada de facturación por categoría y mes** del sistema Food Store (TP3, punto 4.3).

El reporte elegido consolida la facturación histórica agrupando los subtotales de `pedido_detalle` por el nombre de la categoría del producto y por el mes del pedido (usando `DATE_TRUNC('month', pedido.fecha)`). Se trata de una consulta costosa: involucra cuatro JOINs (`pedido_detalle → pedido`, `pedido_detalle → producto`, `producto → categoria`) y una agregación `SUM` + `COUNT DISTINCT` sobre cientos de miles de filas, lo que la hace candidata natural a materialización.

La vista materializada `mv_facturacion_categoria_mes` se crea con `WITH DATA` para que el resultado quede persistido en disco desde el momento de su creación. Un índice `UNIQUE` sobre `(categoria, mes)` hace posible el `REFRESH MATERIALIZED VIEW CONCURRENTLY` en el futuro, permitiendo refrescar los datos sin bloquear lecturas concurrentes.

Los cinco requisitos que siguen cubren:
- **Requisito 1** — Creación de la vista materializada con `WITH DATA`.
- **Requisito 2** — Creación del índice `UNIQUE` sobre `(categoria, mes)`.
- **Requisito 3** — Medición comparativa de rendimiento (consulta original vs. `SELECT` sobre la vista).
- **Requisito 4** — Justificación de la frecuencia de refresco y su impacto en los usuarios.
- **Requisito 5** — Documentación en `TP3/informe_mediciones.md` (sección §9).

---

## Glossary

- **Sistema_Vistas_Mat**: El módulo de base de datos responsable de definir, mantener y refrescar las vistas materializadas en PostgreSQL.
- **Vista_Materializada**: Objeto de PostgreSQL que almacena físicamente el resultado de una consulta en disco. A diferencia de una vista ordinaria, su contenido no se recalcula en cada consulta; se actualiza explícitamente con `REFRESH MATERIALIZED VIEW`.
- **mv_facturacion_categoria_mes**: Vista materializada que consolida, por nombre de categoría y mes, el total de pedidos distintos y la facturación total (suma de subtotales). Su definición SQL es la consulta de referencia indicada en la consigna.
- **Consulta_Original**: La consulta SQL con cuatro JOINs y agregación `SUM`/`COUNT DISTINCT` que la vista materializa; es el punto de referencia para la medición comparativa de rendimiento.
- **REFRESH_CONCURRENTLY**: Modalidad de `REFRESH MATERIALIZED VIEW` que actualiza el contenido de la vista sin adquirir un bloqueo exclusivo, permitiendo lecturas simultáneas durante el proceso. Requiere la existencia de al menos un índice `UNIQUE` sobre la vista.
- **Latencia_de_Dato**: Diferencia temporal entre el momento en que ocurre una transacción en las tablas base y el momento en que esa transacción queda reflejada en la vista materializada tras el siguiente `REFRESH`. Con frecuencia de refresco diaria, la latencia máxima es de aproximadamente 24 horas.
- **Reporte_de_Gestión**: Reporte orientado a la toma de decisiones históricas o periódicas (cierre de mes, análisis de tendencias), para el cual una latencia de hasta 24 horas es aceptable.
- **Dashboard_Tiempo_Real**: Interfaz de monitoreo que requiere datos actualizados en segundos o minutos; incompatible con la política de refresco diario de `mv_facturacion_categoria_mes`.
- **EXPLAIN_ANALYZE**: Comando de PostgreSQL que ejecuta una consulta y retorna el plan de ejecución real con tiempos de planificación y ejecución (`Planning Time` y `Execution Time`), utilizado para medir el impacto de la materialización.
- **WITH_DATA**: Cláusula de `CREATE MATERIALIZED VIEW` que indica que la vista debe poblarse con datos al momento de su creación. La alternativa `WITH NO DATA` crea la estructura sin datos, requiriendo un `REFRESH` explícito antes del primer uso.

---

## Requirements

---

### Requisito 1 — Creación de la vista materializada con WITH DATA

**User Story:** Como analista de negocio, quiero consultar la facturación total agrupada por categoría y mes sin esperar a que la base ejecute cuatro JOINs y una agregación sobre cientos de miles de filas cada vez, para que los reportes de gestión respondan en milisegundos en lugar de segundos.

#### Criterios de Aceptación

1. THE `Sistema_Vistas_Mat` SHALL crear un objeto de tipo `MATERIALIZED VIEW` denominado `mv_facturacion_categoria_mes` en el esquema público de la base de datos.

2. WHEN se ejecuta la sentencia de creación, THE `Sistema_Vistas_Mat` SHALL utilizar la cláusula `WITH DATA` de modo que la vista quede inmediatamente poblada con los datos vigentes en las tablas base al momento de la creación.

3. THE `Sistema_Vistas_Mat` SHALL definir `mv_facturacion_categoria_mes` con exactamente las columnas `categoria` (`c.nombre`), `mes` (`DATE_TRUNC('month', p.fecha)`), `total_pedidos` (`COUNT(DISTINCT p.id)`) y `facturacion_total` (`SUM(pd.subtotal)`).

4. THE `Sistema_Vistas_Mat` SHALL implementar la consulta subyacente con los siguientes JOINs: `pedido_detalle pd JOIN pedido p ON pd.pedido_id = p.id`, `pedido_detalle pd JOIN producto pr ON pd.producto_id = pr.id`, y `producto pr JOIN categoria c ON pr.categoria_id = c.id`.

5. THE `Sistema_Vistas_Mat` SHALL aplicar `GROUP BY c.nombre, DATE_TRUNC('month', p.fecha)` y `ORDER BY mes DESC, facturacion_total DESC` en la definición de la vista.

6. WHEN un consumidor ejecuta `SELECT * FROM mv_facturacion_categoria_mes`, THE `Sistema_Vistas_Mat` SHALL retornar el resultado desde los datos materializados en disco, sin re-ejecutar los JOINs ni la agregación sobre las tablas base.

---

### Requisito 2 — Creación del índice UNIQUE sobre (categoria, mes)

**User Story:** Como administrador de base de datos, quiero que la vista materializada tenga un índice único sobre las columnas `(categoria, mes)`, para poder ejecutar `REFRESH MATERIALIZED VIEW CONCURRENTLY` en el futuro sin bloquear las lecturas en curso.

#### Criterios de Aceptación

1. THE `Sistema_Vistas_Mat` SHALL crear un índice de tipo `UNIQUE` sobre `mv_facturacion_categoria_mes` con las columnas `(categoria, mes)` inmediatamente después de la creación de la vista.

2. WHEN se intenta ejecutar `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes`, THE `Sistema_Vistas_Mat` SHALL completar la operación sin adquirir un bloqueo exclusivo sobre la vista, gracias a la existencia del índice `UNIQUE`.

3. THE `Sistema_Vistas_Mat` SHALL nombrar el índice `idx_mv_facturacion_categoria_mes` para garantizar que el nombre sea descriptivo e identificable en el catálogo del sistema.

4. IF la combinación `(categoria, mes)` no es única en el resultado de la consulta subyacente, THEN THE `Sistema_Vistas_Mat` SHALL producir un error de violación de unicidad al intentar crear el índice, señalando que la definición de la vista debe revisarse para garantizar una fila por par `(categoria, mes)`.

5. THE `Sistema_Vistas_Mat` SHALL documentar en un comentario inline del archivo SQL que el índice `UNIQUE` es un prerrequisito técnico de `REFRESH CONCURRENTLY` y no un índice de rendimiento de búsqueda primario.

---

### Requisito 3 — Medición comparativa de rendimiento

**User Story:** Como responsable de calidad de la base de datos, quiero medir el tiempo de la consulta original con cuatro JOINs y agregación frente al tiempo de un `SELECT` sobre la vista materializada, para cuantificar el beneficio de la materialización y justificar el costo de mantenimiento.

#### Criterios de Aceptación

1. THE `Sistema_Vistas_Mat` SHALL incluir en el archivo `materializadas.sql` un bloque `EXPLAIN (ANALYZE, BUFFERS)` ejecutado sobre la `Consulta_Original` (los cuatro JOINs con agregación) antes de crear la vista materializada, registrando `Planning Time` y `Execution Time`.

2. THE `Sistema_Vistas_Mat` SHALL incluir en el archivo `materializadas.sql` un bloque `EXPLAIN (ANALYZE, BUFFERS)` ejecutado sobre `SELECT * FROM mv_facturacion_categoria_mes` después de crear la vista, registrando `Planning Time` y `Execution Time`.

3. WHEN se comparan ambos resultados de `EXPLAIN ANALYZE`, THE `Sistema_Vistas_Mat` SHALL demostrar que el `Execution Time` del `SELECT` sobre la vista materializada es inferior al `Execution Time` de la `Consulta_Original`, dado que el primero lee páginas ya materializadas en disco en lugar de ejecutar JOINs y agregaciones.

4. THE `Sistema_Vistas_Mat` SHALL documentar los resultados de ambas mediciones en la sección §9 del archivo `TP3/informe_mediciones.md`, incluyendo los valores de `Planning Time`, `Execution Time` y el método de acceso (`Seq Scan` sobre la vista vs. plan de JOINs original).

5. IF las mediciones no pueden realizarse sobre la base poblada con el conjunto de datos completo, THEN THE `Sistema_Vistas_Mat` SHALL indicar explícitamente en `informe_mediciones.md` el volumen de datos sobre el que se ejecutaron las pruebas y cualquier condición que afecte la representatividad de los resultados.

---

### Requisito 4 — Justificación de la frecuencia de refresco y latencia para los usuarios

**User Story:** Como responsable de operaciones, quiero conocer con qué frecuencia debe ejecutarse el `REFRESH MATERIALIZED VIEW` y qué implica para los usuarios que los datos no se actualicen en tiempo real, para poder comunicar correctamente las limitaciones del reporte a los equipos de negocio.

#### Criterios de Aceptación

1. THE `Sistema_Vistas_Mat` SHALL proponer en `informe_mediciones.md` una frecuencia de refresco de al menos una vez por día (preferiblemente durante la madrugada o al cierre de la jornada operativa), justificando que el reporte consolida facturación histórica de cierre de mes y no requiere datos en tiempo real.

2. THE `Sistema_Vistas_Mat` SHALL documentar que la `Latencia_de_Dato` máxima con refresco diario es de aproximadamente 24 horas, lo que significa que transacciones realizadas después del último `REFRESH` no serán visibles en `mv_facturacion_categoria_mes` hasta el siguiente ciclo de refresco.

3. THE `Sistema_Vistas_Mat` SHALL especificar en `informe_mediciones.md` que `mv_facturacion_categoria_mes` es adecuada para `Reporte_de_Gestión` (análisis de tendencias, cierre mensual, decisiones comerciales) y no adecuada para `Dashboard_Tiempo_Real` ni para consultas transaccionales que requieran el estado actual de las ventas.

4. WHERE el sistema opere en un entorno con alta carga de inserción de pedidos durante la jornada comercial, THE `Sistema_Vistas_Mat` SHALL documentar la opción de incrementar la frecuencia de refresco a cada 4-6 horas, evaluando el costo de CPU y I/O que implica re-materializar la consulta con los cuatro JOINs y la agregación completa sobre el volumen de datos vigente.

5. THE `Sistema_Vistas_Mat` SHALL documentar en `informe_mediciones.md` el comando exacto para ejecutar el refresco concurrente: `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes;`, indicando que este comando puede incluirse en un trabajo `pg_cron` o en un script de mantenimiento nocturno.

6. IF se decide en el futuro aumentar la frecuencia de refresco a intervalos inferiores a una hora, THEN THE `Sistema_Vistas_Mat` SHALL evaluar si la vista materializada sigue siendo la herramienta adecuada o si conviene reemplazarla por una vista ordinaria con índices optimizados, dado que el costo de refresco frecuente podría superar el beneficio de la materialización.

---

### Requisito 5 — Documentación en TP3/informe_mediciones.md

**User Story:** Como estudiante responsable del TP3, quiero que todos los resultados de medición y las justificaciones de diseño queden registrados en una nueva sección §9 del informe de mediciones, para completar el entregable del punto 4.3 sin alterar el contenido de las secciones previas.

#### Criterios de Aceptación

1. THE `Sistema_Vistas_Mat` SHALL agregar una nueva sección denominada `## 9. TP3 Parte C — Vista materializada mv_facturacion_categoria_mes` al final del archivo `TP3/informe_mediciones.md`, sin modificar ni reemplazar ninguna de las secciones §1 a §8 ya existentes.

2. WHEN se agrega la sección §9, THE `Sistema_Vistas_Mat` SHALL incluir las subsecciones: descripción del reporte elegido, SQL de la vista materializada y su índice, tabla comparativa de tiempos (consulta original vs. vista materializada), justificación de la frecuencia de refresco, análisis de la `Latencia_de_Dato`, y una nota de Declaración de Uso de IA (DUIA).

3. THE `Sistema_Vistas_Mat` SHALL mantener el mismo estilo de formato que las secciones §2 a §8 del informe: tablas Markdown con columnas `Métrica | Antes | Después | Δ`, bloques de código SQL con triple backtick, y texto analítico en prosa.

4. IF los valores de `EXPLAIN ANALYZE` aún no han sido medidos en el entorno real del estudiante, THEN THE `Sistema_Vistas_Mat` SHALL incluir marcadores de placeholder `[COMPLETAR CON VALOR REAL]` en los campos numéricos correspondientes, de modo que el informe sea entregable como borrador sin datos ficticios.

5. THE `Sistema_Vistas_Mat` SHALL incluir en la sección §9 la tabla resumen de entregables del punto 4.3 con las rutas exactas de los archivos `materializadas.sql` e `informe_mediciones.md`.
