# Diseño: tablet con SQLite y sincronización simulada (TP8)

> Nota: estos documentos se derivan de OpenSpec (`openspec/changes/tp8-tablet-sqlite-sync/`) porque el equipo no usó Kiro. Mantienen el formato de tres archivos de Kiro. Las decisiones salen del `design.md` de ese change.

## Flujo

1. Se exporta S0 (la instantánea) en CSV desde la vista `v_snapshot_movil` de `food_store_copia` (`sql/02_exportar_snapshot.sql`).
2. Se importa en SQLite (`movil/importar_snapshot.sql`): primero a `snapshot_servidor` y después, con un upsert, a `producto_cache`.
3. La tablet arma borradores (`pedido_borrador` e `item_borrador`).
4. Cada envío crea una fila `PENDIENTE` en `cola_sync`.
5. El semáforo (`movil/semaforo.sql`) evalúa las `PENDIENTE` contra `snapshot_servidor`.

De SQLite no vuelve nada al servidor.

## Tablas de SQLite (`movil/schema_sqlite.sql`)

Todas son `STRICT`. El script empieza con `PRAGMA foreign_keys = ON`. Ese PRAGMA vale por conexión.

| Tabla | Para qué sirve | Restricciones principales |
|---|---|---|
| `producto_cache` | Catálogo local. | Precio en centavos enteros, `CHECK` de precio y stock >= 0, `disponible` y `eliminado` en 0 o 1. La fila no se borra: `eliminado = 1` es la lápida. |
| `pedido_borrador` | Cabecera del pedido en la tablet. | `id_local` es un UUID en minúsculas con `CHECK`. `forma_pago` solo `EFECTIVO`, `TARJETA` o `TRANSFERENCIA`. `usuario` es un alias. |
| `item_borrador` | Ítems del borrador. | PK `(id_local, producto_id)`, cantidad > 0, FK a `pedido_borrador` y a `producto_cache`. Guarda `precio_centavos_visto`. |
| `cola_sync` | Solicitudes de sincronización. | `solicitud_uuid` es la PK (UUID con `CHECK`). Estado: `PENDIENTE` (por defecto), `SIMULADO_APROBADO`, `CONFLICTO` o `RECHAZADO`. Guarda `motivo`, `evaluada_en` y `snapshot_copiado_en`. |
| `snapshot_servidor` | Copia cruda del CSV, con `filas_copia`. | Se crea con tipos antes del `.import`. La importación verifica que llegaron todas las filas. |

No hay tabla de clientes ni datos personales.

## Importación

El upsert pisa precio, stock y banderas con los valores del servidor. Lo que se conserva es la fila: un producto dado de baja en el servidor queda con `eliminado = 1` (lápida) y los ítems que lo referencian siguen siendo válidos.

## Reglas del semáforo (por prioridad)

Se evalúan solo las solicitudes `PENDIENTE`.

1. Borrador sin ítems: `RECHAZADO`, motivo `borrador vacio`.
2. Producto que no existe en la instantánea, dado de baja, no disponible, o con cantidad mayor al stock: `RECHAZADO`.
3. Cualquier diferencia de precio (`<>`, sube o baja) y ninguna causa de rechazo: `CONFLICTO`.
4. Todo coincide: `SIMULADO_APROBADO`.

El rojo gana sobre el amarillo. El `CASE` del semáforo lo escribió una persona del equipo (modo aprendizaje).

## Idempotencia

- Una solicitud con UUID repetido falla por clave primaria.
- Una solicitud ya evaluada no sale de su estado: el semáforo solo toca `PENDIENTE`. Una segunda corrida da `changes() = 0`.
- Para aceptar un precio nuevo se crea una solicitud nueva con UUID nuevo.

## Por qué PostgreSQL no se toca

La tablet no escribe en el servidor. La simulación solo lee la instantánea. Un `SIMULADO_APROBADO` no es una venta: no se crea ningún pedido y el stock del servidor queda igual. Se comprobó con la línea base y la verificación final de `food_store_copia` (`evidencias/verificacion_final_diff.txt`). Las únicas escrituras en el servidor son la vista y la preparación y restauración de los casos C2 y C4, y quedan restauradas.
