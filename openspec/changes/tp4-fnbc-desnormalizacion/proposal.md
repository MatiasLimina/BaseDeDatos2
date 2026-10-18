# Proposal: TP4 – FNBC y desnormalización controlada en Food Store

## Why

La consigna del TP Unidad 4 (`TP4/TP_U4_FNBC_Desnormalizacion_FoodStore.pdf`) exige dos decisiones de diseño respaldadas por evidencia: (1) llevar a FNBC la extensión mayorista `control_lote_almacen`, que cumple 3FN pero no FNBC por la dependencia `ResponsableControlID → DepositoID`, y (2) desnormalizar de forma controlada el reporte "top 5 de categorías vendidas en el día", que hoy recorre y une cuatro tablas en cada refresco del panel de administración. Ninguna afirmación se acepta sin el script SQL o la salida de `EXPLAIN ANALYZE` que la demuestre.

## What Changes

**Parte 1 – FNBC (`TP4/tp_fnbc_control_lote.sql`)**
- Crear tablas maestras mínimas y aisladas `lote`, `deposito` y `usuario` (no existen en el schema real; la consigna las asume) y el esquema original `control_lote_almacen` con su instancia de ejemplo `(501,30,801)`, `(502,30,801)`, `(503,31,802)`.
- Documentar dependencias funcionales, clausuras, claves candidatas (`{Lote, Depósito}` y `{Lote, Responsable}`), atributos primos, la violación de FNBC y las tres anomalías sobre la instancia.
- Descomponer sin pérdida en `responsable_deposito(responsable_control_id PK, deposito_id)` y `control_lote(lote_id, responsable_control_id, PK compuesta)`, con FKs explícitas `ON DELETE RESTRICT`.
- Crear la vista de compatibilidad `v_control_lote_almacen` (reunión natural), migrar los datos y verificar equivalencia con `EXCEPT` en ambos sentidos (0 filas).
- Documentar el costo asumido: la DF `{Lote, Depósito} → Responsable` deja de imponerse localmente (no se preserva la dependencia).

**Parte 2 – Desnormalización (`TP4/tp_desnormalizacion_top_categorias.sql`)**
- Adaptar el schema real a la consigna: agregar `eliminado BOOLEAN NOT NULL DEFAULT FALSE` a `pedido` y `pedido_detalle` (baja lógica, R7). Se usa `pedido_detalle` (no `detalle_pedido`) y, como `pedido.fecha` es `TIMESTAMPTZ`, el filtro "del día" se expresa por rango de día de negocio (no `= CURRENT_DATE`).
- Generar datos de prueba con `generate_series`: al menos 8 categorías y un volumen alto de pedidos/detalles con fecha de hoy.
- Medir la consulta original con `EXPLAIN (ANALYZE, BUFFERS)` (baseline).
- Crear la tabla de totales diarios `ventas_diarias_categoria(fecha, categoria_id, total_vendido, ...)` mantenida por disparadores sobre `pedido_detalle`, `pedido` y `producto` (upsert atómico `INSERT ... ON CONFLICT DO UPDATE`), con carga inicial (backfill).
- Reescribir el reporte leyendo la estructura desnormalizada y medirlo; tabla antes/después.
- Script de auditoría que compara la tabla contra la fuente de verdad y devuelve 0 filas.

**Documentación y verificación**
- `TP4/informe_tp4.md` (y PDF si es viable), `TP4/pruebas_manuales.md` (pruebas numeradas con objetivo, SQL exacto, resultado esperado y checkbox) y `TP4/tests/*.sql` (Strict TDD: cada test falla primero).
- Integración posterior a `Proyecto_Integrador/database/` y `Proyecto_Integrador/documentos/` **solo tras confirmación explícita del usuario**, en commits separados.

No hay cambios **BREAKING** sobre el schema del Proyecto Integrador dentro de este change hasta la etapa de integración; la columna `eliminado` se agrega con `DEFAULT FALSE`, por lo que las consultas e inserciones existentes siguen funcionando.

## Capabilities

### New Capabilities
- `control-lote-almacen`: registro del control de calidad de lotes por depósito y responsable, en FNBC, con vista de compatibilidad que reconstruye la relación original y migración verificable.
- `ventas-diarias-categoria`: totales de venta por día y categoría mantenidos de forma redundante y sincronizada con pedidos/detalles, el reporte "top 5 categorías del día" que los consume y su auditoría de consistencia.

### Modified Capabilities
<!-- No existen specs previas en openspec/specs/; no hay capacidades modificadas. -->

## Impact

- **Base de trabajo**: `tp4_foodstore` (clon descartable de `food_store_copia`, PG 18.6). Nunca se tocan `food_store` ni `food_store_copia`.
- **Tablas afectadas (Parte 2)**: `pedido` y `pedido_detalle` (nueva columna `eliminado`, nuevos disparadores), `producto` (disparador ante cambio de `categoria_id`), `categoria` (nuevas filas de prueba). Nueva tabla `ventas_diarias_categoria`.
- **Tablas nuevas (Parte 1)**: `lote`, `deposito`, `usuario`, `control_lote_almacen`, `responsable_deposito`, `control_lote`, vista `v_control_lote_almacen`.
- **Escritura**: cada `INSERT/UPDATE/DELETE` sobre detalles y pedidos paga el costo del disparador (upsert sobre una fila caliente por categoría y día).
- **Entregables**: todo en `TP4/`. `Proyecto_Integrador/` queda intacto hasta la confirmación del usuario.
- **Entorno**: el MCP `postgres` quedó temporalmente con escritura habilitada apuntando a `tp4_foodstore`; debe restaurarse al terminar.
