-- Índice 1: idx_pedido_fecha
-- Tipo: B-tree
-- Columnas: fecha
-- Justificación: Cubre filtros por rango de fecha en consultas frecuentes
CREATE INDEX idx_pedido_fecha ON pedido(fecha);

-- Índice 2: idx_detalle_producto_id
-- Tipo: B-tree
-- Columnas: producto_id
-- Justificación: Mejora el rendimiento del ranking de productos más vendidos
CREATE INDEX idx_detalle_producto_id ON pedido_detalle(producto_id);

-- Índice 3: idx_detalle_subtotal
-- Tipo: B-tree compuesto
-- Columnas: pedido_id, subtotal DESC
-- Justificación: Elimina el sort adicional en la consulta de detalle de pedido
CREATE INDEX idx_detalle_subtotal ON pedido_detalle(pedido_id, subtotal DESC);

-- Índice descartado: pedido(forma_pago)
/*
Justificación:
- Cardinalidad baja (solo 4 valores posibles)
- PostgreSQL preferirá Seq Scan + filter de todas formas
- Solo sería útil con condición parcial tipo WHERE forma_pago = 'TARJETA'
*/

-- Bloque EXPLAIN ANALYZE antes de crear los índices
EXPLAIN ANALYZE
SELECT * FROM pedido
WHERE fecha BETWEEN '2023-01-01' AND '2023-12-31'
AND forma_pago = 'EFECTIVO';

-- Bloque EXPLAIN ANALYZE después de crear los índices
EXPLAIN ANALYZE
SELECT * FROM pedido
WHERE fecha BETWEEN '2023-01-01' AND '2023-12-31'
AND forma_pago = 'EFECTIVO';