# ventas-diarias-categoria Specification

## Purpose

Servir el reporte "top 5 de categorías por monto vendido en el día" del panel de administración desde totales diarios por categoría mantenidos de forma redundante, sincronizados con pedidos y detalles, medidos contra la consulta normalizada y auditables contra su fuente de verdad.

## Requirements

### Requirement: Baja lógica de pedidos y detalles
`pedido` y `pedido_detalle` SHALL tener la columna `eliminado BOOLEAN NOT NULL DEFAULT FALSE`. Agregarla SHALL ser idempotente y no SHALL alterar las filas existentes (todas quedan con `eliminado = FALSE`).

#### Scenario: Columna presente con valor por defecto
- **WHEN** se inserta un pedido o un detalle sin indicar `eliminado`
- **THEN** la fila queda con `eliminado = FALSE`

#### Scenario: Valor nulo rechazado
- **WHEN** se intenta asignar `eliminado = NULL` a un pedido o detalle
- **THEN** la base rechaza la operación por `NOT NULL`

### Requirement: Día de negocio con zona horaria fija
"El día" de un pedido SHALL determinarse a partir de `pedido.fecha` (TIMESTAMPTZ) convertida a la zona horaria de negocio `America/Argentina/Buenos_Aires`, de forma idéntica en el mantenimiento, el reporte y la auditoría, sin depender de la zona horaria de la sesión.

#### Scenario: Pedido cercano a medianoche
- **WHEN** existe un pedido a las 23:30 hora de Buenos Aires y se consulta desde una sesión con `TimeZone = 'UTC'`
- **THEN** el pedido se contabiliza en el día de Buenos Aires, no en el día UTC siguiente

### Requirement: Datos de prueba representativos
El script de la Parte 2 SHALL generar con `generate_series` al menos 8 categorías con productos asignados y un volumen de pedidos y detalles con fecha del día de ejecución suficiente para que la consulta original tenga un costo medible.

#### Scenario: Volumen del día cargado
- **WHEN** termina la sección de datos de prueba
- **THEN** existen al menos 8 categorías con ventas en el día de negocio actual y al menos 100 000 detalles no eliminados de pedidos de ese día

### Requirement: Medición baseline de la consulta normalizada
La consulta original del reporte, adaptada al schema real (`pedido_detalle`, filtro por rango del día de negocio, `eliminado = FALSE` en pedido y detalle), SHALL medirse con `EXPLAIN (ANALYZE, BUFFERS)` registrando tiempo de ejecución y nodo dominante del plan.

#### Scenario: Evidencia de baseline registrada
- **WHEN** se ejecuta la medición baseline sobre la base poblada
- **THEN** la salida completa del plan queda guardada como evidencia y el informe cita el tiempo de ejecución y el nodo que domina el costo

### Requirement: Totales diarios por categoría
SHALL existir `ventas_diarias_categoria` con una fila por `(fecha, categoria_id)` con ventas vigentes, cuyo `total_vendido` es la suma de `subtotal` de los detalles no eliminados de pedidos no eliminados de ese día de negocio cuyo producto pertenece actualmente a esa categoría. No SHALL quedar filas sin detalles que las respalden.

#### Scenario: Carga inicial consistente
- **WHEN** se crea la estructura y se ejecuta la carga inicial sobre la base poblada
- **THEN** la auditoría devuelve 0 filas

#### Scenario: Categoría sin ventas restantes
- **WHEN** se dan de baja lógica todos los detalles de una categoría en un día
- **THEN** la fila `(día, categoría)` deja de existir en `ventas_diarias_categoria`

### Requirement: Sincronización ante cambios en detalles
Todo `INSERT`, `UPDATE` (de `subtotal`, `producto_id`, `pedido_id` o `eliminado`) y `DELETE` sobre `pedido_detalle` SHALL reflejarse en `ventas_diarias_categoria` dentro de la misma transacción.

#### Scenario: Alta de detalle
- **WHEN** se inserta un detalle de subtotal 100.00 en un pedido de hoy de un producto de la categoría C
- **THEN** el total de `(hoy, C)` aumenta exactamente 100.00

#### Scenario: Cambio de subtotal
- **WHEN** se modifica el subtotal de un detalle de hoy de 100.00 a 250.00
- **THEN** el total de su categoría para hoy aumenta exactamente 150.00

#### Scenario: Cambio de producto entre categorías
- **WHEN** se cambia el producto de un detalle por otro de distinta categoría
- **THEN** el subtotal se resta de la categoría anterior y se suma a la nueva

#### Scenario: Baja lógica y reactivación de detalle
- **WHEN** se marca `eliminado = TRUE` en un detalle y luego se vuelve a `FALSE`
- **THEN** el total se descuenta y luego se restituye al valor original

#### Scenario: Borrado físico de detalle
- **WHEN** se elimina físicamente un detalle no eliminado
- **THEN** su subtotal se descuenta del total correspondiente

#### Scenario: Rollback no deja residuos
- **WHEN** una transacción inserta detalles y luego hace `ROLLBACK`
- **THEN** `ventas_diarias_categoria` queda igual que antes de la transacción

### Requirement: Sincronización ante cambios en pedidos y productos
Un cambio de `eliminado` o de `fecha` en `pedido` SHALL mover o descontar los totales de todos sus detalles vigentes. Un cambio de `categoria_id` en `producto` SHALL mover sus ventas históricas de la categoría anterior a la nueva para cada día afectado.

#### Scenario: Baja lógica de pedido
- **WHEN** se marca `eliminado = TRUE` en un pedido de hoy con detalles en dos categorías
- **THEN** ambas categorías descuentan los subtotales de ese pedido

#### Scenario: Cambio de fecha de pedido
- **WHEN** se cambia la fecha de un pedido de hoy a ayer
- **THEN** sus subtotales se descuentan de hoy y se suman a ayer en las mismas categorías

#### Scenario: Recategorización de producto
- **WHEN** se cambia la categoría de un producto con ventas en varios días
- **THEN** para cada uno de esos días el monto pasa de la categoría anterior a la nueva y la auditoría devuelve 0 filas

### Requirement: Reporte top 5 desde la estructura desnormalizada
El reporte SHALL obtener el top 5 de categorías del día de negocio actual leyendo `ventas_diarias_categoria` (con, a lo sumo, la unión a `categoria` para el nombre), devolviendo `categoria` y `total_vendido` ordenados de mayor a menor, con el mismo resultado que la consulta normalizada.

#### Scenario: Resultado equivalente al original
- **WHEN** se ejecutan la consulta normalizada y la desnormalizada sobre los mismos datos
- **THEN** devuelven las mismas 5 filas en el mismo orden con los mismos montos

#### Scenario: Mejora medida antes/después
- **WHEN** se mide la consulta desnormalizada con `EXPLAIN (ANALYZE, BUFFERS)`
- **THEN** el informe presenta una tabla antes/después con tiempo de ejecución y nodo dominante de cada plan, y el tiempo después es menor que el baseline

### Requirement: Auditoría de desincronización
SHALL existir un script de auditoría que recalcula los totales por día y categoría desde la fuente de verdad y devuelve una fila por cada `(fecha, categoria_id)` cuyo total difiere, falta en la tabla redundante o sobra en ella.

#### Scenario: Base sincronizada
- **WHEN** se ejecuta la auditoría sobre la base ya migrada
- **THEN** devuelve 0 filas

#### Scenario: Desincronización detectada
- **WHEN** dentro de una transacción revertida se modifica a mano `total_vendido` de una fila con los disparadores intactos
- **THEN** la auditoría devuelve exactamente esa fila

### Requirement: Reversibilidad sin pérdida
La desnormalización SHALL poder retirarse eliminando disparadores, funciones y la tabla `ventas_diarias_categoria` sin modificar ni perder datos de `pedido`, `pedido_detalle`, `producto` ni `categoria`.

#### Scenario: Retiro de la estructura
- **WHEN** se ejecuta el bloque de reversión dentro de una transacción
- **THEN** la consulta normalizada devuelve el mismo resultado que antes y no queda ningún disparador de sincronización
