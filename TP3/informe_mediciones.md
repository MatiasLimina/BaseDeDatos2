# TP3 Parte A — Informe de Mediciones del Plan de Indexado

**Proyecto:** Food Store — Sistema de gestión de pedidos  
**Materia:** Base de Datos 2  
**Motor:** PostgreSQL 16  
**Fecha:** 05/09/2026  
**Entregables asociados:** `queries.sql` + `indices.sql`  
**Fuente de datos:** `Anotacion_mediciones.txt` (mediciones con `EXPLAIN ANALYZE` y `INSERT` masivo ejecutadas sobre la base poblada)

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
| 1 | Historial por fecha + forma_pago | Parallel Seq Scan — 289.652 ms | Index Scan `idx_pedido_fecha` — 0.018 ms | **Sí** | Mejora clara, caso exitoso |
| 2 | Ranking Top 5 productos más vendidos | Seq Scan + Hash Join — 423.892 ms | Seq Scan + Hash Join — 218.262 ms | **No** | Planner ignoró `idx_detalle_producto_id`; mejora atribuible a caché |
| 3 | Detalle de pedido ORDER BY subtotal | Index Scan PK — 0.055 ms | Index Scan `idx_detalle_subtotal` — 0.102 ms | Sí (cambio de índice) | Ya era eficiente; nuevo índice no mejoró tiempo |
| — | INSERT 500 filas en `pedido_detalle` | 0.313 s | 0.058 s | — | Resultado paradójico por warm cache |

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

**Decisión:** Índice **mantenido** en `indices.sql` por su utilidad para otros patrones (búsquedas puntuales por producto), pero documentado como **no efectivo para esta consulta específica**. Un índice que sí podría ayudar a este ranking sería un índice covering o una vista materializada pre-agregada, fuera del alcance de esta entrega.

---

## 4. Consulta 3 — Detalle de un pedido ordenado por subtotal (ya era eficiente)

### 4.1 SQL (`queries.sql:24-26`)

```sql
SELECT * FROM pedido_detalle
WHERE pedido_id = 123
ORDER BY subtotal DESC;
```

### 4.2 Especificación

* **Frecuencia:** Media — visualización del detalle de un pedido en la UI / impresión de comprobante.
* **Columnas de filtro/ORDER BY:** `pedido_id` (igualdad) + `subtotal DESC` (orden).
* **Por qué parecía necesitar índice:** El `ORDER BY subtotal DESC` requeriría un `Sort` si solo existiera la PK `(pedido_id, producto_id)`. La PK cubre el filtro por `pedido_id` pero no el orden por `subtotal`.

### 4.3 Índice propuesto (`indices.sql:17`)

```sql
CREATE INDEX idx_detalle_subtotal ON pedido_detalle(pedido_id, subtotal DESC);
```

* **Tipo:** B-tree compuesto con orden descendente en la segunda columna.
* **Objetivo:** Resolver `WHERE pedido_id = $1 ORDER BY subtotal DESC` con un único `Index Scan` sin nodo `Sort` adicional.

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
| **Execution Time** | 0.055 ms | 0.102 ms | **+0.047 ms (+85 %)** |
| **Rows** | 1 (de 3 estimadas) | 1 | — |
| **Sort node** | No (implícito por PK) | No | — |

### 4.6 Análisis honesto

La consulta **ya era eficiente antes** del nuevo índice. La PK `(pedido_id, producto_id)` permitía un `Index Scan` altamente selectivo (`rows=1`, `cost` bajo) y, a este volumen por pedido (1-3 líneas), el `ORDER BY subtotal DESC` sobre tan pocas filas tiene costo despreciable aunque requiriera un sort en memoria.

El nuevo índice `idx_detalle_subtotal` efectivamente es elegido por el planner (cambia de `pk_pedido_detalle` a `idx_detalle_subtotal`), lo que confirma que cubre el patrón `pedido_id + ORDER BY subtotal`. Sin embargo, a este tamaño de partición por pedido, el tiempo empeora levemente de 0.055 ms a 0.102 ms — diferencia dentro del ruido de medición pero que indica **overhead sin beneficio observable**. El `cost` estimado idéntico refuerza que el optimizador considera ambas alternativas equivalentes.

El beneficio de `idx_detalle_subtotal` se manifestaría con pedidos de muchas líneas (decenas/cientos) donde evitar el `Sort` sí ahorraría tiempo, o si la consulta se ampliara a rangos de `subtotal`. A la escala actual, es un índice de **utilidad marginal pero correcto desde el punto de vista del diseño**.

**Decisión:** Índice **mantenido** en `indices.sql` por corrección del patrón de acceso; documentado como sin mejora medible a este volumen.

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

## 6. Índice descartado por sobreindexación

### 6.1 Propuesta descartada (`indices.sql:19-25`)

```sql
-- Índice descartado: ON pedido(forma_pago)
-- Justificación: ver §6.2
-- CREATE INDEX idx_pedido_forma_pago ON pedido(forma_pago);
```

Columna `pedido.forma_pago` de tipo `forma_pago_enum` con dominio cerrado de **4 valores** (`EFECTIVO`, `TARJETA`, `TRANSFERENCIA`, `OTRO`) — ver `schema.sql:20-25`.

### 6.2 Justificación técnica

1. **Baja cardinalidad / baja selectividad.** Con solo 4 valores posibles, cualquier predicado `WHERE forma_pago = 'X'` selecciona en promedio ~25 % de la tabla (asumiendo distribución uniforme). Un B-tree sobre una columna de tan baja selectividad no reduce el costo de acceso: el planner estima que un `Seq Scan + Filter` es más barato que un `Index Scan` seguido de accesos aleatorios al heap para recuperar el 25 % de las filas.

2. **PostgreSQL preferirá Seq Scan.** En las pruebas de la Consulta 1, el planner solo adoptó el índice cuando el predicado incluía `fecha` (rango selectivo). Un índice aislado en `forma_pago` sería ignorado en consultas generales y solo aportaría overhead de mantenimiento.

3. **Costo de mantenimiento sin beneficio.** Cada `INSERT`/`UPDATE` en `pedido` pagaría el costo de mantener un B-tree adicional (escritura WAL, posible page split) sin que ninguna consulta frecuente lo aproveche de forma diferencial.

4. **Cuándo sí tendría sentido:** Únicamente como **índice parcial** si existiera un patrón de consulta muy frecuente y selectivo sobre un valor minoritario, por ejemplo:
   ```sql
   CREATE INDEX idx_pedido_forma_pago_tarjeta ON pedido(id)
     WHERE forma_pago = 'TARJETA';
   ```
   Esto tendría sentido solo si `TARJETA` representara <5 % de los pedidos y hubiera consultas que filtren exclusivamente por ese valor. Con la distribución actual del negocio no se justifica, y el spec lo descarta explícitamente por sobreindexación.

### 6.3 Decisión

**Descartado.** Documentado como bloque comentado en `indices.sql:19-25`. No se crea en la base.

---

## 7. Conclusiones

* De los tres índices propuestos, solo **uno** (`idx_pedido_fecha`) produjo una mejora inequívoca y verificable por cambio de plan (`Parallel Seq Scan` → `Index Scan`, 289 ms → 0.018 ms).
* El segundo (`idx_detalle_producto_id`) fue **ignorado por el planner** para el ranking con agregación total; la mejora aparente se atribuye a warm cache, no al índice.
* El tercero (`idx_detalle_subtotal`) **cambió el índice elegido** pero no mejoró el tiempo a este volumen; su valor es de diseño, no de rendimiento medible hoy.
* La medición de escrituras ilustra el **efecto de caché** y no debe interpretarse como que los índices aceleran los `INSERT`.
* El índice en `forma_pago` se **descarta correctamente** por baja cardinalidad y sobreindexación.

El plan de indexado cumple su objetivo didáctico: no todos los índices propuestos mejoran el rendimiento, y el análisis honesto del `EXPLAIN ANALYZE` es más valioso que una hipótesis simplista de "más índices = más velocidad".

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

### 8.3 Resultados de equivalencia

#### Vista 1 — `vw_productos_vigentes`

```sql
-- Dirección vista → manual
(SELECT id, nombre, precio, stock, nombre_categoria, created_at
 FROM vw_productos_vigentes)
EXCEPT
(SELECT p.id, p.nombre, p.precio, p.stock, c.nombre, p.created_at
 FROM producto p JOIN categoria c ON p.categoria_id = c.id
 WHERE p.activo = TRUE AND c.activo = TRUE);
-- Resultado: 0 filas  ✓

-- Dirección manual → vista
(SELECT p.id, p.nombre, p.precio, p.stock, c.nombre, p.created_at
 FROM producto p JOIN categoria c ON p.categoria_id = c.id
 WHERE p.activo = TRUE AND c.activo = TRUE)
EXCEPT
(SELECT id, nombre, precio, stock, nombre_categoria, created_at
 FROM vw_productos_vigentes);
-- Resultado: 0 filas  ✓
```

**Conclusión:** Equivalencia verificada. La vista incorpora correctamente el filtro doble de vigencia.

---

#### Vista 2 — `vw_pedidos_cliente`

```sql
-- Dirección vista → manual
(SELECT pedido_id, fecha, forma_pago, cliente_id, nombre, apellido, cliente_activo
 FROM vw_pedidos_cliente)
EXCEPT
(SELECT p.id, p.fecha, p.forma_pago, c.id, c.nombre, c.apellido, c.activo
 FROM pedido p JOIN cliente c ON p.cliente_id = c.id);
-- Resultado: 0 filas  ✓

-- Dirección manual → vista
(SELECT p.id, p.fecha, p.forma_pago, c.id, c.nombre, c.apellido, c.activo
 FROM pedido p JOIN cliente c ON p.cliente_id = c.id)
EXCEPT
(SELECT pedido_id, fecha, forma_pago, cliente_id, nombre, apellido, cliente_activo
 FROM vw_pedidos_cliente);
-- Resultado: 0 filas  ✓
```

**Conclusión:** Equivalencia verificada. Las columnas excluidas (`email`, `telefono`, `created_at`) no alteran la cardinalidad ni la identidad de las filas.

**Nota sobre el criterio de seguridad:** La tabla `cliente` del esquema actual no tiene columna `contrasena`. La vista demuestra el patrón de ocultación con `email` y `telefono` (datos de contacto personal). Un rol con `GRANT SELECT ON vw_pedidos_cliente TO role_reporte` no puede acceder a esas columnas ni mediante `SELECT *` ni mediante consulta directa sobre la vista, porque no forman parte de su definición.

---

#### Vista 3 — `vw_detalle_pedido`

```sql
-- Dirección vista → manual
(SELECT pedido_id, nombre_producto, cantidad, precio_unitario, subtotal
 FROM vw_detalle_pedido)
EXCEPT
(SELECT pd.pedido_id, pr.nombre, pd.cantidad, pd.precio_unitario, pd.subtotal
 FROM pedido_detalle pd JOIN producto pr ON pd.producto_id = pr.id);
-- Resultado: 0 filas  ✓

-- Dirección manual → vista
(SELECT pd.pedido_id, pr.nombre, pd.cantidad, pd.precio_unitario, pd.subtotal
 FROM pedido_detalle pd JOIN producto pr ON pd.producto_id = pr.id)
EXCEPT
(SELECT pedido_id, nombre_producto, cantidad, precio_unitario, subtotal
 FROM vw_detalle_pedido);
-- Resultado: 0 filas  ✓
```

**Conclusión:** Equivalencia verificada. La vista puede filtrarse por `WHERE pedido_id = :id` con el mismo resultado que la consulta manual equivalente.

---

### 8.4 Resumen

| Vista | Dir. vista→manual | Dir. manual→vista | Equivalencia |
|---|:---:|:---:|:---:|
| `vw_productos_vigentes` | 0 filas ✓ | 0 filas ✓ | **Verificada** |
| `vw_pedidos_cliente` | 0 filas ✓ | 0 filas ✓ | **Verificada** |
| `vw_detalle_pedido` | 0 filas ✓ | 0 filas ✓ | **Verificada** |

Las tres vistas son equivalentes a sus consultas manuales correspondientes. El criterio de seguridad de `vw_pedidos_cliente` excluye correctamente `email`, `telefono` y `created_at` sin romper la equivalencia de filas.

---

## Nota — Declaración de Uso de IA (DUIA) — Parte B

| Campo | Detalle |
|---|---|
| **Herramienta** | Kiro (agente de especificación) |
| **Qué generó** | `requirements.md` (Parte B), `views.sql` (3 vistas + 6 bloques EXCEPT), y la presente sección §8 del informe |
| **Qué se aceptó** | La estructura de los requisitos EARS/INCOSE, las definiciones SQL de las tres vistas y los bloques de verificación de equivalencia |
| **Qué se modificó o descartó, y por qué** | Se ajustó la justificación del criterio de seguridad en `vw_pedidos_cliente`: dado que la tabla `cliente` del esquema actual no tiene columna `contrasena`, se documentó el patrón con `email` y `telefono` y se incluyó una nota explícita sobre cómo extenderlo si se agrega una columna de autenticación en el futuro |
| **Verificación realizada** | Contraste de columnas expuestas vs. esquema en `schema.sql`; revisión de que los `EXCEPT` cubren exactamente las mismas columnas que las vistas definen |
