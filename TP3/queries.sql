-- Consulta 1: Pedidos en un rango de fechas con filtro de forma de pago
-- Frecuencia: Alta
-- Columnas: fecha, forma_pago
-- Seq Scan: Falta índice en fecha
SELECT * FROM pedido
WHERE fecha BETWEEN '2023-01-01' AND '2023-12-31'
AND forma_pago = 'EFECTIVO';

-- Consulta 2: Top 5 productos más vendidos (por cantidad total)
-- Frecuencia: Media
-- Columnas: producto_id, cantidad
-- Seq Scan: Falta índice en producto_id
SELECT p.nombre, SUM(pd.cantidad) AS total_vendido
FROM pedido_detalle pd
JOIN producto p ON pd.producto_id = p.id
GROUP BY p.id
ORDER BY total_vendido DESC
LIMIT 5;

-- Consulta 3: Detalle completo de un pedido ordenado por subtotal descendente
-- Frecuencia: Media
-- Columnas: pedido_id, subtotal
-- Seq Scan: Falta índice compuesto en (pedido_id, subtotal DESC)
SELECT * FROM pedido_detalle
WHERE pedido_id = 123
ORDER BY subtotal DESC;

-- Bloque de inserción masiva para medir costo de escritura
DO $$
BEGIN
  FOR i IN 1..500 LOOP
    INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
    VALUES (i, i % 100 + 1, FLOOR(RANDOM() * 10) + 1, ROUND((RANDOM() * 100)::numeric, 2), 0);
  END LOOP;
END $$;