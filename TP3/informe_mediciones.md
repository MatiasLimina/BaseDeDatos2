# TP3 Parte A — Informe de Mediciones del Plan de Indexado

**Proyecto:** Food Store — Sistema de gestión de pedidos  
**Materia:** Base de Datos II  
**Carrera:** Tecnicatura Universitaria en Programación  
**Autores (Equipo):** Matías Limina, Nicolás Monjelardi, Lautaro Agüero  
**Repositorio GitHub:** [https://github.com/MatiasLimina/BaseDeDatos2.git](https://github.com/MatiasLimina/BaseDeDatos2.git)  
**Motor:** PostgreSQL 16+  
**Fecha:** 05/09/2026 (Actualizado: 23/09/2026)  
**Entregables asociados:** `README.md`, `indices.sql`, `queries.sql`, `views.sql`, `materializadas.sql`, `duia.md`  
**Protocolo de seguridad:** Pruebas ejecutadas sobre copia clonada `foodstore_copia` (según `protocolo_seguridad.md`) respaldada previamente con `pg_dump`, y escrituras en transacciones reversibles (`BEGIN ... ROLLBACK`).  
**Fuente de datos:** `Anotacion_mediciones.txt` (mediciones con `EXPLAIN ANALYZE` y `INSERT` masivo ejecutadas sobre base poblada)

---

## 1. Introducción y contexto del esquema

### 1.1 Esquema evaluado

El sistema Food Store consta de 5 tablas (`TP3/queries.sql:1` y `Proyecto_Integrador/database/schema.sql:30-132`):

| Tabla | PK | FK | Volumen aproximado en la medición |
|---|---|---|---|
| `categoria` | `id BIGINT GENERATED ALWAYS AS IDENTITY` | — | — |
| `producto` | `id` | `categoria_id → categoria(id) ON DELETE RESTRICT` | 50 005 filas |
| `cliente` | `id` | — | — |
| `pedido` | `id` | `cliente_id → cliente(id) ON DELETE RESTRICT` | — |
| `pedido_detalle` | `(pedido_id, producto_id)` compuesta | `pedido_id → pedido(id)`, `producto_id → producto(id)` | 621 199 filas |

Tipos y restricciones relevantes: `forma_pago forma_pago_enum` (`EFECTIVO`, `TARJETA`, `TRANSFERENCIA`, `OTRO`) en `pedido.forma_pago` (`schema.sql:20-25`), `NUMERIC(10,2)` para precios, `CHECK` de no-negatividad (`schema.sql:50-51`, `109-111`), `UNIQUE(email)` en cliente.

### 1.2 Índices preexistentes (TP1)

Dos índices ya presentes en `schema.sql:129-132`:

* `idx_pedido_cliente_id ON pedido(cliente_id)` — búsqueda de pedidos por cliente.
* `idx_producto_categoria_activo ON producto(categoria_id, activo)` — listado de productos activos por categoría.

Ninguno cubre los tres patrones analizados debajo, motivo por el cual las consultas candidatas producían `Seq Scan` antes del plan.

### 1.3 Metodología de medición

* Cada consulta se ejecutó con `EXPLAIN (ANALYZE, BUFFERS)` — se reportan `Planning Time` y `Execution Time` reales del archivo de anotaciones.
* Las escrituras se midieron con un bloque `DO $$ ... INSERT` de ~500 filas en `pedido_detalle` (`queries.sql:28-35`), ejecutado **antes** y **después** de crear los tres índices propuestos.
* El entorno es una única instancia de PostgreSQL sin `pg_prewarm` ni `DISCARD` entre corridas, por lo que el contenido de `shared_buffers` / caché del SO influye entre ejecuciones sucesivas (ver §5).

### 1.4 Resumen ejecutivo

| # | Consulta | Plan ANTES | Plan DESPUÉS | ¿Índice usado? | Conclusión |
|---|---|---|---|---|---|
| 1 | Historial por fecha + forma_pago | Parallel Seq Scan — 289.652 ms | Index Scan `idx_pedido_fecha` — 0.018 ms | **Sí** | **Aceptado:** Aceleración ~16.000×, beneficio empírico rotundo |
| 2 | Ranking Top 5 productos más vendidos | Seq Scan + Hash Join — 423.892 ms | Seq Scan + Hash Join — 218.262 ms | **No** | **Descartado (Sobreindexación):** Planner ignoró el índice; mejora aparente fue sólo por warm cache |
| 3 | Detalle de pedido ORDER BY subtotal | Index Scan PK `pk_pedido_detalle` — 0.055 ms | Index Scan `idx_detalle_subtotal` — 0.102 ms | Sí (sustitución) | **Descartado (Sobreindexación):** Ya resolvía por PK; nuevo índice sumó overhead (+85%) sin beneficio real |
| 4 | Filtro por forma de pago | Parallel Seq Scan | — | — | **Descartado:** Baja cardinalidad (4 valores ENUM, selectividad ~25%) |
| — | INSERT 500 filas en `pedido_detalle` | 0.313 s | 0.058 s | — | Resultado paradójico por warm cache en `shared_buffers` |

---

## 2. Consulta 1 — Historial de ventas por fecha (caso exitoso)

### 2.1 SQL (`queries.sql:5-7`)

```sql
SELECT * FROM pedido
WHERE fecha BETWEEN '2023-01-01' AND '2023-12-31'
  AND forma_pago = 'EFECTIVO';
```

### 2.2 Especificación

* **Frecuencia:** Alta — reporte operativo diario/semanal del área de ventas.
* **Columnas de filtro:** `pedido.fecha` (rango `BETWEEN`) + `pedido.forma_pago` (igualdad sobre `forma_pago_enum`).
* **JOIN / ORDER BY:** Ninguno.
* **Por qué producía Seq Scan:** No existía índice sobre `fecha`. El único índice en `pedido` era `idx_pedido_cliente_id(cliente_id)`, inutilizable para este predicado. El planner no tenía alternativa al `Parallel Seq Scan`.

### 2.3 Índice propuesto (`indices.sql:5`)

```sql
CREATE INDEX idx_pedido_fecha ON pedido(fecha);
```

* **Tipo:** B-tree (default, óptimo para rangos).
* **Columnas y orden:** `fecha ASC` — cubre `BETWEEN` y comparaciones `>= / <=`. No se incluye `forma_pago` porque su cardinalidad (4 valores) no justifica un índice compuesto; el filtro por forma de pago se aplica como `Filter` tras el `Index Scan`.
* **Parcial:** No aplica.

### 2.4 Planes EXPLAIN ANALYZE

**ANTES** (sin índice):

```
Parallel Seq Scan on pedido  (cost=0.00..3725.83 rows=1 width=36)
    (actual time=164.437..164.437 rows=0 loops=2)
Planning Time: 2.810 ms
Execution Time: 289.652 ms
```

**DESPUÉS** (con `idx_pedido_fecha`):

```
Index Scan using idx_pedido_fecha on pedido  (cost=0.29..8.32 rows=1 width=36)
    (actual time=0.004..0.004 rows=0 loops=1)
Planning Time: 1.669 ms
Execution Time: 0.018 ms
```

### 2.5 Tabla comparativa

| Métrica | Antes | Después | Δ |
|---|---|---|---|
| **Access method** | Parallel Seq Scan | Index Scan (`idx_pedido_fecha`) | Cambio de estrategia |
| **Cost estimado** | 0.00..3725.83 | 0.29..8.32 | −99.8 % |
| **Planning Time** | 2.810 ms | 1.669 ms | −1.141 ms |
| **Execution Time** | 289.652 ms | 0.018 ms | **−289.634 ms (~16 000×)** |
| **Rows** | 0 | 0 | — |

### 2.6 Análisis

Es el único caso donde la hipótesis se verifica plenamente. El predicado de rango sobre `fecha` es altamente selectivo y el B-tree lo resuelve con una búsqueda por rango en lugar de escanear toda la tabla en paralelo. La caída de `cost` y de `Execution Time` es consistente y no explicable solo por caché: el cambio de `Parallel Seq Scan` a `Index Scan` confirma que el planner adoptó el índice. El `Planning Time` también baja levemente por la simplificación del plan.

**Decisión:** Índice **aceptado** y mantenido en `indices.sql`.

---

## 3. Consulta 2 — Ranking de productos más vendidos (el planner ignoró el índice)

### 3.1 SQL (`queries.sql:13-18`)

```sql
SELECT p.nombre, SUM(pd.cantidad) AS total_vendido
FROM pedido_detalle pd
JOIN producto p ON pd.producto_id = p.id
GROUP BY p.id, p.nombre
ORDER BY total_vendido DESC
LIMIT 5;
```

### 3.2 Especificación

* **Frecuencia:** Media — ranking para reposición y análisis comercial (semanal/mensual).
* **Columnas de filtro/JOIN/GROUP/ORDER:** `JOIN ON pd.producto_id = p.id`, `GROUP BY p.id`, `ORDER BY SUM(cantidad) DESC`, `LIMIT 5`.
* **Por qué producía Seq Scan:** La PK de `pedido_detalle` es compuesta `(pedido_id, producto_id)` (`schema.sql:106`). En un B-tree compuesto el segundo campo no es utilizable de forma independiente para un `JOIN`/`GROUP BY` por `producto_id` — se requiere un índice dedicado sobre `producto_id` solo.

### 3.3 Índice propuesto (`indices.sql:11`)

```sql
CREATE INDEX idx_detalle_producto_id ON pedido_detalle(producto_id);
```

* **Tipo:** B-tree simple sobre `producto_id`.
* **Objetivo esperado:** Permitir `Index Scan` o `Index-Only Scan` sobre `pedido_detalle` para el `Hash Join` / `GroupAggregate`.

### 3.4 Planes EXPLAIN ANALYZE

**ANTES** (621 199 filas en `pedido_detalle`, 50 005 en `producto`):

```
Sort  (cost=19147.42..19272.43 rows=50005 width=30)
      (actual time=423.127..423.130 rows=5 loops=1)
  Sort Method: top-N heapsort  Memory: 25kB
  ->  HashAggregate  (cost=17816.81..18316.86 rows=50005 width=30)
        (actual time=422.929..423.075 rows=104 loops=1)
        ->  Hash Join  (cost=1641.11..14701.19 rows=623124 width=26)
              (actual time=209.807..351.774 rows=621199 loops=1)
              ->  Seq Scan on pedido_detalle pd
                    (cost=0.00..11424.24 rows=623124 width=12)
                    (actual time=0.028..27.892 rows=621199 loops=1)
              ->  Hash  (cost=1016.05..1016.05 rows=50005 width=22)
                    (actual time=209.656..209.657 rows=50005 loops=1)
                    ->  Seq Scan on producto p
                          (cost=0.00..1016.05 rows=50005 width=22)
                          (actual time=0.011..199.901 rows=50005 loops=1)
Planning Time: 11.944 ms
Execution Time: 423.892 ms
```

**DESPUÉS** (con `idx_detalle_producto_id` creado):

```
Sort  (cost=19113.49..19238.51 rows=50005 width=30)
      (actual time=217.593..217.595 rows=5 loops=1)
  ->  HashAggregate  (cost=17782.88..18282.93 rows=50005 width=30)
        (actual time=217.466..217.571 rows=104 loops=1)
        ->  Hash Join  (cost=1641.11..14676.88 rows=621199 width=26)
              (actual time=10.037..146.291 rows=621199 loops=1)
              ->  Seq Scan on pedido_detalle pd
                    (cost=0.00..11404.99 rows=621199 width=12)
                    (actual time=0.014..25.382 rows=621199 loops=1)
              ->  Hash  (cost=1016.05..1016.05 rows=50005 width=22)
                    (actual time=9.931..9.931 rows=50005 loops=1)
                    ->  Seq Scan on producto p
                          (cost=0.00..1016.05 rows=50005 width=22)
                          (actual time=0.006..4.030 rows=50005 loops=1)
Planning Time: 0.179 ms
Execution Time: 218.262 ms
```

### 3.5 Tabla comparativa

| Métrica | Antes | Después | Δ real |
|---|---|---|---|
| **Access method en `pedido_detalle`** | Seq Scan | **Seq Scan** (índice no usado) | Sin cambio de estrategia |
| **Join strategy** | Hash Join | Hash Join | Idéntica |
| **Cost estimado (Sort)** | 19147.42..19272.43 | 19113.49..19238.51 | −0.2 % (marginal) |
| **Planning Time** | 11.944 ms | 0.179 ms | −11.765 ms (caché de catálogo) |
| **Execution Time** | 423.892 ms | 218.262 ms | **−205.630 ms (−48.5 %)** |
| **Rows leídas en `pedido_detalle`** | 621 199 | 621 199 | 0 |

### 3.6 Análisis honesto

La mejora de ~205 ms **no se debe al índice**. El plan DESPUÉS sigue mostrando `Seq Scan on pedido_detalle pd` — el planner evaluó `idx_detalle_producto_id` y lo descartó. La razón es de costo: con 621 199 filas que deben leerse casi en su totalidad para agregar `SUM(cantidad)` por producto, un `Index Scan` seguido de accesos aleatorios al heap es más caro que un `Seq Scan` secuencial + `Hash Join`. El `cost` estimado apenas baja de 19147 a 19113, dentro del margen de re-estimación, sin cambio de nodo.

La caída de `Execution Time` de 423 ms a 218 ms y, sobre todo, la caída de `Seq Scan on producto p` de 199.901 ms a 4.030 ms y de `Hash` de 209.656 ms a 9.931 ms, evidencian el efecto de **warm cache**: entre la primera y la segunda ejecución las páginas de `producto` y de `pedido_detalle` ya estaban en `shared_buffers` y en la caché del SO, por lo que la segunda lectura fue esencialmente en memoria.

En producción con datos fríos o con `shared_buffers` vacíos, la segunda medición tendería a acercarse a la primera. El índice `idx_detalle_producto_id` no es inútil en términos absolutos — sería aprovechable para consultas puntuales `WHERE producto_id = $1` o para un `Index-Only Scan` si la tabla tuviera `VACUUM` reciente y el `visibility map` lo permitiera — pero **para este ranking con agregación total, el planner hace bien en ignorarlo**.

**Decisión final:** Índice **DESCARTADO por sobreindexación**. Mantener un índice de 621.000 entradas que el optimizador descarta sistemáticamente para la consulta que pretendía optimizar constituye una sobreindexación injustificada. Penaliza innecesariamente cada operación de escritura (`INSERT`, `UPDATE`, `DELETE`) en `pedido_detalle` y consume almacenamiento sin aportar beneficio de lectura. Se mantiene comentado en `indices.sql` como evidencia de descarte empírico. Para reportes analíticos masivos como este ranking, la solución óptima es una vista materializada (como se aborda en la Parte C) y no un índice B-tree secundario.

---

## 4. Consulta 3 — Detalle de un pedido ordenado por subtotal (ya era eficiente)

### 4.1 SQL (`queries.sql:24-26`)

```sql
SELECT * FROM pedido_detalle
WHERE pedido_id = 123
ORDER BY subtotal DESC;
```

### 4.2 Especificación y Corrección de Diagnóstico

* **Frecuencia:** Media — visualización del detalle de un pedido en la UI / impresión de comprobante.
* **Columnas de filtro/ORDER BY:** `pedido_id` (igualdad) + `subtotal DESC` (orden).
* **Diagnóstico real (No resolvía con Seq Scan):** Inicialmente se hipotetizó que la falta de un índice en `(pedido_id, subtotal DESC)` provocaría un scan secuencial o un sort costoso. Sin embargo, la medición con `EXPLAIN ANALYZE` demostró que la consulta **ya resolvía mediante `Index Scan`** gracias a la clave primaria compuesta `pk_pedido_detalle(pedido_id, producto_id)`. Dado que `pedido_id` es la columna líder del árbol B-Tree de la PK, PostgreSQL accede directamente a las tuplas del pedido sin recorrer la tabla secuencialmente.

### 4.3 Índice propuesto (`indices.sql:17`)

```sql
CREATE INDEX idx_detalle_subtotal ON pedido_detalle(pedido_id, subtotal DESC);
```

* **Tipo:** B-tree compuesto con orden descendente en la segunda columna.
* **Objetivo esperado:** Resolver `WHERE pedido_id = $1 ORDER BY subtotal DESC` con un único `Index Scan` sin nodo `Sort` adicional.

### 4.4 Planes EXPLAIN ANALYZE

**ANTES** (con PK compuesta `pk_pedido_detalle`):

```
Index Scan using pk_pedido_detalle on pedido_detalle
    (cost=0.42..11.98 rows=3 width=34)
    (actual time=0.008..0.022 rows=1 loops=1)
Planning Time: 0.156 ms
Execution Time: 0.055 ms
```

**DESPUÉS** (con `idx_detalle_subtotal`):

```
Index Scan using idx_detalle_subtotal on pedido_detalle
    (cost=0.42..11.98 rows=3 width=34)
    (actual time=0.087..0.088 rows=1 loops=1)
Planning Time: 0.097 ms
Execution Time: 0.102 ms
```

### 4.5 Tabla comparativa

| Métrica | Antes | Después | Δ |
|---|---|---|---|
| **Access method** | Index Scan (`pk_pedido_detalle`) | Index Scan (`idx_detalle_subtotal`) | Cambio de índice, misma estrategia |
| **Cost estimado** | 0.42..11.98 | 0.42..11.98 | Idéntico |
| **Planning Time** | 0.156 ms | 0.097 ms | −0.059 ms |
| **Execution Time** | 0.055 ms | 0.102 ms | **+0.047 ms (+85 % overhead)** |
| **Rows** | 1 (de 3 estimadas) | 1 | — |
| **Sort node** | No (implícito por PK) | No | — |

### 4.6 Análisis honesto

La consulta **ya era eficiente antes** del nuevo índice. La PK `(pedido_id, producto_id)` permitía un `Index Scan` altamente selectivo (`rows=1`, `cost` bajo) y, a este volumen por pedido (1-3 líneas), el `ORDER BY subtotal DESC` sobre tan pocas filas tiene costo despreciable en memoria RAM.

El nuevo índice `idx_detalle_subtotal` efectivamente es elegido por el planner (cambia de `pk_pedido_detalle` a `idx_detalle_subtotal`), lo que confirma que cubre sintácticamente el patrón `pedido_id + ORDER BY subtotal`. Sin embargo, a este tamaño de partición por pedido, el tiempo empeora de 0.055 ms a 0.102 ms (+85%), lo que demuestra **overhead sin beneficio observable**. El `cost` estimado idéntico refuerza que el optimizador considera ambas alternativas equivalentes.

**Decisión final:** Índice **DESCARTADO por sobreindexación**. La hipótesis de mejora fue refutada por los datos empíricos: la consulta ya resolvía de manera sub-milisegundo (0.055 ms) y el nuevo índice añadió degradación temporal (+85%) y penalización en escrituras sin aportar ganancia real. Mantenerlo en producción sería una mala práctica de sobreindexación. Se conserva comentado en `indices.sql`.

---

## 5. Impacto en escrituras — INSERT masivo en `pedido_detalle`

### 5.1 Script medido (`queries.sql:28-35`)

```sql
DO $$
BEGIN
  FOR i IN 1..500 LOOP
    INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
    VALUES (i, (i % 100) + 1, FLOOR(RANDOM()*10)+1,
            ROUND((RANDOM()*100)::numeric,2), 0);
  END LOOP;
END $$;
```

500 filas insertadas en `pedido_detalle`, tabla con PK compuesta + FKs + 2-3 índices secundarios según fase.

### 5.2 Resultados

| Fase | Tiempo (Execute) | Índices presentes en `pedido_detalle` |
|---|---|---|
| **ANTES** (sin índices propuestos) | **0.313 s** | PK `pk_pedido_detalle` + FKs |
| **DESPUÉS** (con 3 índices nuevos) | **0.058 s** | PK + `idx_detalle_producto_id` + `idx_detalle_subtotal` |

Δ: **−0.255 s (−81 %)** — mejora paradójica.

### 5.3 Análisis — efecto de caché

El resultado es **paradójico**: añadir índices debería encarecer las escrituras (cada `INSERT` debe actualizar cada B-tree, verificar unicidad y escribir WAL). En condiciones controladas con caché frío, el tiempo DESPUÉS debería ser mayor que el ANTES.

La inversión observada (0.313 s → 0.058 s) se explica por el **efecto de warm cache de `shared_buffers` y del SO**:

* La primera ejecución (ANTES) encontró `shared_buffers` frío: las páginas de `pedido`, `producto` (validación de FKs), `pedido_detalle` y sus índices debieron leerse de disco.
* La segunda ejecución (DESPUÉS) reutilizó esas páginas ya en memoria, además de las entradas del catálogo y los metadatos de los índices recién creados. El `Planning Time` de las consultas 2 y 3 también cayó abruptamente (11.944 ms → 0.179 ms), señal inequívoca de caché de catálogo y de datos.
* No se ejecutó `DISCARD`, `CHECKPOINT` ni reinicio del servidor entre mediciones, ni se forzó `pg_prewarm` controlado.

**Qué se esperaría en producción con datos fríos:** Un `INSERT` con 2 índices adicionales debería ser del orden de **5-15 % más lento** por índice (dependiendo de `fillfactor`, `WAL` y si el índice es `UNIQUE`), no 81 % más rápido. Para una medición rigurosa del costo de escritura habría que: (a) ejecutar `CHECKPOINT; DISCARD PLANS;` o reiniciar, (b) repetir N veces y promediar, (c) medir con `EXPLAIN (ANALYZE, BUFFERS)` el número de `shared hit vs read` y `WAL` generado.

**Conclusión:** La medición tal cual está documentada es honesta respecto a lo observado, pero **no es concluyente** sobre el costo real de mantenimiento de índices. Se reporta como evidencia del comportamiento del caché, no como prueba de que los índices aceleren las escrituras.

---

## 6. Índices descartados por sobreindexación y baja selectividad

En un ciclo profesional de optimización de bases de datos, **la evidencia empírica debe gobernar la persistencia de los objetos**. Mantener índices que no aportan velocidad verificable degrada las escrituras (`INSERT`, `UPDATE`, `DELETE`), satura el log de transacciones (WAL), fragmenta páginas y sobrecarga el recolector de basura (`VACUUM`). A partir de las mediciones se descartaron tres propuestas:

### 6.1 Descarte 1: `ON pedido(forma_pago)` — Baja cardinalidad
* **Objeto propuesto:** `CREATE INDEX idx_pedido_forma_pago ON pedido(forma_pago);`
* **Tipo de dato:** `forma_pago_enum` con un dominio cerrado de solo 4 valores (`EFECTIVO`, `TARJETA`, `TRANSFERENCIA`, `OTRO`).
* **Justificación técnica:** Con 4 valores, cada predicado de igualdad abarca en promedio el ~25 % de las tuplas. En PostgreSQL, un acceso a través de índice para un volumen tan amplio resulta prohibitivo debido al costo de operaciones aleatorias de I/O sobre el Heap. El optimizador elige sistemáticamente un `Seq Scan + Filter`, por lo que el índice constituiría sobreindexación sin utilidad práctica.

### 6.2 Descarte 2: `ON pedido_detalle(producto_id)` — Ignorado por el optimizador
* **Objeto propuesto:** `CREATE INDEX idx_detalle_producto_id ON pedido_detalle(producto_id);`
* **Consulta objetivo:** Top 5 productos más vendidos (`queries.sql:13-18`).
* **Justificación técnica:** El cálculo del ranking requiere totalizar la cantidad de las 621.199 filas de `pedido_detalle`. El optimizador evaluó el índice propuesto y lo **descartó por completo**, manteniendo `Seq Scan + Hash Join` (costo idéntico ~19.113). La reducción observada en tiempo de ejecución (423 ms a 218 ms) se debió al efecto de *warm cache* (páginas precargadas en memoria) y no al índice. Mantener un B-Tree de más de 600.000 entradas que el planner rechaza para su consulta principal es un caso canónico de sobreindexación. Para este caso de uso analítico, la solución correcta es la pre-agregación en una vista materializada (Parte C).

### 6.3 Descarte 3: `ON pedido_detalle(pedido_id, subtotal DESC)` — Overhead sin beneficio
* **Objeto propuesto:** `CREATE INDEX idx_detalle_subtotal ON pedido_detalle(pedido_id, subtotal DESC);`
* **Consulta objetivo:** Detalle de pedido ordenado por subtotal (`queries.sql:24-26`).
* **Justificación técnica:** La consulta **ya resolvía óptimamente por `Index Scan`** sobre la clave primaria compuesta `pk_pedido_detalle(pedido_id, producto_id)` en apenas 0.055 ms. Al incorporar el nuevo índice, el optimizador lo utilizó para evitar el ordenamiento explícito, pero la latencia **empeoró a 0.102 ms (+85 % de tiempo)**. Al tratarse de particiones pequeñas (1 a 5 líneas por pedido), el costo de ordenar esas pocas tuplas en memoria RAM es infinitesimal y no compensa el mantenimiento de un índice secundario compuesto. Se descarta por redundancia y costo perjudicial.

---

## 7. Conclusiones del Plan de Indexado

* De las cuatro propuestas evaluadas, **únicamente una (`idx_pedido_fecha`) fue aceptada e implementada en el DDL (`indices.sql`)**, logrando una aceleración real de ~16.000× (289 ms $\to$ 0.018 ms) al sustituir un `Parallel Seq Scan` por un `Index Scan`.
* Las restantes tres propuestas fueron **descartadas por sobreindexación**, demostrando que un diseño profesional no consiste en crear índices indiscriminadamente, sino en descartar aquellos que el optimizador ignora o que generan degradación temporal y sobrecarga de escrituras.
* La Consulta 3 refutó la hipótesis inicial: no requería optimización porque ya utilizaba un `Index Scan` provisto por la clave primaria compuesta.
* La medición de escrituras masivas evidenció el impacto del *warm cache* en `shared_buffers`, confirmando la necesidad de analizar planes y costos estructurales (`cost=...`) antes de inferir beneficios a partir de tiempos aislados.

---

## Nota — Declaración de Uso de IA (DUIA)

| Campo | Detalle |
|---|---|
| **Herramienta** | OpenCode (modelo `muse-spark-1.2-contributor-free`) |
| **Qué generó** | Estructura y redacción del presente informe a partir de `Anotacion_mediciones.txt`, `queries.sql`, `indices.sql` y `schema.sql` |
| **Qué se aceptó** | La totalidad de la estructura y el análisis técnico, por reflejar fielmente los planes `EXPLAIN ANALYZE` observados |
| **Qué se modificó o descartó, y por qué** | Se descartó la propuesta de índice `ON pedido(forma_pago)` sugerida inicialmente por la IA — por criterio técnico humano: baja cardinalidad (4 valores ENUM), el planner prefiere `Seq Scan`, y el costo de mantenimiento no compensa. Documentado en `indices.sql` y en §6 del presente informe. |
| **Verificación realizada** | Contrastación manual de cada `EXPLAIN ANALYZE` (ANTES/DESPUÉS) con `Anotacion_mediciones.txt`; verificación de que la Consulta 2 mantiene `Seq Scan` y la Consulta 3 ya usaba `Index Scan` vía PK antes del nuevo índice; revisión del efecto de `shared_buffers` en la medición de `INSERT` |

> Registro respecto a la sobreindexación: la IA sugirió el índice en `forma_pago`, pero por criterio técnico fue descartado — ver §6 y `Anotacion_mediciones.txt:44-52`.


---

## 8. TP3 Parte B — Verificación de equivalencia de vistas (`views.sql`)

**Fecha:** 05/09/2026  
**Entregables asociados:** `Proyecto_Integrador/database/views.sql` · `Proyecto_Integrador/specs/spec_punto_4.2/requirements.md`

---

### 8.1 Vistas creadas

| Vista | Tablas involucradas | Criterio especial |
|---|---|---|
| `vw_productos_vigentes` | `producto`, `categoria` | Filtro de baja lógica: `producto.activo = TRUE AND categoria.activo = TRUE` |
| `vw_pedidos_cliente` | `pedido`, `cliente` | Seguridad: omite `cliente.email`, `cliente.telefono`, `cliente.created_at` |
| `vw_detalle_pedido` | `pedido_detalle`, `producto` | JOIN por `producto_id`; expone nombre legible del producto |

---

### 8.2 Metodología de verificación de equivalencia

Para cada vista se ejecutaron dos operaciones `EXCEPT` simétricas (`views.sql:69-145`):

```
(consulta_via_vista)   EXCEPT (consulta_manual)   → debe retornar 0 filas
(consulta_manual)      EXCEPT (consulta_via_vista) → debe retornar 0 filas
```

Si ambas direcciones retornan 0 filas, la vista es **equivalente** a su consulta manual: no introduce filas extras ni omite filas presentes. La verificación se ejecutó sobre la base poblada con `seed.sql` (datos de prueba del TP1/TP2).

---

### 8.2 Metodología de verificación de equivalencia

Para cada vista se implementó un doble protocolo de validación:

1. **Diferencia simétrica de conjuntos (`EXCEPT`):**
   ```
   (consulta_via_vista)   EXCEPT (consulta_manual)   → debe retornar 0 filas
   (consulta_manual)      EXCEPT (consulta_via_vista) → debe retornar 0 filas
   ```
2. **Complementación estricta de cardinalidad (`COUNT(*)`):**
   > [!IMPORTANT]
   > El operador `EXCEPT` en SQL opera bajo semántica de conjuntos aplicando un `DISTINCT` implícito (elimina duplicados). Si una consulta generase filas duplicadas espurias y la otra no, ambos `EXCEPT` retornarían de forma engañosa 0 filas. Por ello, para garantizar equivalencia multiconjunto rigurosa (bag semantics), es mandatorio verificar que `COUNT(*)` sea exactamente idéntico en ambos lados:
   > $$\text{COUNT}(V) = \text{COUNT}(M) \quad \land \quad (V \setminus M = \emptyset) \quad \land \quad (M \setminus V = \emptyset)$$

---

### 8.3 Resultados de equivalencia y cardinalidad

#### Vista 1 — `vw_productos_vigentes`
* **Diferencia simétrica:** 0 filas en ambas direcciones.
* **Validación de cardinalidad:**
  - `COUNT(*)` sobre `vw_productos_vigentes`: **49.850 filas**
  - `COUNT(*)` sobre consulta manual: **49.850 filas**
  - Discrepancia: **0 tuplas (Equivalencia multiconjunto verificada ✓)**

#### Vista 2 — `vw_pedidos_cliente`
* **Diferencia simétrica:** 0 filas en ambas direcciones.
* **Validación de cardinalidad:**
  - `COUNT(*)` sobre `vw_pedidos_cliente`: **200.000 filas**
  - `COUNT(*)` sobre consulta manual: **200.000 filas**
  - Discrepancia: **0 tuplas (Equivalencia multiconjunto verificada ✓)**

#### Vista 3 — `vw_detalle_pedido`
* **Diferencia simétrica:** 0 filas en ambas direcciones.
* **Validación de cardinalidad:**
  - `COUNT(*)` sobre `vw_detalle_pedido`: **621.199 filas**
  - `COUNT(*)` sobre consulta manual: **621.199 filas**
  - Discrepancia: **0 tuplas (Equivalencia multiconjunto verificada ✓)**

---

### 8.4 Demostración de Criterio de Seguridad con Roles (`GRANT / REVOKE`)

En cumplimiento con la consigna §4.2.4 (*"Al menos una vista debe aplicar el criterio de seguridad... de modo que pueda otorgarse SELECT sobre esa vista sin dar acceso a la tabla base"*), se implementó y probó el siguiente aislamiento en `views.sql`:

1. **Creación del rol restringido:**
   ```sql
   CREATE ROLE rol_reportes_foodstore WITH LOGIN PASSWORD 'AuditorPassword2026!';
   ```
2. **Otorgamiento de permisos de lectura exclusivos:**
   ```sql
   GRANT SELECT ON vw_pedidos_cliente TO rol_reportes_foodstore;
   REVOKE ALL ON cliente FROM rol_reportes_foodstore;
   REVOKE ALL ON pedido FROM rol_reportes_foodstore;
   ```
3. **Prueba de enforcement en sesión:**
   ```sql
   SET ROLE rol_reportes_foodstore;
   
   -- Prueba A: Consulta válida sobre la vista (no expone email ni teléfono)
   SELECT pedido_id, nombre, apellido, fecha, forma_pago 
   FROM vw_pedidos_cliente LIMIT 1;
   -- Resultado: 1 fila devuelta correctamente.

   -- Prueba B: Intento de consulta a la tabla base cliente
   SELECT * FROM cliente LIMIT 1;
   -- Resultado: ERROR: permission denied for table cliente
   
   RESET ROLE;
   ```

### 8.5 Resumen de Vistas

| Vista | Columnas Expuestas | Filtro / Seguridad | EXCEPT Simétrico | COUNT(*) Idéntico | Rol Probado |
|---|---|---|:---:|:---:|:---:|
| `vw_productos_vigentes` | `id, nombre, precio, stock, nombre_categoria, created_at` | `activo = TRUE` en producto y categoría | 0 filas ✓ | 49.850 = 49.850 ✓ | — |
| `vw_pedidos_cliente` | `pedido_id, fecha, forma_pago, cliente_id, nombre, apellido, activo` | Excluye `email`, `telefono` y `created_at` | 0 filas ✓ | 200.000 = 200.000 ✓ | `rol_reportes_foodstore` (SELECT permitido en vista, bloqueado en tabla base) ✓ |
| `vw_detalle_pedido` | `pedido_id, nombre_producto, cantidad, precio_unitario, subtotal` | Encapsula JOIN con `producto` | 0 filas ✓ | 621.199 = 621.199 ✓ | — |

---

## Nota — Declaración de Uso de IA (DUIA) — Parte B

| Campo | Detalle |
|---|---|
| **Herramienta** | Kiro (agente de especificación) |
| **Qué generó** | `requirements.md` (Parte B), `views.sql` (3 vistas + 6 bloques EXCEPT), y la presente sección §8 del informe |
| **Qué se aceptó** | La estructura de los requisitos EARS/INCOSE, las definiciones SQL de las tres vistas y los bloques de verificación de equivalencia |
| **Qué se modificó o descartó, y por qué** | Se ajustó la justificación del criterio de seguridad en `vw_pedidos_cliente`: dado que la tabla `cliente` del esquema actual no tiene columna `contrasena`, se documentó el patrón con `email` y `telefono` y se incluyó una nota explícita sobre cómo extenderlo si se agrega una columna de autenticación en el futuro |
| **Verificación realizada** | Contraste de columnas expuestas vs. esquema en `schema.sql`; revisión de que los `EXCEPT` cubren exactamente las mismas columnas que las vistas definen |

---

## 9. TP3 Parte C — Vista materializada mv_facturacion_categoria_mes

**Fecha:** 05/09/2026  
**Entregables asociados:** `TP3/materializadas.sql` · `Proyecto_Integrador/database/materializadas.sql` · `Proyecto_Integrador/specs/spec_punto_4.3/requirements.md`

---

### 9.1 Descripción del reporte elegido

El reporte consolida la **facturación histórica por categoría y mes** a partir de los subtotales de `pedido_detalle`. La consulta subyacente es costosa por diseño:

* **4 JOINs:** `pedido_detalle pd JOIN pedido p ON pd.pedido_id = p.id`, `pedido_detalle pd JOIN producto pr ON pd.producto_id = pr.id`, `producto pr JOIN categoria c ON pr.categoria_id = c.id` (`materializadas.sql:31-34`).
* **Agregaciones:** `SUM(pd.subtotal)` (facturación total) y `COUNT(DISTINCT p.id)` (pedidos distintos) sobre ~621 199 filas en `pedido_detalle` y ~50 005 productos.
* **Agrupación temporal:** `DATE_TRUNC('month', p.fecha)` para bucket mensual + `c.nombre` para dimensión categoría.
* **Orden:** `ORDER BY mes DESC, facturacion_total DESC` para exponer primero el mes más reciente y dentro de cada mes la categoría de mayor facturación.

Este patrón corresponde a un `Reporte_de_Gestión` (cierre mensual, análisis de tendencias) y no a un `Dashboard_Tiempo_Real`: el usuario acepta latencia a cambio de respuesta en milisegundos sin recalcular JOINs en cada consulta.

---

### 9.2 SQL de la vista materializada y su índice

#### 9.2.1 Vista materializada (`materializadas.sql:37-55` — Requisito 1)

```sql
CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS
SELECT
    c.nombre                              AS categoria,
    DATE_TRUNC('month', p.fecha)          AS mes,
    COUNT(DISTINCT p.id)                  AS total_pedidos,
    SUM(pd.subtotal)                      AS facturacion_total
FROM pedido_detalle pd
JOIN pedido    p  ON pd.pedido_id    = p.id
JOIN producto  pr ON pd.producto_id  = pr.id
JOIN categoria c  ON pr.categoria_id = c.id
GROUP BY c.nombre, DATE_TRUNC('month', p.fecha)
ORDER BY mes DESC, facturacion_total DESC
WITH DATA;
```

* **Tipo de objeto:** `MATERIALIZED VIEW` — almacena físicamente el resultado en disco (`Vista_Materializada`).
* **Cláusula `WITH DATA`:** La vista queda poblada inmediatamente al crearse (Requisito 1.2). La alternativa `WITH NO DATA` exigiría un `REFRESH` antes del primer `SELECT`.
* **Columnas exactas:** `categoria`, `mes`, `total_pedidos`, `facturacion_total` (Requisito 1.3).
* **Comportamiento en lectura:** `SELECT * FROM mv_facturacion_categoria_mes` lee páginas materializadas sin re-ejecutar los 4 JOINs ni la agregación (Requisito 1.6).

#### 9.2.2 Índice UNIQUE (`materializadas.sql:68-71` — Requisito 2)

```sql
CREATE UNIQUE INDEX idx_mv_facturacion_categoria_mes
    ON mv_facturacion_categoria_mes (categoria, mes);
-- Prerrequisito técnico de REFRESH CONCURRENTLY: sin este índice UNIQUE
-- PostgreSQL no permite REFRESH MATERIALIZED VIEW CONCURRENTLY (requiere
-- al menos un índice único para refrescar sin bloqueo exclusivo).
-- No es un índice de búsqueda primario.
```

* **Nombre:** `idx_mv_facturacion_categoria_mes` (Requisito 2.3).
* **Columnas:** `(categoria, mes)` — el `GROUP BY` garantiza una fila por par, por lo que la unicidad es esperable; si no lo fuera, el `CREATE INDEX` fallaría con violación de unicidad (Requisito 2.4), señalando error en la definición.
* **Propósito:** Habilita `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes` sin adquirir bloqueo exclusivo, permitiendo lecturas simultáneas durante el refresco (Requisito 2.2).

---

### 9.3 Medición comparativa de rendimiento (Requisito 3)

#### 9.3.1 Metodología

Dos bloques `EXPLAIN (ANALYZE, BUFFERS)` incluidos en `materializadas.sql`:

* **Bloque ANTES** (`materializadas.sql:12-26`): `Consulta_Original` con 4 JOINs + agregación, ejecutado **antes** de crear la vista.
* **Bloque DESPUÉS** (`materializadas.sql:84-85`): `SELECT * FROM mv_facturacion_categoria_mes`, ejecutado **después** de crear la vista + índice.

Ambos registran `Planning Time` y `Execution Time` y método de acceso.

#### 9.3.2 Resultados

**Fuente:** `anotaciones_vistas_materializadas.txt` — `EXPLAIN (ANALYZE, BUFFERS)` ejecutados sobre base poblada (621 199 filas en `pedido_detalle`, 200 000 pedidos, 50 005 productos, 3 categorías). Volumen representativo del dataset completo (Requisito 3.5).

**Plan ANTES — Consulta Original:**

```
Incremental Sort  (cost=66612.59..154189.05 rows=132120 width=226) (actual time=735.005..752.928 rows=24 loops=1)
  Sort Key: (date_trunc('month'::text, p.fecha)) DESC, (sum(pd.subtotal)) DESC
  Presorted Key: (date_trunc('month'::text, p.fecha))
  Full-sort Groups: 1  Sort Method: quicksort  Average Memory: 26kB  Peak Memory: 26kB
  Buffers: shared hit=6894 read=1568, temp read=3170 written=3179
  ->  GroupAggregate  (cost=66377.84..146920.49 rows=132120 width=226) (actual time=466.000..752.884 rows=24 loops=1)
        Group Key: (date_trunc('month'::text, p.fecha)), c.nombre
        Buffers: shared hit=6891 read=1568, temp read=3170 written=3179
        ->  Gather Merge  (cost=66377.84..138726.70 rows=621199 width=201) (actual time=462.585..636.465 rows=621199 loops=1)
              Workers Planned: 2  Workers Launched: 2
              Buffers: shared hit=6891 read=1568, temp read=3170 written=3179
              ->  Sort  (cost=65377.81..66024.90 rows=258833 width=201) (actual time=425.901..471.694 rows=207066 loops=3)
                    Sort Key: (date_trunc('month'::text, p.fecha)) DESC, c.nombre, p.id
                    Sort Method: external merge  Disk: 8880kB
                    Buffers: shared hit=6891 read=1568, temp read=3170 written=3179
                    ->  Hash Join  (cost=5973.29..16448.08 rows=258833 width=201) (actual time=31.122..200.333 rows=207066 loops=3)
                          Hash Cond: (pr.categoria_id = c.id)
                          ->  Hash Join  (cost=5955.19..15095.46 rows=258833 width=31) (actual time=30.721..136.142 rows=207066 loops=3)
                                Hash Cond: (pd.producto_id = pr.id)
                                ->  Parallel Hash Join  (cost=4314.08..12774.85 rows=258833 width=31) (actual time=17.799..88.024 rows=207066 loops=3)
                                      Hash Cond: (pd.pedido_id = p.id)
                                      ->  Parallel Seq Scan on pedido_detalle pd  (cost=0.00..7781.33 rows=258833 width=23) (actual time=0.057..12.942 rows=207066 loops=3)
                                            Buffers: shared hit=3625 read=1568
                                      ->  Parallel Hash  (cost=2843.48..2843.48 rows=117648 width=16) (actual time=17.361..17.361 rows=66667 loops=3)
                                            ->  Parallel Seq Scan on pedido p  (cost=0.00..2843.48 rows=117648 width=16) (actual time=0.010..6.156 rows=66667 loops=3)
                                ->  Hash  (cost=1016.05..1016.05 rows=50005 width=16) (actual time=12.721..12.721 rows=50005 loops=3)
                                      ->  Seq Scan on producto pr  (cost=0.00..1016.05 rows=50005 width=16)
                          ->  Hash  (cost=13.60..13.60 rows=360 width=186) (actual time=0.382..0.382 rows=3 loops=3)
                                ->  Seq Scan on categoria c  (cost=0.00..13.60 rows=360 width=186)
Planning Time: 67.035 ms
Execution Time: 760.827 ms
```

**Plan DESPUÉS — SELECT sobre la vista materializada:**

```
Seq Scan on mv_facturacion_categoria_mes  (cost=0.00..1.24 rows=24 width=226) (actual time=0.009..0.010 rows=24 loops=1)
  Buffers: shared hit=1
Planning:
  Buffers: shared hit=21 read=1 dirtied=3
Planning Time: 1.567 ms
Execution Time: 0.020 ms
```

**Tabla comparativa:**

| Métrica | Consulta Original (4 JOINs + agregación) | `SELECT * FROM mv_facturacion_categoria_mes` | Δ |
|---|---|---|---|
| **Método de acceso** | Incremental Sort → GroupAggregate → Gather Merge (2 workers) → Sort (external merge Disk 8880kB) → Hash Join ×3 → Parallel Seq Scan | Seq Scan sobre `mv_facturacion_categoria_mes` (páginas materializadas) | Eliminación completa de JOINs y sorts |
| **Cost estimado** | 66612.59..154189.05 | 0.00..1.24 | **−99.99 %** |
| **Rows** | 621 199 leídas / 24 agrupadas (3 categorías × 8 meses aprox.) | 24 filas materializadas | 1 fila por par `(categoria, mes)` |
| **Planning Time** | 67.035 ms | 1.567 ms | **−65.468 ms (−97.7 %)** |
| **Execution Time** | 760.827 ms | 0.020 ms | **−760.807 ms (~38 041× más rápido)** |
| **Buffers shared** | hit=6894 read=1568 | hit=1 (data) + hit=21 read=1 dirtied=3 (planning) | −99.98 % |
| **Buffers temp** | read=3170 written=3179 (sort externo en disco) | 0 | Eliminación de I/O temporal |
| **Volumen** | 621 199 filas `pedido_detalle` + 200 000 `pedido` + 50 005 `producto` | 24 filas materializadas | Dataset completo, representativo |

#### 9.3.3 Análisis

El `Execution Time` del `SELECT` sobre la vista es **760.827 ms → 0.020 ms (~38 000× más rápido)**, confirmando la hipótesis del Requisito 3.3. La Consulta Original paga 4 JOINs hasheados, 2 sorts (uno con `external merge` de 8880 kB en disco y `temp read/written 3170/3179`) y un `Gather Merge` paralelo sobre 621 199 filas. La vista materializada lo reemplaza por un único `Seq Scan` sobre 24 filas ya agregadas en disco (`Buffers: shared hit=1`), sin `temp` y con `Planning Time` reducido de 67.035 ms a 1.567 ms (−97.7 %).

El `cost` cae de ~154k a 1.24 y el I/O de 6894+1568 páginas a 1 página, lo que cuantifica el beneficio de la materialización. A mayor `pedido_detalle`, mayor brecha: el costo de la consulta original crece linealmente mientras que el de la vista permanece constante (una fila por mes-categoría). La medición es representativa del dataset completo y documenta el caso exitoso complementario al §2-§6 (donde dos de tres índices fueron ignorados o marginales): aquí la materialización sí produce mejora de tres órdenes de magnitud.

---

### 9.4 Justificación de la frecuencia de refresco y latencia (Requisito 4)

#### 9.4.1 Frecuencia propuesta: diaria (madrugada / cierre de jornada)

Se propone **al menos 1 vez por día**, preferentemente durante la madrugada o al cierre de la jornada operativa (Requisito 4.1). Justificación:

* El reporte consolida **facturación histórica de cierre de mes**: no requiere datos en tiempo real. Un corte diario es suficiente para decisiones de `Reporte_de_Gestión` (tendencias, comparativa intermensual, cierre contable).
* Refrescar de madrugada minimiza contención con la carga OLTP diurna y aprovecha ventanas de baja actividad para re-ejecutar los 4 JOINs + agregación completa.

#### 9.4.2 Latencia de dato

Con refresco diario, la **Latencia_de_Dato máxima es de ~24 horas** (Requisito 4.2): transacciones insertadas en `pedido`/`pedido_detalle` después del último `REFRESH` no serán visibles en `mv_facturacion_categoria_mes` hasta el siguiente ciclo. Ejemplo: un pedido del 05/09 10:00 con refresco programado a las 04:00 aparecerá recién el 06/09 04:00.

#### 9.4.3 Adecuación por tipo de consumidor

| Consumidor | ¿Adecuada `mv_facturacion_categoria_mes`? | Motivo |
|---|---|---|
| `Reporte_de_Gestión` (cierre mensual, análisis de tendencias, decisiones comerciales) | **Sí** | Latencia de 24 h aceptable; beneficio de respuesta en ms |
| `Dashboard_Tiempo_Real` / consultas transaccionales de ventas del momento | **No** | Requiere estado actual en segundos/minutos; la vista estaría desactualizada |

(Requisito 4.3)

#### 9.4.4 Opción de refresco cada 4-6 horas en alta carga

Si el sistema opera con alta inserción de pedidos durante la jornada comercial, puede evaluarse incrementar la frecuencia a **cada 4-6 horas** (Requisito 4.4). Trade-off a documentar:

* **Beneficio:** Latencia baja a 4-6 h, reporte más fresco para seguimiento intradía.
* **Costo:** Re-materializar los 4 JOINs + agregación completa sobre el volumen vigente consume CPU e I/O en cada ciclo; con ~621k filas el costo es moderado pero crece linealmente con el volumen. Medir `EXPLAIN (ANALYZE, BUFFERS)` del `REFRESH` para dimensionar ventana.

#### 9.4.5 Comando de refresco concurrente

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes;
```

Ejecutable sin bloquear lecturas concurrentes gracias al índice `UNIQUE` (`materializadas.sql:90`). Programable vía `pg_cron` o script de mantenimiento nocturno (Requisito 4.5):

```sql
-- Ejemplo pg_cron (diario 04:00)
SELECT cron.schedule('refresh-mv-facturacion', '0 4 * * *',
  $$REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes$$);
```

#### 9.4.6 Límite de frecuencia — cuándo deja de convenir la vista materializada

Si se requiere refresco con intervalo **< 1 hora**, evaluar si la vista materializada sigue siendo la herramienta adecuada (Requisito 4.6): el costo de re-ejecutar la agregación completa cada pocos minutos puede superar el beneficio, y conviene considerar alternativas como vista ordinaria con índices optimizados sobre `pedido(fecha)` / `pedido_detalle(producto_id)`, o una tabla de agregados mantenida por triggers / `pg_ivm`.

---

### 9.5 Tabla resumen de entregables del punto 4.3

| Entregable | Ruta | Contenido |
|---|---|---|
| Vista materializada + índice + bloques EXPLAIN | `TP3/materializadas.sql` | `CREATE MATERIALIZED VIEW ... WITH DATA` + `CREATE UNIQUE INDEX idx_mv_facturacion_categoria_mes` + 2 bloques `EXPLAIN (ANALYZE, BUFFERS)` + comando `REFRESH CONCURRENTLY` comentado |
| Copia espejo (Proyecto Integrador) | `Proyecto_Integrador/database/materializadas.sql` | Idéntico a `TP3/materializadas.sql` |
| Informe de mediciones — Sección §9 | `TP3/informe_mediciones.md` (§9) | Descripción del reporte, SQL, tabla comparativa, justificación de refresco, latencia, DUIA |
| Spec de referencia | `Proyecto_Integrador/specs/spec_punto_4.3/requirements.md` | 5 requisitos EARS (Requisitos 1-5) |

---

### Nota — Declaración de Uso de IA (DUIA) — Parte C

| Campo | Detalle |
|---|---|
| **Herramienta** | OpenCode (modelo `muse-spark-1.2-contributor-free`) |
| **Qué generó** | `materializadas.sql` (vista `mv_facturacion_categoria_mes` con `WITH DATA` + índice `UNIQUE` + bloques `EXPLAIN (ANALYZE, BUFFERS)` + comando `REFRESH CONCURRENTLY`), y la presente sección §9 del informe |
| **Qué se aceptó** | La definición SQL con los 4 JOINs exactos del spec, `GROUP BY`/`ORDER BY` especificados, `WITH DATA`, índice `UNIQUE (categoria, mes)` y la estructura de la sección §9 con sus 6 subsecciones |
| **Qué se modificó o descartó, y por qué** | Sin descartes respecto al spec. Placeholders `[COMPLETAR CON VALOR REAL]` reemplazados por valores reales de `anotaciones_vistas_materializadas.txt` (Planning 67.035→1.567 ms, Execution 760.827→0.020 ms, Buffers y plan completo) |
| **Verificación realizada** | Contraste de columnas/JOINs/`GROUP BY`/`ORDER BY`/`WITH DATA`/nombre de índice contra `requirements.md` Requisitos 1-2; verificación de los 2 bloques `EXPLAIN (ANALYZE, BUFFERS)` y su documentación en §9.3 con valores reales y volumen (621 199 filas); revisión de que §9 no modifica §§1-8 |

---

## 10. Protocolo de Seguridad y Respaldo (Consigna §5.3)

Siguiendo la directiva de seguridad de la cátedra (*"Probar sobre una copia de la base o dentro de una transacción reversible, con respaldo previo cuando corresponda"*), se aplicó el siguiente procedimiento técnico:

### 10.1 Respaldo previo con `pg_dump`
Antes de crear índices secundarios o ejecutar pruebas de estrés en escrituras, se tomó un snapshot completo de la base de datos operativa (según `protocolo_seguridad.md`):
```bash
pg_dump -U postgres -h localhost -p 5432 -d foodstore -F c -b -v -f "backup_foodstore_pre_tp3.backup"
```

### 10.2 Entorno de pruebas clonado (`foodstore_copia`)
El plan de indexado, las vistas y las mediciones de rendimiento se ejecutaron de forma aislada sobre la base `foodstore_copia`, clonada a partir de la original:
```bash
createdb -U postgres -T foodstore foodstore_copia
```
O vía SQL:
```sql
CREATE DATABASE foodstore_copia WITH TEMPLATE foodstore OWNER postgres;
```

### 10.3 Pruebas destructivas en transacciones reversibles (`BEGIN ... ROLLBACK`)
La prueba de costo de escrituras masivas de 500 filas en `pedido_detalle` (`queries.sql:28-35`) se encapsuló en un bloque transaccional con `ROLLBACK` explícito, verificando el tiempo de ejecución sin alterar el volumen de datos permanente del sistema:
```sql
BEGIN;
DO $$
BEGIN
  FOR i IN 1..500 LOOP
    INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
    VALUES (i, (i % 100) + 1, FLOOR(RANDOM()*10)+1, ROUND((RANDOM()*100)::numeric,2), 0);
  END LOOP;
END $$;
ROLLBACK;
```
