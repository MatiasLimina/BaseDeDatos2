-- =====================================================================
-- Proyecto Integrador: Food Store
-- Cátedra: Base de Datos II - Universidad Tecnológica Nacional (UTN)
-- Archivo: consultas_avanzadas.sql
-- Motor: PostgreSQL 16+
-- Descripción: Consultas DML avanzadas y analítica de negocio.
--   Demostración de JOINs múltiples, agregaciones con HAVING,
--   subconsultas correlacionadas, CTEs (Common Table Expressions),
--   funciones de ventana (Window Functions: DENSE_RANK, SUM OVER, LAG)
--   y segmentación condicional (CASE WHEN).
-- =====================================================================


-- =====================================================================
-- CONSULTA 1: Agrupación y Filtro Post-Agregación con HAVING
-- =====================================================================
--
-- 1. Caso de Uso / Pregunta de Negocio:
--    ¿Quiénes son nuestros clientes de mayor valor comercial ("High-Value Frequent Customers")?
--    Se busca identificar a aquellos clientes activos que posean fidelidad recurrente
--    (más de 3 pedidos completados) y un nivel de gasto acumulado significativo
--    (superior a $10,000.00 en total histórico), para incluirlos en programas de
--    fidelización exclusiva o campañas de retención VIP.
--
-- 2. Conceptos de Base de Datos II Evidenciados:
--    - Múltiples JOINs entre entidades relacionales (cliente -> pedido -> pedido_detalle).
--    - Respeto del patrón de baja lógica (c.activo = TRUE).
--    - Agrupación por clave primaria y atributos determinísticos (GROUP BY c.id, c.nombre, ...).
--    - Filtro post-agregación mediante cláusula HAVING combinando múltiples métricas
--      (COUNT(DISTINCT p.id) y SUM(pd.subtotal)).
--    - Funciones de agregación de resumen (COUNT, SUM, AVG, ROUND).
--
-- 3. Explicación del Plan / Costo Esperado (Query Planner):
--    - El optimizador aplica primero el filtro condicional 'c.activo = TRUE' mediante
--      un Index Scan / Seq Scan sobre la tabla cliente.
--    - Para realizar los cruces, utiliza 'idx_pedido_cliente_id' para resolver el JOIN
--      hacia 'pedido' y luego cruza con 'pedido_detalle' mediante un Hash Join o Merge Join.
--    - La agregación se ejecuta comúnmente vía 'HashAggregate' (si la memoria 'work_mem'
--      lo permite) creando buckets en memoria por cada cliente, o 'GroupAggregate' si
--      las tuplas vienen preordenadas.
--    - El predicado HAVING se evalúa como un nodo 'Filter' inmediatamente posterior a la
--      agregación sobre los resultados agrupados, descartando clientes que no superen
--      el umbral antes del nodo final 'Sort' (total_gastado DESC).
-- =====================================================================

SELECT
    c.id                                  AS cliente_id,
    c.nombre                              AS cliente_nombre,
    c.apellido                            AS cliente_apellido,
    c.email                               AS cliente_email,
    COUNT(DISTINCT p.id)                  AS total_pedidos,
    SUM(pd.cantidad)                      AS total_unidades_compradas,
    SUM(pd.subtotal)                      AS total_gastado,
    ROUND(AVG(pd.subtotal), 2)            AS ticket_promedio_linea
FROM cliente c
JOIN pedido p 
    ON c.id = p.cliente_id
JOIN pedido_detalle pd 
    ON p.id = pd.pedido_id
WHERE c.activo = TRUE
GROUP BY 
    c.id, 
    c.nombre, 
    c.apellido, 
    c.email
HAVING COUNT(DISTINCT p.id) > 3 
   AND SUM(pd.subtotal) > 10000.00
ORDER BY 
    total_gastado DESC, 
    total_pedidos DESC;



-- =====================================================================
-- CONSULTA 2: Subconsultas Correlacionadas contra el Promedio de Categoría
-- =====================================================================
--
-- 1. Caso de Uso / Pregunta de Negocio:
--    ¿Qué productos activos tienen un precio unitario "premium" que se sitúa
--    estrictamente por encima de la media de precios de su propia categoría?
--    Esta consulta permite al área comercial detectar ítems de alto margen o evaluar
--    desviaciones de precios relativas dentro de cada línea de catálogo vigente.
--
-- 2. Conceptos de Base de Datos II Evidenciados:
--    - Subconsulta correlacionada en la cláusula WHERE: la subconsulta se parametriza
--      y evalúa en función del contexto de la fila externa (p1.categoria_id = p2.categoria_id).
--    - Subconsulta correlacionada en la proyección (SELECT): cálculo simultáneo del
--      benchmark de categoría y la brecha monetaria absoluta.
--    - Integridad de catálogo: exclusión de categorías y productos dados de baja lógica
--      (p1.activo = TRUE, c.activo = TRUE, p2.activo = TRUE).
--
-- 3. Explicación del Plan / Costo Esperado (Query Planner):
--    - En PostgreSQL 16+, el optimizador puede ejecutar la subconsulta correlacionada
--      mediante un nodo 'SubPlan' o transformar el patrón empleando un operador 'Memoize'.
--    - Con el índice compuesto 'idx_producto_categoria_activo (categoria_id, activo)',
--      cada invocación de la subconsulta realiza un Index Only Scan o Bitmap Index Scan
--      acotado únicamente a los productos activos de esa categoría en lugar de escanear la tabla entera.
--    - El nodo 'Memoize' cachea el resultado del AVG por categoria_id en memoria, evitando
--      recalcular el promedio si múltiples productos pertenecen a la misma categoría,
--      reduciendo drásticamente el costo de ejecución a O(N) filas externas.
-- =====================================================================

SELECT
    p1.id                                 AS producto_id,
    p1.nombre                             AS producto,
    p1.precio                             AS precio_unitario,
    c.id                                  AS categoria_id,
    c.nombre                              AS categoria,
    (
        SELECT ROUND(AVG(p2.precio), 2)
        FROM producto p2
        WHERE p2.categoria_id = p1.categoria_id
          AND p2.activo = TRUE
    )                                     AS precio_promedio_categoria,
    ROUND(
        p1.precio - (
            SELECT AVG(p2.precio)
            FROM producto p2
            WHERE p2.categoria_id = p1.categoria_id
              AND p2.activo = TRUE
        ), 
        2
    )                                     AS diferencia_sobre_promedio
FROM producto p1
JOIN categoria c 
    ON p1.categoria_id = c.id
WHERE p1.activo = TRUE
  AND c.activo = TRUE
  AND p1.precio > (
      SELECT AVG(p2.precio)
      FROM producto p2
      WHERE p2.categoria_id = p1.categoria_id
        AND p2.activo = TRUE
  )
ORDER BY 
    c.nombre ASC, 
    p1.precio DESC;



-- =====================================================================
-- CONSULTA 3: Ranking de Productos con Funciones de Ventana (DENSE_RANK)
-- =====================================================================
--
-- 1. Caso de Uso / Pregunta de Negocio:
--    ¿Cuáles son los 3 productos más vendidos (Top 3 por volumen físico) dentro
--    de cada categoría comercial?
--    Permite a la gerencia de compras optimizar el abastecimiento y la reposición
--    de inventario garantizando stock de los productos líderes de cada rubro.
--
-- 2. Conceptos de Base de Datos II Evidenciados:
--    - Common Table Expression (CTE WITH): estructuración modular de la consulta para
--      aislar la capa de agregación base de la capa de filtrado por ranking.
--    - Función de Ventana Analítica: 'DENSE_RANK() OVER (PARTITION BY ... ORDER BY ...)'
--      para asignar posiciones consecutivas sin omitir puestos en caso de empates.
--    - Particionamiento de ventana ('PARTITION BY c.id, c.nombre'): segmenta el cálculo
--      independiente por categoría sin colapsar las filas de los productos.
--    - Filtro sobre resultado de ventana en la consulta externa ('WHERE ranking_categoria <= 3'),
--      solucionando la restricción técnica de que las Window Functions no se pueden evaluar
--      directamente en el WHERE de su propio nivel.
--
-- 3. Explicación del Plan / Costo Esperado (Query Planner):
--    - El CTE calcula la agregación base mediante un HashAggregate o GroupAggregate
--      sobre el JOIN entre categoria, producto, pedido_detalle y pedido.
--    - Los resultados pasan a un nodo 'Sort' con claves (categoria_id, SUM(cantidad) DESC).
--    - Posteriormente, el nodo 'WindowAgg' recorre el flujo ordenado en una sola pasada lineal
--      computando el DENSE_RANK() para cada tupla dentro de los límites de su partición.
--    - La consulta exterior procesa el CTE como una subconsulta en línea o CTE materializado,
--      aplicando un filtro simple 'Filter: (ranking_categoria <= 3)'.
-- =====================================================================

WITH ranking_productos AS (
    SELECT
        c.id                              AS categoria_id,
        c.nombre                          AS categoria,
        pr.id                             AS producto_id,
        pr.nombre                         AS producto,
        pr.precio                         AS precio_actual,
        SUM(pd.cantidad)                  AS total_unidades_vendidas,
        SUM(pd.subtotal)                  AS facturacion_total_producto,
        DENSE_RANK() OVER (
            PARTITION BY c.nombre
            ORDER BY SUM(pd.cantidad) DESC, SUM(pd.subtotal) DESC
        )                                 AS ranking_categoria
    FROM categoria c
    JOIN producto pr 
        ON c.id = pr.categoria_id
    JOIN pedido_detalle pd 
        ON pr.id = pd.producto_id
    JOIN pedido p 
        ON pd.pedido_id = p.id
    WHERE c.activo = TRUE
      AND pr.activo = TRUE
    GROUP BY 
        c.id, 
        c.nombre, 
        pr.id, 
        pr.nombre, 
        pr.precio
)
SELECT
    ranking_categoria                     AS posicion_top,
    categoria,
    producto,
    precio_actual,
    total_unidades_vendidas,
    facturacion_total_producto
FROM ranking_productos
WHERE ranking_categoria <= 3
ORDER BY 
    categoria ASC, 
    ranking_categoria ASC, 
    total_unidades_vendidas DESC;



-- =====================================================================
-- CONSULTA 4: Análisis Temporal y Acumulados Móviles con SUM OVER y LAG
-- =====================================================================
--
-- 1. Caso de Uso / Pregunta de Negocio:
--    ¿Cómo evoluciona el comportamiento de compra de cada cliente a lo largo del tiempo?
--    Para cada transacción realizada, se requiere conocer el total del pedido actual,
--    el monto acumulado histórico que el cliente lleva gastado hasta esa fecha exacta,
--    el valor de su pedido cronológico anterior y la variación monetaria entre compras
--    consecutivas (incremento o decremento de gasto).
--
-- 2. Conceptos de Base de Datos II Evidenciados:
--    - CTE de consolidación a nivel grano de pedido (un pedido = un registro con su suma de subtotales).
--    - Función de Ventana de Agregación Acumulativa:
--      'SUM(total_pedido) OVER (PARTITION BY cliente_id ORDER BY fecha ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)'
--      que implementa un Running Total determinístico.
--    - Función de Ventana de Desplazamiento Relativo:
--      'LAG(total_pedido, 1) OVER (PARTITION BY cliente_id ORDER BY fecha)' para acceder al registro inmediatamente anterior.
--    - Tratamiento robusto de valores NULL con 'COALESCE' para inicializar el estado del primer pedido.
--
-- 3. Explicación del Plan / Costo Esperado (Query Planner):
--    - La CTE preagrega los detalles por pedido mediante un 'HashAggregate' agrupando por
--      (p.id, p.fecha, p.forma_pago, c.id, c.nombre, c.apellido).
--    - El planificador ordena las tuplas resultantes mediante un 'Sort' compuesto por
--      (cliente_id, fecha ASC, pedido_id ASC).
--    - Un único nodo 'WindowAgg' en el plan ejecuta simultáneamente las dos funciones de ventana
--      (SUM y LAG) al compartir idéntica cláusula de partición y orden, realizando un streaming
--      secuencial sin necesidad de múltiples ordenamientos ni escaneos repetidos en disco.
-- =====================================================================

WITH pedido_totales AS (
    SELECT
        p.id                              AS pedido_id,
        p.fecha                           AS fecha_pedido,
        p.forma_pago                      AS forma_pago,
        c.id                              AS cliente_id,
        c.nombre || ' ' || c.apellido     AS cliente,
        SUM(pd.subtotal)                  AS total_pedido
    FROM pedido p
    JOIN cliente c 
        ON p.cliente_id = c.id
    JOIN pedido_detalle pd 
        ON p.id = pd.pedido_id
    WHERE c.activo = TRUE
    GROUP BY 
        p.id, 
        p.fecha, 
        p.forma_pago, 
        c.id, 
        c.nombre, 
        c.apellido
)
SELECT
    cliente_id,
    cliente,
    pedido_id,
    fecha_pedido,
    forma_pago,
    total_pedido,
    
    -- Gasto acumulado histórico del cliente hasta este pedido
    SUM(total_pedido) OVER (
        PARTITION BY cliente_id
        ORDER BY fecha_pedido ASC, pedido_id ASC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                     AS gasto_acumulado_historico,
    
    -- Monto del pedido inmediatamente anterior (0.00 si es su primera compra)
    COALESCE(
        LAG(total_pedido, 1) OVER (
            PARTITION BY cliente_id
            ORDER BY fecha_pedido ASC, pedido_id ASC
        ),
        0.00
    )                                     AS monto_pedido_anterior,
    
    -- Variación neta respecto a la compra previa
    ROUND(
        total_pedido - COALESCE(
            LAG(total_pedido, 1) OVER (
                PARTITION BY cliente_id
                ORDER BY fecha_pedido ASC, pedido_id ASC
            ),
            total_pedido
        ),
        2
    )                                     AS variacion_vs_pedido_anterior
FROM pedido_totales
ORDER BY 
    cliente_id ASC, 
    fecha_pedido ASC, 
    pedido_id ASC;



-- =====================================================================
-- CONSULTA 5: Segmentación de Clientes según Nivel de Consumo (CTE + CASE)
-- =====================================================================
--
-- 1. Caso de Uso / Pregunta de Negocio:
--    ¿Cuál es la segmentación de cartera de clientes bajo un modelo de clasificación ABC
--    y análisis de actividad reciente (Recencia y Frecuencia)?
--    Se clasifica a todos los clientes registrados (incluso aquellos sin compras históricas)
--    en segmentos: 'CLIENTE VIP', 'CLIENTE FRECUENTE', 'CLIENTE OCASIONAL' e 'INACTIVO / SIN COMPRAS',
--    junto con su recencia de compra para guiar estrategias comerciales diferenciadas.
--
-- 2. Conceptos de Base de Datos II Evidenciados:
--    - CTE para precalcular las métricas dimensionales de consumo por cliente.
--    - Uso de 'LEFT OUTER JOIN' entre cliente, pedido y pedido_detalle para garantizar
--      la preservación de clientes con 0 pedidos (cardinalidad 0..N en el modelo relacional).
--    - Manejo de dimensionalidad y valores nulos con 'COALESCE' y agregaciones protegidas.
--    - Lógica de segmentación multidimensional mediante expresiones condicionales 'CASE WHEN'.
--    - Operaciones con intervalos temporales ('now() - INTERVAL ...') para evaluación de recencia.
--
-- 3. Explicación del Plan / Costo Esperado (Query Planner):
--    - El optimizador utiliza un 'Hash Left Join' o 'Merge Left Join' para relacionar la totalidad
--      de clientes activos con sus eventuales pedidos y detalles.
--    - Se utiliza el índice 'idx_pedido_cliente_id' para optimizar la recolección de pedidos asociados.
--    - La agregación 'HashAggregate' procesa la suma y conteos por cliente.
--    - La evaluación de las ramas 'CASE WHEN' se produce fila a fila en el paso de proyección
--      del SELECT sin requerir operaciones auxiliares de E/S ni reescrituras costosas.
-- =====================================================================

WITH metricas_cliente AS (
    SELECT
        c.id                              AS cliente_id,
        c.nombre || ' ' || c.apellido     AS cliente,
        c.email                           AS email,
        c.telefono                        AS telefono,
        c.created_at                      AS fecha_alta,
        COUNT(DISTINCT p.id)              AS total_pedidos,
        COALESCE(SUM(pd.subtotal), 0.00)  AS gasto_total,
        COALESCE(ROUND(AVG(pd.subtotal), 2), 0.00) AS ticket_promedio_linea,
        MAX(p.fecha)                      AS fecha_ultima_compra
    FROM cliente c
    LEFT JOIN pedido p 
        ON c.id = p.cliente_id
    LEFT JOIN pedido_detalle pd 
        ON p.id = pd.pedido_id
    WHERE c.activo = TRUE
    GROUP BY 
        c.id, 
        c.nombre, 
        c.apellido, 
        c.email, 
        c.telefono, 
        c.created_at
)
SELECT
    cliente_id,
    cliente,
    email,
    telefono,
    total_pedidos,
    gasto_total,
    ticket_promedio_linea,
    fecha_ultima_compra,
    
    -- Segmentación de Valor (Clasificación ABC)
    CASE
        WHEN total_pedidos = 0 OR gasto_total = 0.00 THEN 'INACTIVO / SIN COMPRAS'
        WHEN total_pedidos >= 5 AND gasto_total >= 50000.00 THEN 'CLIENTE VIP'
        WHEN total_pedidos >= 2 AND gasto_total >= 15000.00 THEN 'CLIENTE FRECUENTE'
        WHEN total_pedidos >= 1 THEN 'CLIENTE OCASIONAL'
        ELSE 'NO CLASIFICADO'
    END                                   AS segmento_cliente,
    
    -- Estado de Recencia según última compra
    CASE
        WHEN fecha_ultima_compra IS NULL THEN 'Sin Compras Registradas'
        WHEN fecha_ultima_compra >= (now() - INTERVAL '30 days') THEN 'Activo Reciente (<= 30 días)'
        WHEN fecha_ultima_compra >= (now() - INTERVAL '90 days') THEN 'Regular (31 a 90 días)'
        ELSE 'En Riesgo / Inactivo (> 90 días)'
    END                                   AS estado_recencia
FROM metricas_cliente
ORDER BY 
    gasto_total DESC, 
    total_pedidos DESC, 
    cliente_id ASC;
