-- =====================================================================
-- 01_seleccion_pedidos.sql — Subconjunto de pedidos que se migra a MongoDB
-- Uso: psql -X -w -h localhost -U postgres -d foodstore -At -f sql/01_seleccion_pedidos.sql
-- Devuelve un id por línea.
--
-- Regla determinista: por cada estado, el pedido de menor id que contiene el
-- producto 13896 ("Producto 13891") y el de menor id que no lo contiene. Así
-- el subconjunto cubre los cinco estados (consulta b) y tiene pedidos con y
-- sin el producto elegido (consulta c). PENDIENTE solo tiene un pedido, así
-- que el resultado son 9 pedidos.
--
-- Producto elegido: es uno de los cuatro que el generador de datos repite en
-- unos 155 000 pedidos (78 %), así que aparece en pedidos de todos los estados.
--
-- Solo se consideran los pedidos del lote original (id <= 200001). Si no, un
-- pedido nuevo (que nace PENDIENTE y quizás sin el producto) cambiaría el
-- subconjunto y dejaría de coincidir con lo migrado.
--
-- Lo usan migracion/generar_insert_pedidos.sql y tests/test_migracion.sh.
-- Las consultas de PostgreSQL de la Parte 2 lo reproducen con la lista literal
-- de ids, para comparar contra los mismos pedidos que hay en MongoDB.
-- =====================================================================
WITH marcados AS (
    SELECT p.id, p.estado,
           EXISTS (SELECT 1 FROM pedido_detalle d
                   WHERE d.pedido_id = p.id AND d.producto_id = 13896) AS contiene_producto
    FROM pedido p
    WHERE p.id <= 200001
)
SELECT id
FROM (SELECT DISTINCT ON (estado, contiene_producto) id
      FROM marcados
      ORDER BY estado, contiene_producto, id) s
ORDER BY id;
