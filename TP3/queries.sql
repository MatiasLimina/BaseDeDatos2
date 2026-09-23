-- =====================================================================
-- Base de Datos II — Trabajo Práctico Unidad 3 (Food Store)
-- Archivo: queries.sql
-- Integrantes: Matías Limina, Nicolás Monjelardi, Lautaro Agüero
-- Motor: PostgreSQL 16+
-- Repositorio: https://github.com/MatiasLimina/BaseDeDatos2.git
-- =====================================================================

-- Consulta 1: Pedidos en un rango de fechas con filtro de forma de pago
-- Frecuencia: Alta (Reportes operativos diarios)
-- Columnas: fecha (rango), forma_pago (igualdad)
-- Comportamiento previo: Parallel Seq Scan en tabla 'pedido' (289.65 ms)
-- Solución: Optimizado con índice B-tree idx_pedido_fecha (0.018 ms)
SELECT * FROM pedido
WHERE fecha BETWEEN '2023-01-01' AND '2023-12-31'
  AND forma_pago = 'EFECTIVO';


-- Consulta 2: Top 5 productos más vendidos (por cantidad total)
-- Frecuencia: Media (Reporte comercial semanal/mensual)
-- Columnas: producto_id, cantidad
-- Comportamiento previo: Seq Scan en pedido_detalle + Hash Join con producto (423.89 ms)
-- Diagnóstico empírico: Un índice en producto_id es ignorado por el planner debido
-- a que debe leerse casi la totalidad de las 621.199 filas para agregar.
SELECT p.nombre, SUM(pd.cantidad) AS total_vendido
FROM pedido_detalle pd
JOIN producto p ON pd.producto_id = p.id
GROUP BY p.id, p.nombre
ORDER BY total_vendido DESC
LIMIT 5;


-- Consulta 3: Detalle completo de un pedido ordenado por subtotal descendente
-- Frecuencia: Alta/Media (Consulta puntual al ver pedido o emitir comprobante)
-- Columnas: pedido_id (filtro de igualdad), subtotal (orden descendente)
-- Corrección de diagnóstico: Esta consulta NO resolvía con Seq Scan.
--   La tabla pedido_detalle posee clave primaria compuesta pk_pedido_detalle(pedido_id, producto_id).
--   Al ser pedido_id la columna líder del índice B-tree de la PK, PostgreSQL ya resolvía
--   la consulta mediante Index Scan altamente eficiente (0.055 ms).
--   La propuesta de un índice secundario (pedido_id, subtotal DESC) introdujo overhead (0.102 ms)
--   sin aportar beneficio, por lo que fue descartada.
SELECT * FROM pedido_detalle
WHERE pedido_id = 123
ORDER BY subtotal DESC;


-- =====================================================================
-- Bloque de inserción masiva para medir costo de escritura
-- Ejecutado bajo el protocolo de seguridad en transacción reversible
-- =====================================================================
BEGIN;

DO $$
BEGIN
  FOR i IN 1..500 LOOP
    INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
    VALUES (i, (i % 100) + 1, FLOOR(RANDOM() * 10) + 1, ROUND((RANDOM() * 100)::numeric, 2), 0);
  END LOOP;
END $$;

-- Verificación de inserciones
SELECT COUNT(*) AS filas_insertadas_test FROM pedido_detalle WHERE subtotal = 0;

-- Reversión para mantener el estado de la base inalterado
ROLLBACK;