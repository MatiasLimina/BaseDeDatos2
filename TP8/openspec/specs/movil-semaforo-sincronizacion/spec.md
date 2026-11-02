# movil-semaforo-sincronizacion Specification

## Purpose
Simular la sincronización de la tablet con el servidor: clasificar cada solicitud pendiente con el semáforo (rojo, amarillo, verde) contra la última instantánea, de forma idempotente, sin que la tablet cambie nunca precio, stock ni ventas del servidor.

## Requirements

### Requirement: Rojo – solicitud RECHAZADA
WHEN una solicitud PENDIENTE tiene al menos un ítem cuyo producto no existe en `snapshot_servidor`, no está disponible, fue dado de baja o pide más unidades que el stock de la instantánea, el semáforo SHALL marcarla RECHAZADO con un motivo que identifique el producto y la causa. El rojo SHALL tener prioridad sobre el amarillo.

#### Scenario: C3 – Más unidades que el stock
- **WHEN** un borrador pide `stock + 1` unidades de un producto y se corre el semáforo
- **THEN** su solicitud queda RECHAZADO y el motivo nombra el producto y la falta de stock

#### Scenario: C4 – Producto dado de baja
- **WHEN** después de armar un borrador el producto se da de baja lógica en el servidor, se exporta e importa una instantánea nueva y se corre el semáforo
- **THEN** la solicitud queda RECHAZADO con motivo de baja, aunque el precio también haya cambiado

#### Scenario: Producto inexistente en la instantánea
- **WHEN** un ítem referencia un producto que no está en `snapshot_servidor`
- **THEN** la solicitud queda RECHAZADO con motivo de producto inexistente

#### Scenario: Borrador sin ítems
- **WHEN** una solicitud PENDIENTE corresponde a un borrador sin ítems
- **THEN** la solicitud queda RECHAZADO con motivo de borrador vacío (no queda PENDIENTE para siempre)

### Requirement: Amarillo – solicitud en CONFLICTO
WHEN una solicitud PENDIENTE no cumple ninguna condición de rojo pero al menos un ítem tiene un `precio_centavos_visto` distinto del precio de la instantánea, el semáforo SHALL marcarla CONFLICTO con un motivo que indique el producto, el precio visto y el precio actual.

#### Scenario: C2 – Subió el precio
- **WHEN** después de armar un borrador se sube en el servidor el precio de uno de sus productos, se exporta e importa una instantánea nueva y se corre el semáforo
- **THEN** la solicitud queda CONFLICTO y el motivo muestra ambos precios en centavos

#### Scenario: Bajó el precio
- **WHEN** el precio de la instantánea es menor que el visto
- **THEN** la solicitud también queda CONFLICTO (cualquier diferencia de precio es conflicto)

### Requirement: Verde – SIMULADO_APROBADO que no es una venta
WHEN una solicitud PENDIENTE no cumple ninguna condición de rojo ni de amarillo, el semáforo SHALL marcarla SIMULADO_APROBADO. Ese estado SHALL significar solo que la propuesta coincide con la instantánea: no SHALL crear pedidos, descontar stock ni presentarse como venta en ningún entregable.

#### Scenario: C5 – Borrador sin cambios
- **WHEN** se evalúa un borrador cuyos productos existen, están disponibles, alcanzan el stock y mantienen el precio
- **THEN** la solicitud queda SIMULADO_APROBADO

#### Scenario: Aprobado simulado no crea pedidos
- **WHEN** se compara la cantidad de pedidos de PostgreSQL antes y después de una solicitud SIMULADO_APROBADO
- **THEN** la cantidad es la misma

### Requirement: Solo se evalúan solicitudes pendientes
El semáforo SHALL evaluar solo las solicitudes con estado PENDIENTE y SHALL no modificar las que ya tienen otro estado. Correrlo dos veces seguidas sin solicitudes nuevas SHALL no cambiar ninguna fila. Si `snapshot_servidor` está vacía, el semáforo SHALL no evaluar nada.

#### Scenario: Repetir la simulación no reevalúa
- **WHEN** se corre el semáforo dos veces seguidas
- **THEN** la segunda ejecución modifica 0 filas de `cola_sync`

#### Scenario: Estados finales estables ante una instantánea nueva
- **WHEN** una solicitud ya está CONFLICTO y se importa una instantánea donde el precio volvió al visto
- **THEN** al correr el semáforo esa solicitud sigue CONFLICTO

#### Scenario: Instantánea vacía
- **WHEN** se corre el semáforo con `snapshot_servidor` vacía
- **THEN** las solicitudes PENDIENTE siguen PENDIENTE

### Requirement: Idempotencia por UUID de solicitud (C6)
Reenviar una solicitud con un `solicitud_uuid` ya registrado SHALL fallar por clave primaria sin duplicarla ni cambiar su estado.

#### Scenario: C6 – Reenvío del mismo UUID
- **WHEN** se inserta en `cola_sync` una solicitud con el mismo `solicitud_uuid` que una ya evaluada y luego se corre el semáforo
- **THEN** la inserción falla por clave primaria, `cola_sync` tiene una sola fila con ese UUID y su estado no cambia

### Requirement: Aceptación de un conflicto con una solicitud nueva
Cuando el cliente acepta el precio nuevo, la tablet SHALL actualizar el `precio_centavos_visto` de los ítems del borrador y crear una solicitud nueva (UUID nuevo, PENDIENTE) en una sola transacción. La solicitud en CONFLICTO SHALL quedar como historia.

#### Scenario: C2 – Cliente acepta el precio nuevo
- **WHEN** se actualiza el precio visto del borrador en CONFLICTO al de la instantánea, se crea una solicitud nueva y se corre el semáforo
- **THEN** la solicitud nueva queda SIMULADO_APROBADO y la anterior sigue CONFLICTO

### Requirement: La tablet nunca modifica el servidor
Ninguna operación de la tablet ni del semáforo SHALL escribir en PostgreSQL. Los cambios de datos para preparar C2 y C4 SHALL hacerse solo en la copia de pruebas y revertirse al terminar; al final, la cantidad de pedidos, la suma del stock y la huella del catálogo SHALL ser iguales a la línea base.

#### Scenario: Verificación final en PostgreSQL
- **WHEN** después de correr C2 a C6 y revertir la preparación se ejecuta la consulta de verificación
- **THEN** `count(*)` de `pedido` y `sum(stock)` de `producto` son iguales a los registrados antes de los casos

#### Scenario: Catálogo del servidor restaurado
- **WHEN** se compara la huella de `producto` (id, precio, stock, activo) antes de los casos y después de la restauración
- **THEN** ambas huellas son idénticas
