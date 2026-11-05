# Consigna 6 — Consulta a una herramienta de IA

- **Herramienta:** agente de IA aislado (Claude Sonnet), lanzado desde Claude Code el 01/11/2026.
- **Aislamiento:** no tuvo acceso a esta conversación, al repositorio ni a la base. Se le pidió que respondiera solo con su conocimiento, sin herramientas: sin leer archivos, sin búsquedas web y sin ejecutar comandos.
- **Contrastación:** la hizo el equipo en [`../contraste_ia.md`](../contraste_ia.md), con la documentación oficial y los resultados del laboratorio.

## Prompt enviado (literal)

> Respondé únicamente con tu conocimiento. No uses ninguna herramienta (no leas archivos, no busques en la web, no ejecutes comandos). Respondé en español, en no más de 700 palabras.
>
> Estoy diseñando el almacenamiento de pedidos de "Food Store", una tienda de comida online. Hoy los datos están en PostgreSQL con un modelo relacional normalizado: pedido(id, fecha, estado, forma_pago, cliente_id → cliente), pedido_detalle(pedido_id, producto_id, cantidad, precio_unitario histórico, subtotal; clave primaria compuesta pedido_id + producto_id), producto(id, nombre, precio, stock, categoria_id) y cliente(id, nombre, apellido, email único), con restricciones CHECK de cantidad > 0 y precios ≥ 0 y claves foráneas entre las tablas. El acceso más frecuente es leer pedidos completos (cabecera, datos del cliente y todas sus líneas). Es indispensable conservar la coherencia de cantidades y precios: el precio unitario histórico de cada línea, el subtotal y el total del pedido no pueden quedar inconsistentes. Compará PostgreSQL y MongoDB para almacenar y consultar estos pedidos: ventajas y desventajas de cada uno, cómo modelarías los pedidos en MongoDB y qué recomendarías (mantener PostgreSQL, migrar a MongoDB o combinar tecnologías). Justificá con criterios técnicos concretos.

El prompt menciona los tres elementos que exige la consigna:
- el modelo actual;
- el acceso frecuente a pedidos completos;
- la necesidad de conservar la coherencia de cantidades y precios.

## Respuesta recibida

**Síntesis.** La IA recomendó **combinar tecnologías**:
- PostgreSQL como fuente de verdad y sistema de registro transaccional;
- MongoDB solo si aparece una necesidad concreta, y nunca para escrituras: como una vista de lectura derivada, alimentada desde PostgreSQL;
- si el volumen no lo exige, mantener solo PostgreSQL.

El criterio decisivo fue la coherencia de cantidades y precios. Según la IA, PostgreSQL la garantiza en el motor y MongoDB solo en el código de la aplicación.

**Afirmaciones más concretas**, con sus palabras:
- Sobre el validador de MongoDB: `$jsonSchema` "**no** puede expresar relaciones entre campos como `subtotal == cantidad × precio` ni `total == suma(subtotales)`". En su tabla comparativa, la coherencia entre precio, subtotal y total en MongoDB figura como "Solo por código de aplicación".
- Sobre las transacciones: "las transacciones multi-documento existen desde la 4.0, pero son más costosas y menos idiomáticas". En su tabla, la transacción entre el pedido y el stock figura como "Posible, más costosa".
- Sobre la lectura del pedido completo: en MongoDB es "una lectura, más rápida", y en PostgreSQL un "JOIN indexado, rápido". Según la IA, "el diferencial de rendimiento de MongoDB en la lectura (evitar 3 JOIN indexados) es pequeño a una escala típica de tienda".

**Modelo que propuso en MongoDB:**
- colección `pedidos` con el cliente embebido como copia histórica y las líneas embebidas;
- `producto` en una colección aparte, referenciado por id;
- `Decimal128` para los importes;
- validador `$jsonSchema` para tipos y rangos;
- índices por cliente y fecha, y por estado.

La respuesta completa, sin cambios, está en [`consulta_ia_respuesta.txt`](consulta_ia_respuesta.txt).
