# Parte 2 — Consultas y verificación

Archivos entregados: [`consultas_mongodb.js`](../consultas_mongodb.js) (Consigna 4) y [`consultas_postgresql.sql`](../consultas_postgresql.sql) (Consigna 5). Salidas completas: [`evidencias/parte2_salida_mongodb.txt`](../evidencias/parte2_salida_mongodb.txt) y [`evidencias/parte2_salida_postgresql.txt`](../evidencias/parte2_salida_postgresql.txt).

## Consigna 4 — Consultas en MongoDB

| | Consulta | Instrucción | Resultado (`_id`) |
|---|---|---|---|
| a | Todos los pedidos, con id y estado | `db.pedidos.find({}, {_id: 1, estado: 1}).sort({_id: 1})` | 9 pedidos: 1, 2, 7, 20, 26, 120, 217, 240, 10167 |
| b | Pedidos en un estado | `db.pedidos.find({estado: "ENTREGADO"})` | 2 pedidos: 2, 7 |
| c | Pedidos con un producto en el arreglo de líneas | `db.pedidos.find({"lineas.producto.id": 13896}, {estado: 1, "lineas.$": 1})` | 5 pedidos: 1, 2, 20, 26, 240 |
| d | Pedidos con total mayor que un umbral | `db.pedidos.find({total: {$gt: NumberDecimal("20000.00")}})` | 3 pedidos: 1, 26, 20 |

- **b)** `ENTREGADO` es el estado más frecuente de la base (188 745 de 200 001 pedidos). En los datos migrados hay dos pedidos con ese estado: uno con el producto 13896 y otro sin él.
- **c)** `"lineas.producto.id"` recorre todos los elementos del arreglo. La proyección `"lineas.$"` devuelve solo la línea que coincidió. `explain()` confirma que se usa el índice sobre el arreglo: `FETCH <- IXSCAN(idx_lineas_producto, multikey=true)`, con 5 documentos examinados, que son justamente los 5 resultados.
- **d) El umbral de 20 000 está justificado con los datos de toda la base.** Los totales de los 200 001 pedidos tienen mediana 15 653,28, tercer cuartil 19 731,93 y p90 22 510,46.
  - 20 000 queda apenas por encima del tercer cuartil: identifica los **pedidos grandes**, cerca del 24 % del total.
  - Es una cifra redonda y fácil de comunicar.
  - La comparación es en `Decimal128` y estricta: el pedido 240 (19 782,73) queda afuera, y en PostgreSQL pasa lo mismo.

## Consigna 5 — Equivalentes en PostgreSQL y tabla de verificación

| Consulta | Cantidad en PostgreSQL | Cantidad en MongoDB | ¿Coinciden los ids? |
|---|---|---|---|
| Estado seleccionado (`ENTREGADO`) | 2 (ids 2, 7) | 2 (ids 2, 7) | **Sí** |
| Producto seleccionado (13896, "Producto 13891") | 5 (ids 1, 2, 20, 26, 240) | 5 (ids 1, 2, 20, 26, 240) | **Sí** |
| *Adicional:* total > 20 000 | 3 (ids 1, 20, 26) | 3 (ids 1, 20, 26) | **Sí** |

La comparación no se hizo a mano. [`tests/test_consultas.sh`](../tests/test_consultas.sh) ejecuta los dos archivos y compara las líneas `RESULTADO`, que salen de las mismas consultas. Además verifica:
- que a) devuelva exactamente los pedidos migrados;
- que la lista literal de pedidos de `consultas_postgresql.sql` sea esa misma;
- que ninguna consulta devuelva 0 pedidos ni los 9.

En `consultas_mongodb.js`, cada filtro se define una sola vez: lo usan tanto la consulta que se muestra como la línea `RESULTADO`.

Para comprobar que el test detecta errores se introdujeron cinco, y los cinco lo hicieron fallar:
- otro estado en MongoDB;
- otro umbral en PostgreSQL;
- quitar la restricción a los pedidos migrados;
- otro producto en MongoDB;
- un id de más en la lista de PostgreSQL. Este último lo señaló la revisión antes del commit: con la primera versión del test pasaba sin ser detectado.

Ver [`evidencias/parte2_tests.txt`](../evidencias/parte2_tests.txt).

### Diferencias detectadas y cómo se resolvieron

1. **Volumen (corregido en la consulta).** La primera versión de las consultas en PostgreSQL recorría toda la tabla `pedido`: 188 745 pedidos `ENTREGADO` y 155 679 con el producto 13896, contra 2 y 5 en MongoDB. No es un error del modelo: en MongoDB está solo el subconjunto migrado. La corrección fue limitar las consultas de PostgreSQL a los 9 pedidos migrados (la vista `migrados`). Las dos versiones quedan en `consultas_postgresql.sql`, para que se vea la diferencia.
2. **Fecha (misma información, distinta representación).** MongoDB muestra `2026-04-10T03:00:00Z` y PostgreSQL `2026-04-10 00:00:00-03`. Es el mismo instante: `timestamptz` se migró a UTC y `psql` lo muestra en la zona de la sesión (Argentina, UTC-3). `test_migracion.sh` lo compara convirtiendo ambos a UTC.
3. **Total (guardado o calculado).** En MongoDB `total` está guardado en el documento. En PostgreSQL no existe la columna y se calcula con `SUM(subtotal)` en cada consulta. Los resultados coinciden porque el validador de MongoDB exige `total = Σ subtotales`. Sin esa regla, un total desactualizado haría que d) diera distinto en los dos motores.
4. **Forma de la consulta c).** En MongoDB es un filtro sobre el arreglo embebido, en un solo documento y sin uniones. En PostgreSQL hace falta unir `pedido`, `pedido_detalle` y `producto`. No hace falta `DISTINCT`, porque la PK `(pedido_id, producto_id)` garantiza una sola fila por pedido. Es el mismo resultado con dos formas de acceso, y esa diferencia es uno de los criterios de la Parte 3.

No hizo falta corregir el modelo: las únicas diferencias venían de la consulta (punto 1) o de la representación de los datos (puntos 2 y 3).
