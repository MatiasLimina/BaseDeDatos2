Implementation Plan - TP3 Parte A: Plan de Indexado

Problem Statement: Diseñar e implementar un plan de indexado para el sistema Food Store (PostgreSQL) que identifique consultas con Seq Scan, proponga y valide índices mediante EXPLAIN ANALYZE, mida el impacto en escrituras, y documente el rechazo justificado de al menos un índice por sobreindexación. Entregables: queries.sql + indices.sql.

Requirements:

Crear queries.sql con al menos 3 consultas frecuentes que producen Seq Scan
Para cada consulta: especificación de frecuencia, columnas de filtro/JOIN/ORDER BY
Proponer índice adecuado (tipo, columnas, orden, parcial si aplica)
Medir antes/después con EXPLAIN ANALYZE (a completar por el usuario)
Medir costo en escrituras: INSERT masivo en pedido_detalle antes/después
Descartar al menos 1 índice con justificación escrita
Entregables finales: queries.sql + indices.sql (con comentarios)
Background: El esquema existente tiene 5 tablas: categoria, producto, cliente, pedido, pedido_detalle. Ya existen dos índices del TP1:

idx_pedido_cliente_id ON pedido(cliente_id) — cubre búsqueda de pedidos por cliente
idx_producto_categoria_activo ON producto(categoria_id, activo) — cubre listado de productos activos por categoría
Las tres consultas candidatas más representativas del negocio son:

Historial de ventas por fecha — pedido filtrado por rango de fecha + forma_pago, sin índice en fecha
Ranking de productos más vendidos — JOIN entre pedido_detalle y producto, agrupado por producto_id, sin índice en pedido_detalle(producto_id) (la PK es compuesta (pedido_id, producto_id), el segundo campo no está indexado solo)
Detalle de un pedido específico con totales — pedido_detalle filtrado por pedido_id + ORDER BY subtotal DESC, cubierto por PK pero sin orden en subtotal
El índice descartado será: pedido(forma_pago) — baja cardinalidad (solo 4 valores ENUM posibles), sin condición parcial que lo justifique, redundante con un full scan que PostgreSQL preferiría de todas formas.

Estado: ✅ COMPLETADA — 05/09/2026 — Ver `TP3/informe_mediciones.md` (informe técnico con mediciones EXPLAIN ANALYZE antes/después, análisis honesto y DUIA).

Proposed Solution: Crear 
queries.sql
 con las 3 consultas anotadas + script de medición de escrituras, y 
indices.sql
 con los CREATE INDEX aceptados y la propuesta descartada documentada.

Task Breakdown:

Task 1: Crear queries.sql con las 3 consultas frecuentes anotadas

Objetivo: Escribir las consultas SQL representativas del negocio con comentarios que expliquen frecuencia de uso, columnas involucradas y por qué producen Seq Scan hoy.
Consultas a incluir:
Pedidos en un rango de fechas con filtro de forma de pago
Top 5 productos más vendidos (por cantidad total)
Detalle completo de un pedido ordenado por subtotal descendente
También incluir: bloque de INSERT masivo (~500 filas en pedido_detalle) para medir costo de escritura antes/después de crear los índices
Demo: Archivo ejecutable en psql que devuelve resultados correctos sobre la base existente
Task 2: Crear indices.sql con los índices aceptados, la propuesta descartada, y los bloques EXPLAIN ANALYZE

Objetivo: Documentar en SQL los índices finalmente creados, con comentarios que expliquen el tipo elegido, las columnas, el orden y (si aplica) la condición parcial. Incluir también el índice descartado como comentario con justificación.
Índices a crear:
idx_pedido_fecha — ON pedido(fecha) — B-tree, cubre filtros por rango de fecha
idx_detalle_producto_id — ON pedido_detalle(producto_id) — B-tree, cubre el ranking de productos (el segundo campo de la PK compuesta no es usable solo)
idx_detalle_subtotal — ON pedido_detalle(pedido_id, subtotal DESC) — B-tree compuesto, cubre el ORDER BY del detalle de pedido sin sort adicional
Índice descartado (comentado): ON pedido(forma_pago) — justificación: cardinalidad = 4 valores, PostgreSQL preferirá Seq Scan + filter de todas formas; solo sería útil con condición parcial tipo WHERE forma_pago = 'TARJETA' en un sistema con distribución muy desigual
Incluir: bloques EXPLAIN ANALYZE listos para ejecutar antes y después de cada CREATE INDEX, con marcadores para completar con los resultados reales
Demo: Archivo ejecutable que, al correrlo después de queries.sql, crea los 3 índices y deja el esquema listo para medir

## Estado de entrega — 05/09/2026

- [x] Task 1 — `TP3/queries.sql` entregado (3 consultas + bloque INSERT 500 filas)
- [x] Task 2 — `TP3/indices.sql` entregado (3 CREATE INDEX + índice descartado comentado + bloques EXPLAIN ANALYZE)
- [x] Informe técnico — `TP3/informe_mediciones.md` generado a partir de `TP3/Anotacion_mediciones.txt` con análisis honesto:
  - C1: Parallel Seq Scan 289.652 ms → Index Scan 0.018 ms (mejora clara)
  - C2: Seq Scan persiste — planner ignoró índice; 423.892 ms → 218.262 ms atribuido a buffer cache
  - C3: Index Scan PK 0.055 ms → Index Scan idx_detalle_subtotal 0.102 ms (ya era eficiente)
  - INSERT 0.313 s → 0.058 s — paradójico por warm cache (shared_buffers)
  - Índice descartado `pedido(forma_pago)` justificado por cardinalidad = 4
- Entregable renderizable sin placeholders — ver `TP3/informe_mediciones.md:1`