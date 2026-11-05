# Requisitos: tablet con SQLite y sincronización simulada (TP8)

> Nota: estos documentos se derivan de OpenSpec (`openspec/changes/tp8-tablet-sqlite-sync/`) porque el equipo no usó Kiro. Mantienen el formato de tres archivos de Kiro (`requirements.md`, `design.md`, `tasks.md`).

## Alcance

La tablet de ventas trabaja sin conexión con una base SQLite. La sincronización es una simulación: la tablet evalúa sus solicitudes contra una instantánea (S0) del servidor, copiada desde la vista `v_snapshot_movil` de `food_store_copia`. La tablet no modifica PostgreSQL. `SIMULADO_APROBADO` no es una venta: no se crea ningún pedido y el stock del servidor no cambia.

En SQLite no hay tabla de clientes ni datos personales. El campo `usuario` es un alias.

El semáforo evalúa solo las filas de `cola_sync` en estado `PENDIENTE`. El rojo (`RECHAZADO`) gana sobre el amarillo (`CONFLICTO`).

Motivos que genera `movil/semaforo.sql`: `borrador vacio`; `producto N: no existe en el servidor`; `producto N: dado de baja`; `producto N: no disponible`; `producto N: pide X, stock Y`; `producto N: precio visto X, actual Y`.

## REQ-01: Precio distinto

Como vendedor, quiero que la tablet me avise si el precio cambió en el servidor, para no cerrar el pedido con un precio viejo.

- WHEN el precio actual de algún ítem es distinto del precio visto y no hay causa de rechazo THE SYSTEM SHALL marcar la solicitud como `CONFLICTO`.
- WHEN el precio es distinto, sea más alto o más bajo, THE SYSTEM SHALL guardar el motivo `producto N: precio visto X, actual Y`.
- WHEN el vendedor acepta el precio nuevo THE SYSTEM SHALL actualizar el precio visto del ítem y crear una solicitud nueva (UUID nuevo) que termina en `SIMULADO_APROBADO`.

Se prueba con: C2

Evidencia: `evidencias/c2_conflicto.txt`, `evidencias/c2_aceptado.txt`. Scripts: `movil/casos/c2_borrador.sql`, `movil/casos/c2_aceptar.sql`.

## REQ-02: Cantidad mayor al stock

Como vendedor, quiero que la tablet rechace un pedido que pide más de lo que hay, para no prometer mercadería que no existe.

- WHEN algún ítem pide más unidades que el stock de la instantánea THE SYSTEM SHALL marcar la solicitud como `RECHAZADO`.
- WHEN se rechaza por stock THE SYSTEM SHALL guardar el motivo `producto N: pide X, stock Y` (en el caso: pide 5, stock 4).

Se prueba con: C3

Evidencia: `evidencias/c3_rechazado.txt`. Script: `movil/casos/c3_borrador.sql`.

## REQ-03: Producto dado de baja

Como vendedor, quiero que un producto dado de baja en el servidor no se pueda vender, para no armar pedidos con algo que ya no existe.

- WHEN un producto del borrador fue dado de baja en el servidor THE SYSTEM SHALL marcar la solicitud como `RECHAZADO` con el motivo `producto N: dado de baja`.
- WHEN la instantánea trae un producto dado de baja THE SYSTEM SHALL conservar la fila en `producto_cache` con `eliminado = 1` (lápida) y sacarla del catálogo disponible.

Se prueba con: C4

Evidencia: `evidencias/c4_rechazado.txt`. Script: `movil/casos/c4_borrador.sql`.

## REQ-04: Todo coincide

Como vendedor, quiero saber cuándo un pedido está en condiciones de enviarse, sin que eso cierre una venta.

- WHEN todos los ítems coinciden con la instantánea en disponibilidad, stock y precio THE SYSTEM SHALL marcar la solicitud como `SIMULADO_APROBADO`.
- WHEN una solicitud queda en `SIMULADO_APROBADO` THE SYSTEM SHALL dejar PostgreSQL sin cambios: no se crea ningún pedido y el stock del servidor es el mismo.

`SIMULADO_APROBADO` no es una venta.

Se prueba con: C5

Evidencia: `evidencias/c5_aprobado.txt`, `evidencias/verificacion_final_diff.txt`. Script: `movil/casos/c5_c6.sql`.

## REQ-05: Mismo UUID otra vez

Como vendedor, quiero que reenviar una solicitud no la duplique ni la vuelva a evaluar.

- WHEN se inserta en `cola_sync` una solicitud con un UUID ya registrado THE SYSTEM SHALL rechazarla por clave primaria y no agregar filas.
- WHEN el semáforo se corre otra vez sobre solicitudes ya evaluadas THE SYSTEM SHALL dejarlas como están (`changes() = 0`), porque solo evalúa `PENDIENTE`.

Se prueba con: C6

Evidencia: `evidencias/c6_reintento.txt`, `evidencias/c6_semaforo_idempotente.txt`. Script: `movil/casos/c5_c6.sql`.

## REQ-06: Catálogo sin conexión

Como vendedor, quiero ver el catálogo aunque no haya internet.

- WHEN no hay conexión con el servidor THE SYSTEM SHALL listar el catálogo disponible desde `producto_cache`, sin filas con `disponible = 0` ni `eliminado = 1`.

Se prueba con: C1

Evidencia: `evidencias/c1_c7_pruebas_sqlite.txt`.

## REQ-07: Ítem inválido

Como vendedor, quiero que la base local no acepte ítems sin sentido.

- WHEN un ítem tiene cantidad 0 THE SYSTEM SHALL rechazarlo con error y no dejar filas nuevas.
- WHEN un ítem referencia un producto inexistente THE SYSTEM SHALL rechazarlo con error (clave foránea) y no dejar filas nuevas.

Se prueba con: C7

Evidencia: `evidencias/c1_c7_pruebas_sqlite.txt`.
