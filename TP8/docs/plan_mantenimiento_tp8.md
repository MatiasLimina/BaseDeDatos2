# Plan de mantenimiento integral de la capa de datos (TP8)

> **Alcance y marco de gobierno:**
> Este documento extiende el plan de mantenimiento de la Unidad 6 a los tres motores del ecosistema Food Store (PostgreSQL central, MongoDB documental de analítica de pedidos del TP7, y SQLite local en tablets para venta offline en ferias). **No modifica el plan del TP6**, sino que formaliza las políticas de respaldo, restauración, contingencia y roles para la arquitectura distribuida.

---

## 1. Qué se respalda y cómo se prueba la restauración en cada motor

### 1.1 PostgreSQL (Servidor central - Fuente de verdad)
* **Qué se respalda:** Base completa (`foodstore` en producción / `food_store_copia` en pruebas), incluyendo catálogo de productos, categorías, clientes, pedidos confirmados (ventas) y estados.
* **Política:** Respaldo diario automatizado (volcado lógico vía `pg_dump` con compresión).
* **Prueba de restauración:** Semanal, en un servidor aislado de pruebas, verificando la integridad referencial y comprobando conteos y huella digital del catálogo (`sql/linea_base.sql`).

### 1.2 MongoDB (Unidad 7 - Consultas documentales de pedidos)
* **Qué se respalda:** **No se respalda de forma independiente**.
* **Fundamento:** La colección `foodstore.pedidos` es una vista documental desnormalizada (proyección de solo lectura) cuyos datos se derivan íntegramente de PostgreSQL.
* **Procedimiento de recuperación:** Ante pérdida de datos o corrupción en MongoDB, la colección se destruye y se regenera desde la fuente de verdad ejecutando el flujo de extracción y carga probado en el TP7:
  1. `psql -f migracion/generar_insert_pedidos.sql -o mongodb/02_insert_pedidos.js`
  2. `mongosh mongodb/01_crear_coleccion.js`
  3. `mongosh mongodb/02_insert_pedidos.js`

### 1.3 SQLite (Tablet del Food Truck - Operación offline)
* **Qué se respalda:** Archivo local `foodstore_movil.db` que contiene los borradores de pedido (`pedido_borrador`, `item_borrador`), la cola de sincronización (`cola_sync`) y la copia del catálogo (`producto_cache`).
* **Política de respaldo:** Al cierre de cada jornada de feria (antes del apagado de la tablet o de la conexión al servidor), se realiza una copia en caliente utilizando el comando nativo:
  ```sql
  VACUUM INTO 'respaldo_jornada_YYYYMMDD.db';
  ```
  `VACUUM INTO` genera una copia limpia, desfragmentada y transaccionalmente consistente sin bloquear la lectura.
* **Prueba de restauración:** Semanalmente, el personal técnico monta la copia generada en una carpeta aislada y comprueba:
  1. `PRAGMA integrity_check;` devuelve `ok`.
  2. Conteos idénticos en las cuatro tablas maestras (`producto_cache`, `pedido_borrador`, `item_borrador`, `cola_sync`).

---

## 2. Contingencia: ¿Qué hacen las tablets ante la restauración de un respaldo viejo de PostgreSQL?

Si el servidor central PostgreSQL sufre una contingencia grave y debe restaurarse a un respaldo anterior (con pérdida de transacciones recientes, RPO > 0):

1. **Principio de desconfianza:** La tablet **no confía en su caché local ni en resultados simulados previos**. Un estado `SIMULADO_APROBADO` obtenido contra una instantánea que el servidor ya no reconoce como vigente queda inmediatamente invalidado.
2. **Invalidación de la instantánea:** La tabla `snapshot_servidor` se vacía y se suspende la evaluación del semáforo hasta recibir la nueva instantánea oficial.
3. **Recarga de instantánea fresca:** Una vez restaurado el servidor, se exporta una nueva instantánea con `copiado_en` estrictamente posterior a la fecha/hora de la restauración.
4. **Reevaluación de solicitudes:** La tablet importa la nueva instantánea y re-ejecuta `movil/semaforo.sql` para todas las solicitudes que permanecían en `PENDIENTE`.
5. **Auditoría de discrepancias:** Toda solicitud que hubiera cambiado de resultado (por ejemplo, pedidos armados con precios que volvieron a valores antiguos o stock que volvió a estar disponible) es separada para revisión antes de cualquier intento de confirmación.

---

## 3. Frecuencia y responsable de revisar solicitudes en CONFLICTO o RECHAZADO

* **Frecuencia obligatoria:** Al **cierre de cada jornada de feria**, inmediatamente posterior a la ejecución del semáforo de sincronización y previo al respaldo de la base local.
* **Rol responsable:** **Encargado del Food Truck** (responsable operativo de punto de venta y cuadre de caja).

### Procedimiento de actuación según semáforo:
* **Solicitudes en `CONFLICTO` (amarillo - cambio de precio en servidor):**
  * El encargado consulta la columna `motivo` en `cola_sync` (que detalla precio visto vs. precio vigente en centavos).
  * Si el cliente se encuentra presente o contactable y aprueba la diferencia, se ejecuta `movil/casos/c2_aceptar.sql`: se actualiza el precio visto y se genera una nueva solicitud `PENDIENTE` (manteniendo la anterior como `CONFLICTO` para auditoría).
  * Si el cliente desiste, la solicitud queda archivada como `CONFLICTO` sin procesar venta.
* **Solicitudes en `RECHAZADO` (rojo - sin stock, producto dado de baja o inexistente):**
  * El encargado analiza la causal en `motivo` (falta de stock o baja del producto).
  * Se notifica la anulación del pedido en el parte diario de la feria.
  * Ninguna fila de borrador se elimina físicamente: permanece en SQLite para control de mermas e historial operativo.
