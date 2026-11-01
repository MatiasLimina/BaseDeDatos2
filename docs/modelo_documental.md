# Parte 1 — Modelo documental y migración

Food Store real del equipo: base `foodstore` en PostgreSQL 17.11, cargada en el TP6 con el esquema del proyecto integrador. MongoDB 9.0.4 local (`localhost:27017`).

## Consigna 1 — Subconjunto "pedidos y detalle de pedidos"

### Tablas y claves que intervienen en PostgreSQL

Evidencia: [`evidencias/parte1_postgresql_claves.txt`](../evidencias/parte1_postgresql_claves.txt).

| Tabla | Clave primaria | Claves foráneas y únicas | Restricciones relevantes |
|---|---|---|---|
| `pedido` | `id` | `cliente_id → cliente(id)` | `estado estado_pedido_enum NOT NULL DEFAULT 'PENDIENTE'` (agregado en este TP, ver abajo), `forma_pago forma_pago_enum` |
| `pedido_detalle` | `(pedido_id, producto_id)` | `pedido_id → pedido(id)`, `producto_id → producto(id)` | `cantidad > 0`, `precio_unitario >= 0`, `subtotal >= 0` |
| `cliente` | `id` | `email` UNIQUE | — |
| `producto` | `id` | `categoria_id → categoria(id)` | `precio >= 0`, `stock >= 0` |
| `categoria` | `id` | `nombre` UNIQUE | — |

`pedido_detalle` es la tabla intermedia de la relación N:M entre pedido y producto (regla R3) y guarda el **precio unitario histórico** (regla R4). `pedido` no tiene columna de total: el total es la suma de los subtotales.

**`estado` agregado.** La consigna pide documentos con estado y una consulta por estado, pero la tabla `pedido` de este Food Store no lo tenía. El equipo decidió agregarlo a la base relacional, para que los dos motores trabajen con los mismos datos. Lo hace [`sql/00_estado_pedido.sql`](../sql/00_estado_pedido.sql), probado con [`sql/test_estado_pedido.sql`](../sql/test_estado_pedido.sql). Antes de aplicarlo se tomó un respaldo con el script del TP6.

**Procedencia de los estados.** Los pedidos son datos sintéticos de los TP 3 y 4. El estado se asignó con una regla determinista según la fecha, contra un corte fijo (29/10/2026):
- menos de 12 h: PENDIENTE;
- entre 12 h y 1 día: EN_PREPARACION;
- entre 1 y 3 días: ENVIADO;
- más antiguos: ENTREGADO, salvo uno de cada veinte (`id % 20 = 0`), que queda CANCELADO.

### Subconjunto migrado

[`sql/01_seleccion_pedidos.sql`](../sql/01_seleccion_pedidos.sql) aplica una regla determinista sobre el lote original de pedidos (`id <= 200001`): **por cada estado, el pedido de menor id que contiene el producto 13896 ("Producto 13891") y el de menor id que no lo contiene.** El límite de ids congela el subconjunto. Sin él, un pedido nuevo (que nace PENDIENTE) podía cambiarlo y dejar de coincidir con lo migrado. Se probó con un insert revertido. Así quedan **9 pedidos**, que cubren los cinco estados, con 5 pedidos con el producto y 4 sin él. PENDIENTE tiene un solo pedido en toda la base. Son pedidos existentes: no hubo que agregar pedidos de prueba.

| `_id` | Estado | Contiene 13896 | Líneas | Total |
|---|---|---|---|---|
| 1 | PENDIENTE | sí | 5 | 24 782,73 |
| 2 | ENTREGADO | sí | 3 | 14 249,69 |
| 7 | ENTREGADO | no | 3 | 14 148,98 |
| 20 | CANCELADO | sí | 4 | 21 210,34 |
| 26 | ENVIADO | sí | 4 | 22 611,17 |
| 120 | CANCELADO | no | 3 | 16 136,83 |
| 217 | ENVIADO | no | 2 | 8 491,21 |
| 240 | EN_PREPARACION | sí | 4 | 19 782,73 |
| 10167 | EN_PREPARACION | no | 3 | 13 918,54 |

**Hallazgos sobre los datos de origen**, que se usan en la Parte 3:
- Los 200 000 pedidos generados son **todos del mismo cliente (4812)**. Solo el pedido 1, del seed, es de otro (cliente 1).
- Cuatro productos aparecen en unos 155 000 pedidos cada uno (el 78 %).
- En las 621 853 líneas el precio histórico coincide con el precio actual del producto.

### Esquema de la colección `foodstore.pedidos`

Un documento por pedido:

```js
{
  _id: 2,                                   // pedido.id (identificador de origen conservado)
  fecha: ISODate("2026-04-10T03:00:00Z"),   // pedido.fecha (timestamptz → fecha UTC)
  estado: "ENTREGADO",                      // pedido.estado
  forma_pago: "TRANSFERENCIA",              // pedido.forma_pago
  cliente: {                                // objeto EMBEBIDO: datos esenciales del cliente
    id: 4812,                               //   cliente.id conservado
    nombre: "Usuario4809", apellido: "Apellido4809", email: "usuario4809@test.com"
  },
  lineas: [                                 // ARREGLO embebido: una entrada por fila de pedido_detalle
    { producto: { id: 9443, nombre: "Producto 9438", categoria: "Bebidas" },  // producto.id conservado
      cantidad: 3,
      precio_unitario: Decimal128("2218.29"),  // precio HISTÓRICO (pedido_detalle), no el actual
      subtotal: Decimal128("6654.87") },
    // ...
  ],
  total: Decimal128("14249.69")             // suma de los subtotales (calculado al migrar)
}
```

Se conservan los identificadores `pedido.id` (como `_id`), `cliente.id` y `producto.id`.

Los importes van en `Decimal128`, que tiene aritmética decimal exacta. Un `double` introduciría errores de redondeo en precios y totales. `Decimal128` admite más decimales, valores más grandes e `Infinity`, que `NUMERIC(10,2)` no acepta. Por eso el validador limita los importes al rango de `NUMERIC(10,2)` (de 0 a 99 999 999,99) y el precio a 2 decimales.

## Consigna 2 — Base, colección y migración

1. [`mongodb/01_crear_coleccion.js`](../mongodb/01_crear_coleccion.js) crea la base `foodstore` y la colección `pedidos`, con su validador y los índices de la Parte 2: `estado`, `lineas.producto.id` (índice sobre el arreglo, multikey) y `total`.
2. [`migracion/generar_insert_pedidos.sql`](../migracion/generar_insert_pedidos.sql) genera desde PostgreSQL el archivo [`mongodb/02_insert_pedidos.js`](../mongodb/02_insert_pedidos.js), con la instrucción `insertMany()` de los 9 pedidos y sus 31 líneas. Los valores se copian de la base, no se transcriben a mano. Los textos se escapan con `to_json()`.
3. Al ejecutar `02_insert_pedidos.js` con `mongosh`, la salida es `pedidos insertados: 9`.

Evidencia: [`evidencias/parte1_coleccion.txt`](../evidencias/parte1_coleccion.txt). Muestra la colección, los índices, la configuración del validador, un documento completo, el resumen de los 9 pedidos y un insert inválido rechazado (código 121).

**Verificación.** [`tests/test_migracion.sh`](../tests/test_migracion.sh) compara los dos motores:
- que tengan los mismos ids;
- **línea por línea**, el estado, la fecha, la forma de pago, el cliente, el producto, la cantidad, el precio, el subtotal y el total;
- que todos los importes sean `Decimal128`;
- que el validador rechace 10 documentos inválidos, **cada uno por la regla que corresponde**. Cada caso rompe una sola regla: recalcula el subtotal y el total cuando hace falta. El test comprueba qué cláusula del validador falló (`errInfo.details`) y, en el `$jsonSchema`, el campo y el operador.

Ciclo seguido:
- **RED:** el test falló con la colección vacía.
- **GREEN:** pasó después de migrar.
- **Mutaciones:** cada una hizo fallar el test:
  - quitar del validador la regla del total;
  - quitar la regla del subtotal;
  - quitar la del producto único;
  - quitar el mínimo de cantidad;
  - quitar el mínimo de los importes;
  - quitar el máximo de los importes;
  - quitar la regla de los 2 decimales;
  - alterar un estado en la migración.

**Defectos encontrados en la revisión antes del commit.** Un agente revisor de solo lectura encontró dos casos del test (cantidad 0 y precio negativo) que **pasaban aunque se quitara su regla**. Al cambiar un solo campo, rompían también la regla `subtotal = cantidad × precio`, y el validador los rechazaba por esa. Se rehicieron para que cada caso aísle su regla.

Al ajustar los casos apareció un segundo problema: la regla de decimales controlaba tres importes y dos eran redundantes. Quitar dos de los tres controles no hacía fallar el test. Se dejó solo el control del precio, porque el subtotal y el total quedan con 2 decimales por las reglas aritméticas.

## Consigna 3 — Reglas de integridad y qué se embebe

### Dos reglas que se conservan en la migración

1. **El precio de cada línea es el histórico y es coherente con el total** (reglas R4 y R5).
   - `precio_unitario` se copia de `pedido_detalle`, nunca de `producto.precio`. Si un producto cambia de precio, los pedidos ya hechos no cambian.
   - En MongoDB, el validador exige:
     - `cantidad >= 1`;
     - `precio_unitario >= 0`, con 2 decimales como máximo;
     - importes dentro del rango de `NUMERIC(10,2)`;
     - `subtotal = cantidad × precio_unitario` en cada línea;
     - `total = Σ subtotales`.
   - Todo se guarda en `Decimal128`, con aritmética exacta.
   - **Límite:** en estos datos el precio histórico coincide con el actual en todas las líneas, así que no hay ningún caso que muestre la diferencia. La regla está garantizada por cómo se escribió la migración, no por un caso de prueba.
2. **Cada pedido conserva su identidad y sus referencias** (PK y FK).
   - `_id = pedido.id` impide duplicar un pedido: es la PK.
   - `cliente.id` y `producto.id` conservan las referencias a las entidades de origen.
   - El validador impide que un producto se repita dentro de un pedido, lo mismo que la PK compuesta `(pedido_id, producto_id)`. También exige al menos una línea por pedido y que estado y forma de pago estén dentro de los valores de sus enums.
   - **Límite:** MongoDB no tiene claves foráneas, así que no puede comprobar que `cliente.id` o `producto.id` existan. Esa garantía queda en PostgreSQL.

El validador usa `validationLevel: "strict"` y `validationAction: "error"`: los documentos que no cumplen se rechazan, no solo se informan.

### Qué se embebe y por qué

- **Líneas del pedido (arreglo embebido).**
  - Pertenecen a un único pedido: no se comparten ni se consultan sueltas.
  - Son pocas (de 1 a 5 por pedido) y no crecen después de cerrado el pedido.
  - El acceso frecuente es "el pedido completo". Embeberlas lo resuelve en una sola lectura, sin el `JOIN` de tres tablas que hace falta en PostgreSQL.
  - Es el caso típico de relación "contiene" uno a pocos que la documentación de MongoDB recomienda embeber.
- **Datos esenciales del cliente y del producto (copia embebida, con su id).**
  - Se guarda lo necesario para mostrar el pedido (nombre, email, nombre del producto, categoría) **tal como estaba al momento de la venta**, igual que el precio histórico.
  - Se mantiene el id para poder ir a la entidad completa.
- **Qué no se embebe.**
  - El resto del cliente (teléfono, estado activo) y del producto (precio actual, stock) cambia independientemente de los pedidos, y en Food Store lo administra PostgreSQL.
  - Copiarlo en cada pedido obligaría a actualizar muchos documentos ante cada cambio. Con estos datos el caso extremo es real: el cliente 4812 aparece en 200 000 pedidos.
