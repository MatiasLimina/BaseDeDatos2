# Declaración de Uso de Inteligencia Artificial (DUIA)

**Proyecto:** Food Store — Sistema de gestión de pedidos  
**Materia:** Base de Datos II  
**Carrera:** Tecnicatura Universitaria en Programación  
**Motor de BD:** PostgreSQL 16+  
**Entregable:** Trabajo Práctico Unidad 3 (Índices, Vistas y Vistas Materializadas)  
**Repositorio GitHub:** [https://github.com/MatiasLimina/BaseDeDatos2.git](https://github.com/MatiasLimina/BaseDeDatos2.git)  

### Integrantes del Equipo
* **Matías Limina**
* **Nicolás Monjelardi**
* **Lautaro Agüero**

---

## 1. Declaración General de Responsabilidad y Criterio Humano

En cumplimiento con las normas éticas y metodológicas de la cátedra de Base de Datos II, dejamos constancia de que las herramientas de inteligencia artificial (**Kiro** y **OpenCode**) fueron utilizadas como agentes asistentes para la formulación de especificaciones iniciales y la generación asistida de código SQL.

La totalidad de las decisiones de ingeniería —en particular: la interpretación de los planes de ejecución (`EXPLAIN ANALYZE`), el descarte de índices por sobreindexación, la corrección del diagnóstico de acceso por clave primaria, la validación de equivalencia multiconjunto con `COUNT(*)` y la definición de políticas de seguridad con `GRANT`— fueron analizadas, verificadas, contrastadas con la teoría de bases de datos y asumidas bajo la responsabilidad exclusiva del equipo humano.

---

## 2. Bitácora de Interacciones

### 2.1 Parte A — Plan de Indexado Asistido por IA

| Campo | Detalle |
|---|---|
| **Herramientas utilizadas** | Kiro (agente de especificación EARS/INCOSE) y OpenCode (agente CLI de codificación) |
| **Propósito** | Identificar consultas candidatas con `Seq Scan`, formular especificaciones técnicas y proponer índices optimizadores |
| **Prompt / Spec entregado** | Archivo `TP3/spec_punto_4_1.md` conteniendo el esquema de 5 tablas, el volumen poblado (~621.000 filas en `pedido_detalle`), y las 3 consultas de negocio de `queries.sql` |
| **Propuesta inicial de la IA** | 1. `CREATE INDEX idx_pedido_fecha ON pedido(fecha);`<br>2. `CREATE INDEX idx_pedido_forma_pago ON pedido(forma_pago);`<br>3. `CREATE INDEX idx_detalle_producto_id ON pedido_detalle(producto_id);`<br>4. `CREATE INDEX idx_detalle_subtotal ON pedido_detalle(pedido_id, subtotal DESC);` |
| **Qué se aceptó** | Se aceptó únicamente `idx_pedido_fecha ON pedido(fecha)`. La contrastación empírica con `EXPLAIN ANALYZE` demostró que transformó un `Parallel Seq Scan` de 289.65 ms en un `Index Scan` de 0.018 ms (~16.000× más rápido). |
| **Qué se modificó o descartó (Sobreindexación)** | **1. Descarte de `pedido(forma_pago)`:** Propuesto por la IA para filtrar por tipo de pago. Descartado por criterio humano debido a su muy baja cardinalidad (tipo ENUM de solo 4 valores, selectividad ~25%). PostgreSQL prefiere `Seq Scan` y el índice sólo añadiría costo de escritura.<br>**2. Descarte de `idx_detalle_producto_id`:** Aunque la IA prometía acelerar el Top 5 de ventas, el `EXPLAIN ANALYZE` demostró que el optimizador lo IGNORÓ (mantuvo `Seq Scan + Hash Join`). La aparente reducción de tiempo se debió a *warm cache*. Se descartó para no sobreindexar.<br>**3. Descarte de `idx_detalle_subtotal`:** La IA supuso que la Consulta 3 resolvía con `Seq Scan`. La verificación empírica demostró que ya usaba `Index Scan` por la clave primaria `pk_pedido_detalle(pedido_id, producto_id)`. Al probar el nuevo índice, el tiempo aumentó de 0.055 ms a 0.102 ms (+85% overhead). Se descartó por redundancia y costo injustificado. |
| **Verificación realizada** | Ejecución de `EXPLAIN (ANALYZE, BUFFERS)` en base clonada `food_store_test` antes y después de cada índice; medición del costo en transacciones reversibles (`BEGIN ... ROLLBACK`) con 500 `INSERT` en `pedido_detalle`. |

---

### 2.2 Parte B — Vistas y Criterio de Seguridad

| Campo | Detalle |
|---|---|
| **Herramientas utilizadas** | Kiro (especificación de requerimientos en `spec_punto_4.2/`) y OpenCode |
| **Propósito** | Especificar y generar 3 vistas habituales (`vw_productos_vigentes`, `vw_pedidos_cliente`, `vw_detalle_pedido`), sus pruebas de equivalencia y el aislamiento de datos por seguridad |
| **Prompt / Spec entregado** | Requisitos EARS en `spec_punto_4.2/requirements.md` solicitando encapsular baja lógica (`activo = TRUE`), simplificar JOINs de detalle de pedido y ocultar datos de contacto personales en pedidos |
| **Propuesta inicial de la IA** | Generación de las 3 vistas en `views.sql` y verificación de equivalencia utilizando únicamente pares simétricos de `(SELECT ...) EXCEPT (SELECT ...)`. |
| **Qué se aceptó** | Las definiciones de las 3 vistas y el criterio de seguridad de excluir `email`, `telefono` y `created_at` en `vw_pedidos_cliente`. |
| **Qué se modificó o descartó** | **1. Complementación de `EXCEPT` con `COUNT(*)`:** La IA propuso validar equivalencia exclusivamente con `EXCEPT`. El equipo detectó que `EXCEPT` realiza un `DISTINCT` implícito (semántica de conjuntos), lo cual oculta discrepancias si existieran tuplas duplicadas. Se agregaron bloques explícitos de comparación de `COUNT(*)` para garantizar equivalencia multiconjunto rigurosa.<br>**2. Adición de prueba DCL con Roles:** La IA solo comentó el criterio de seguridad en el código de la vista. El equipo humano implementó el script DCL ejecutable: creación del rol `rol_reportes_foodstore`, asignación de `GRANT SELECT` a la vista, revocación sobre tablas base y demostración práctica de fallo `permission denied for table cliente`. |
| **Verificación realizada** | Ejecución de las 3 diferencias simétricas (0 filas retornadas), validación de conteo idéntico de cardinalidad y ejecución con `SET ROLE rol_reportes_foodstore`. |

---

### 2.3 Parte C — Vista Materializada (`mv_facturacion_categoria_mes`)

| Campo | Detalle |
|---|---|
| **Herramientas utilizadas** | Kiro (`spec_punto_4.3/`) y OpenCode |
| **Propósito** | Diseñar una vista materializada para un reporte analítico costoso con 4 JOINs y agregación temporal sobre ~621.000 filas |
| **Prompt / Spec entregado** | Requerimiento de consolidación histórica mensual de ventas por categoría, con cláusula `WITH DATA` e índice único para permitir actualización concurrente |
| **Propuesta inicial de la IA** | Código SQL de `CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes ... WITH DATA` con índice `CREATE UNIQUE INDEX idx_mv_facturacion_categoria_mes ON mv_facturacion_categoria_mes(categoria, mes)` y plantilla de medición `EXPLAIN (ANALYZE, BUFFERS)`. |
| **Qué se aceptó** | La definición completa de la vista materializada y la justificación del índice `UNIQUE` como prerrequisito obligatorio del motor para soportar `REFRESH MATERIALIZED VIEW CONCURRENTLY`. |
| **Qué se modificó o descartó** | Se ajustaron los parámetros de análisis de latencia: el reporte está diseñado para análisis de gestión gerencial con tolerancia de hasta 24 horas de desactualización, justificando un refresco diario nocturno vía `pg_cron` para no colisionar con la carga OLTP diurna. |
| **Verificación realizada** | Medición de la consulta original (760.82 ms, buffers compartidos y temporales en disco) frente al `SELECT` sobre la vista materializada (0.020 ms, lectura directa de 24 tuplas agregadas en 1 página de buffer). |

---

## 3. Conclusión del Uso de IA

El uso de Kiro y OpenCode aceleró la estructuración de especificaciones y la redacción de scripts SQL. Sin embargo, el valor técnico del trabajo residió en la capacidad crítica de los integrantes del equipo para:
1. Rechazar el 75% de los índices propuestos por la IA por sobreindexación y falta de efectividad real.
2. Identificar que `EXCEPT` sin `COUNT(*)` no prueba equivalencia matemática estricta.
3. Probar en la práctica el aislamiento de privilegios mediante roles y permisos de PostgreSQL.
4. Identificar que la Consulta 3 ya gozaba de un `Index Scan` por clave primaria.

**Firmado:**  
Matías Limina — Nicolás Monjelardi — Lautaro Agüero  
*Estudiantes de Base de Datos II — Tecnicatura Universitaria en Programación*
