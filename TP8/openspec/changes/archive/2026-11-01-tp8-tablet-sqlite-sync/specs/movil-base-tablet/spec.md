# Spec Delta

## Purpose

Base SQLite de la tablet del food truck: guarda una copia del catálogo y los borradores de pedido con sus solicitudes de sincronización, funciona sin conexión al servidor y rechaza datos inválidos sin dejar filas a medias.

## ADDED Requirements

### Requirement: Esquema de la tablet creado desde cero con integridad activa
El script de esquema SHALL empezar con `PRAGMA foreign_keys = ON;` y crear desde cero, en modo STRICT, `producto_cache`, `pedido_borrador`, `item_borrador` y `cola_sync`. Re-ejecutarlo sobre una base existente SHALL dejar el mismo esquema vacío sin errores. Toda sesión que escriba en la base (pruebas, carga, semáforo, casos) SHALL activar las claves foráneas, porque el PRAGMA vale solo para la conexión que lo ejecuta.

#### Scenario: Creación desde un archivo inexistente
- **WHEN** se ejecuta el script de esquema sobre un archivo `.db` que no existe
- **THEN** la base queda con las cuatro tablas, cada una declarada STRICT, y `PRAGMA foreign_key_check` no devuelve filas

#### Scenario: Re-ejecución
- **WHEN** el script de esquema se ejecuta dos veces seguidas sobre la misma base
- **THEN** la segunda ejecución termina sin errores y las tablas quedan vacías y con la misma definición

#### Scenario: Claves foráneas activas en cada sesión de escritura
- **WHEN** cualquier script que escribe en la base consulta `PRAGMA foreign_keys`
- **THEN** obtiene `1`

### Requirement: Caché de productos en centavos con banderas binarias
`producto_cache` SHALL guardar por producto su id del servidor, nombre, `precio_centavos` (entero, no negativo), `stock_visto` (entero, no negativo), `disponible` y `eliminado` (solo 0 o 1) y la fecha de la copia. El tipo STRICT SHALL rechazar precios con decimales o texto en columnas enteras.

#### Scenario: Precio negativo rechazado
- **WHEN** se inserta un producto con `precio_centavos = -1`
- **THEN** la base rechaza la fila por el `CHECK`

#### Scenario: Bandera fuera de dominio rechazada
- **WHEN** se inserta un producto con `disponible = 2` o con `eliminado = 't'`
- **THEN** la base rechaza la fila (por `CHECK` o por tipo STRICT)

#### Scenario: Precio con decimales rechazado
- **WHEN** se inserta un producto con `precio_centavos = 12.5`
- **THEN** la base rechaza la fila porque la columna STRICT es entera

### Requirement: Borrador de pedido con identificador UUID y forma de pago cerrada
`pedido_borrador` SHALL identificar cada borrador con un `id_local` UUID en texto canónico (36 caracteres, hexadecimal en minúsculas con guiones) y registrar usuario (alias inventado, nunca datos personales reales), forma de pago y fecha. La forma de pago SHALL ser solo EFECTIVO, TARJETA o TRANSFERENCIA.

#### Scenario: Forma de pago no permitida en la tablet
- **WHEN** se inserta un borrador con `forma_pago = 'OTRO'`
- **THEN** la base rechaza la fila aunque `OTRO` exista en el enumerado del servidor

#### Scenario: Identificador que no es UUID
- **WHEN** se inserta un borrador con `id_local = 'pedido-1'`
- **THEN** la base rechaza la fila por el `CHECK` de formato

### Requirement: Ítems del borrador con referencias válidas y cantidad positiva
`item_borrador` SHALL referenciar un borrador existente y un producto existente en `producto_cache`, con `cantidad > 0` y el `precio_centavos_visto` (entero no negativo) que la tablet mostró. Un mismo producto SHALL aparecer una sola vez por borrador.

#### Scenario: Producto repetido en el mismo borrador
- **WHEN** se agrega dos veces el mismo producto al mismo borrador
- **THEN** la base rechaza la segunda fila por clave primaria

#### Scenario: Ítem de un borrador inexistente
- **WHEN** se inserta un ítem con un `id_local` que no está en `pedido_borrador`
- **THEN** la base rechaza la fila por clave foránea

### Requirement: Cola de sincronización con estados cerrados
`cola_sync` SHALL tener `solicitud_uuid` como clave primaria, referenciar el borrador (`id_local`) y guardar `estado` y `motivo`. El estado SHALL ser solo PENDIENTE, CONFLICTO, RECHAZADO o SIMULADO_APROBADO, y una solicitud nueva SHALL nacer PENDIENTE.

#### Scenario: Estado inválido
- **WHEN** se inserta una solicitud con `estado = 'APROBADO'`
- **THEN** la base rechaza la fila por el `CHECK`

#### Scenario: Estado inicial
- **WHEN** se inserta una solicitud sin indicar el estado
- **THEN** la fila queda con `estado = 'PENDIENTE'`

### Requirement: Borrador completo guardado de forma atómica
Guardar un borrador completo (borrador + ítems + solicitud) SHALL hacerse en una única transacción: o quedan todas sus filas o ninguna. Una operación deshecha con `ROLLBACK` SHALL no dejar filas.

#### Scenario: Borrador confirmado con COMMIT
- **WHEN** se ejecuta `BEGIN`, se insertan el borrador, sus ítems y su solicitud y se ejecuta `COMMIT`
- **THEN** las tres tablas tienen las filas nuevas y la solicitud está PENDIENTE

#### Scenario: Operación deshecha con ROLLBACK
- **WHEN** se ejecuta `BEGIN`, se insertan un borrador y un ítem y se ejecuta `ROLLBACK`
- **THEN** la cantidad de filas de `pedido_borrador`, `item_borrador` y `cola_sync` es la misma que antes del `BEGIN`

### Requirement: Catálogo disponible consultable sin servidor (C1)
La tablet SHALL poder listar el catálogo disponible (`disponible = 1` y `eliminado = 0`) leyendo solo su archivo SQLite, sin ninguna conexión a PostgreSQL.

#### Scenario: C1 – Catálogo offline
- **WHEN** se copia `foodstore_movil.db` a una carpeta aislada y se ejecuta la consulta del catálogo con sqlite3, sin acceso a PostgreSQL
- **THEN** la consulta devuelve los productos disponibles y no dados de baja de la última instantánea cargada, con su precio en centavos

#### Scenario: Productos no disponibles excluidos
- **WHEN** el caché tiene productos con `disponible = 0` o `eliminado = 1`
- **THEN** ninguno aparece en el catálogo disponible

### Requirement: Datos inválidos no dejan filas nuevas (C7)
Un ítem con cantidad 0 o con un producto inexistente SHALL producir un error y, al deshacer el borrador en curso, SHALL no quedar ninguna fila nueva en ninguna tabla de la tablet.

#### Scenario: C7 – Cantidad en cero
- **WHEN** dentro de un borrador en curso se inserta un ítem con `cantidad = 0` y se deshace el borrador
- **THEN** la inserción falla por el `CHECK` y los conteos de las cuatro tablas son los mismos que antes

#### Scenario: C7 – Producto inexistente
- **WHEN** se inserta un ítem con un `producto_id` que no existe en `producto_cache`
- **THEN** la inserción falla por clave foránea y los conteos de las cuatro tablas son los mismos que antes
