# Parte 3 — Contraste de la IA y conclusión

La consulta a la IA (Consigna 6) está en [`ia/consulta_ia.md`](ia/consulta_ia.md): el prompt literal, una síntesis y la [respuesta completa](ia/consulta_ia_respuesta.txt). La IA recomendó **combinar tecnologías**: PostgreSQL como fuente de verdad y MongoDB, si hiciera falta, solo como vista de lectura derivada.

## Consigna 7 — Dos afirmaciones contrastadas

Evidencia del laboratorio: [`evidencias/parte3_contraste_mongodb.txt`](../evidencias/parte3_contraste_mongodb.txt) y [`evidencias/parte3_lectura_pedido_completo.txt`](../evidencias/parte3_lectura_pedido_completo.txt). La documentación oficial se consultó el 01/11/2026.

### Afirmación 1 — "Coherencia precio, subtotal y total: solo por código de aplicación"

**Qué dijo la IA.** Según la IA, `$jsonSchema` "no puede expresar relaciones entre campos como `subtotal == cantidad × precio` ni `total == suma(subtotales)`". Por eso, en MongoDB esa coherencia quedaría solo a cargo de la aplicación.

**Veredicto: incorrecta en lo que importa.** Es cierto que las palabras clave de `$jsonSchema` comparan contra valores fijos, no entre campos. La conclusión, en cambio, es falsa: el validador de una colección no se limita a `$jsonSchema`.

- **Documentación oficial.** En [Specify Validation With Query Operators](https://www.mongodb.com/docs/manual/core/schema-validation/specify-query-expression-rules/):
  - el manual dice que se pueden usar operadores de consulta "to compare fields", es decir, para comparar campos entre sí;
  - su ejemplo es una colección de pedidos que solo acepta documentos con `totalWithVAT = total * (1 + VAT)`;
  - la misma página explica que esa validación se combina con la de JSON Schema.
- **Laboratorio.** El validador de `foodstore.pedidos` (Parte 1) combina `$jsonSchema` con cláusulas `$expr` y rechazó con el error 121 estos tres intentos:
  - un insert con un subtotal distinto de `cantidad × precio` (3 × 2218,29 ≠ 9999,99);
  - un insert con un total distinto de la suma de los subtotales;
  - un `updateOne` que intentaba desincronizar el total de un pedido ya guardado. El total quedó en 14 249,69.
  - Además, `tests/test_migracion.sh` prueba 10 violaciones y verifica que cada una la rechace su propia regla.
- **Lo que la IA sí acierta.** MongoDB no tiene claves foráneas ("Sin FK"): no puede comprobar que `cliente.id` o `producto.id` existan.
- **Límites que agrega el equipo, y que la IA no mencionó.**
  - El validador se puede saltear con `bypassDocumentValidation`.
  - Solo controla cada documento por separado, no reglas entre documentos.

### Afirmación 2 — "Las transacciones multi-documento existen desde la 4.0, pero son más costosas"

**Qué dijo la IA.** En su tabla, la "transacción pedido + stock" en MongoDB figura como "Posible, más costosa".

**Veredicto: correcta pero incompleta. La omisión es justo la que afecta al laboratorio.**

- **Documentación oficial.** En [Production Considerations](https://www.mongodb.com/docs/manual/core/transactions-production-consideration/):
  - el manual exige un `featureCompatibilityVersion` mínimo de 4.0 para conjuntos de réplicas y de 4.2 para clústeres fragmentados. La IA acierta con la versión;
  - la misma página aclara que una instalación **standalone no admite transacciones** y que hace falta un conjunto de réplicas.
- **Costo.** [Transactions](https://www.mongodb.com/docs/manual/core/transactions/) confirma que una transacción distribuida suele costar más que escribir un solo documento. Agrega que en muchos casos el modelo desnormalizado, con documentos y arreglos embebidos, sigue siendo el óptimo.
- **Laboratorio.** El MongoDB del TP es standalone (`hello()` sin `setName`).
  - Con `mongosh`, la sesión falla en el propio driver: *"This MongoDB deployment does not support retryable writes"*.
  - Enviado el comando directo al servidor, la respuesta es `code 20 IllegalOperation`, *"Transaction numbers are only allowed on a replica set member or mongos"*.
  - Para "pedido + stock", lo que la IA llama "posible" es imposible con la infraestructura del laboratorio. Habría que montar un conjunto de réplicas.
- **Matiz a favor del modelo.** Grabar el pedido no necesita transacción: cabecera, líneas y total están en un solo documento, y en MongoDB la operación sobre un documento es atómica. La transacción solo hace falta si se actualiza también otra colección, como el stock.

### Afirmación que se confirmó

La IA dijo que "el diferencial de rendimiento de MongoDB en la lectura (evitar 3 JOIN indexados) es pequeño a una escala típica de tienda". Se midió con el pedido 2, con los datos ya en memoria por cuatro lecturas previas:

| Motor | Plan | Ejecución |
|---|---|---|
| PostgreSQL | 5 índices (pedido, cliente, `pedido_detalle`, producto, categoría), 7 búsquedas y 25 bloques leídos | 0,32 ms |
| MongoDB | `EXPRESS_IXSCAN` por `_id`: 1 clave y 1 documento | < 1 ms |

Cada ejecución de `psql` abre una conexión nueva. Por eso la planificación del `EXPLAIN` (10,6 ms) incluye cargar la caché de catálogo de esa conexión. Una aplicación con conexiones persistentes y sentencias preparadas no la paga en cada lectura.

## Conclusión

*(199 palabras)*

Conviene **mantener PostgreSQL como fuente de verdad de los pedidos** y usar MongoDB, si hiciera falta, solo como copia de lectura derivada de PostgreSQL. Se llega a la misma recomendación que la IA, pero por razones corregidas.

**Primer criterio: integridad y atomicidad.** MongoDB pudo validar dentro de cada documento lo que la IA creía imposible: `subtotal = cantidad × precio`, `total = Σ subtotales` y producto sin repetir. Lo que no puede hacer es garantizar las relaciones entre documentos. No tiene claves foráneas, y la operación conjunta "pedido + stock" requiere transacciones, que el MongoDB standalone del laboratorio rechazó (código 20). PostgreSQL ofrece las dos cosas en cualquier instalación.

**Segundo criterio: patrón de acceso.** El documento embebido resuelve el pedido completo con una sola lectura. Pero PostgreSQL lo hizo en 0,32 ms usando cinco índices. A esta escala, la ventaja no justifica un segundo motor.

**Tercer criterio: duplicación.** Embeber al cliente copia sus datos en cada pedido. Como foto histórica sirve, pero cualquier dato que deba estar al día obligaría a reescribir documentos: el cliente 4812 tiene 200 000 pedidos. En PostgreSQL es una fila.

La combinación solo se justificaría con mucho tráfico de lectura de pedidos cerrados, que no cambian.
