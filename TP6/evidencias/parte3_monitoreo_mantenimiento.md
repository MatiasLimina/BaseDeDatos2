# Parte 3 — Monitoreo y mantenimiento

Ejecutado el 28/10/2026 sobre `foodstore` (PostgreSQL 17.11).

## `health_check.sql`

Cumple los cuatro controles que pide la consigna y agrega otros. Es de solo lectura y usa `current_database()`, así que también corre sobre `foodstore_restore_test`.

| Control | Qué muestra | Para qué |
|---|---|---|
| Encabezado | Momento, base, versión y **tamaño de la base** | Seguir el crecimiento y estimar el tamaño de los respaldos |
| 1. Conexiones y transacciones | `numbackends` contra `max_connections`, commits y rollbacks (con %), deadlocks, archivos temporales, % de cache hit y sesiones por estado | Ver cuánto margen de conexiones queda, detectar errores de la aplicación y si falta memoria |
| 2. Consultas activas | Sesiones no `idle` (sin la propia), con su duración y su evento de espera | Encontrar consultas largas y sesiones `idle in transaction` |
| 2b. Sesiones bloqueadas | `pg_blocking_pids()`: quién bloquea a quién | Diagnosticar bloqueos |
| 3. Estado de tablas | Tuplas vivas y muertas, % de muertas, último vacuum y último analyze; edad de XID respecto de `autovacuum_freeze_max_age` | Saber si autovacuum alcanza y qué tan lejos está el wraparound |
| 4. Tamaño por tabla | Tamaño total, de datos y de índices (las 10 tablas más grandes) | Ver el crecimiento de cada tabla |

Salidas: [`parte3_health_check.txt`](parte3_health_check.txt) (corrida normal, código 0) y [`parte3_health_check_con_bloqueo.txt`](parte3_health_check_con_bloqueo.txt). En esta segunda, otra sesión tenía `cliente` bloqueada y una tercera la esperaba. El control 2b mostró la cadena (`32044` bloqueada por `{12276}`) y el chequeo terminó con error a los 5 s (código 3), en lugar de quedar colgado.

**Defecto encontrado al probar.** En la primera versión, el tamaño por tabla iba primero. `pg_total_relation_size` toma un bloqueo sobre cada tabla, así que, ante un bloqueo, **el chequeo se quedaba esperando justo detrás del problema que debía mostrar**. Cuando por fin llegaba a "consultas activas", el bloqueo ya había terminado y la sección salía vacía. Al principio parecía un problema del escenario de prueba. Se descartó consultando `pg_stat_activity` desde otra sesión, donde los bloqueos sí se veían. Corrección: los controles que no toman bloqueos van primero, y el tamaño por tabla va al final con `lock_timeout = 5s`.

## `maintenance.sql`

1. Muestra la configuración de autovacuum: umbral de vacuum de 50 + 20 % y de analyze de 50 + 10 %, con un `naptime` de 60 s.
2. Calcula, por tabla, **los mismos umbrales que autovacuum**, con los valores por tabla de `reloptions` si existen, y decide una acción con su motivo:
   - `VACUUM (ANALYZE)` si las tuplas muertas superan el umbral de vacuum;
   - `ANALYZE` si los cambios desde el último analyze superan su umbral, o si la tabla tiene datos y el planificador no tiene estadísticas (no hay filas en `pg_stats`).
3. Ejecuta solo esas acciones, una sentencia por vez con `\gexec`, porque `VACUUM` no corre dentro de una transacción. Si se define `solo_revision` (por ejemplo `-v solo_revision=1`) muestra el plan sin ejecutarlo. Cuenta que la variable esté definida, no su valor.
4. Vuelve a mostrar el estado como evidencia.

**Tablas bloqueadas.** Si otra sesión tiene, o espera, un bloqueo incompatible con `VACUUM`/`ANALYZE` sobre una tabla, esa tabla no se mide ni se toca y aparece con el motivo "bloqueada por otra sesión". Si el bloqueo aparece justo entre la revisión y la acción, la acción espera hasta 1 min (`lock_timeout`) y el script termina con error, dejando las acciones siguientes para la próxima corrida.

**No usa `VACUUM FULL`**, que reescribe la tabla con un bloqueo exclusivo. `VACUUM` y `ANALYZE` toman `SHARE UPDATE EXCLUSIVE`, que no bloquea lecturas ni escrituras. La única excepción es breve y nunca espera: `VACUUM` puede tomar un bloqueo exclusivo para liberar las páginas vacías del final de la tabla, pero solo si lo consigue sin esperar.

### Observación previa y decisión

[`parte3_maintenance_revision.txt`](parte3_maintenance_revision.txt): ninguna tabla tenía tuplas muertas, porque autovacuum había procesado las tablas grandes a las 18:04, después de la carga. Pero **`categoria` (3 filas) y `mv_facturacion_categoria_mes` (1 fila) nunca se habían analizado**. Con 3 cambios contra un umbral de 50, autovacuum no las iba a analizar nunca mientras la tabla no cambie. La acción ejecutada fue `ANALYZE` sobre esas dos y nada más ([`parte3_maintenance_ejecucion.txt`](parte3_maintenance_ejecucion.txt)).

Efecto sobre el planificador ([`parte3_planes_antes_despues.txt`](parte3_planes_antes_despues.txt)):

| `EXPLAIN SELECT * FROM categoria` | Filas estimadas | Ancho estimado |
|---|---|---|
| Sin estadísticas | 360 | 195 bytes |
| Después del `ANALYZE` | **3** (las reales) | 25 bytes |

Una segunda corrida devuelve "Sin acciones". La versión final del script, con la detección de tablas bloqueadas agregada después de la revisión, se volvió a ejecutar sobre `foodstore`: las seis tablas quedaron dentro de los umbrales y no hubo acciones ([`parte3_maintenance_version_final.txt`](parte3_maintenance_version_final.txt)). Para la Parte 4 hay una consecuencia: `pg_restore` no restaura estadísticas, así que **toda** la base restaurada queda en esta situación hasta que se ejecute `maintenance.sql` o `ANALYZE`.

### Prueba automatizada

[`../tests/test_maintenance.sh`](../tests/test_maintenance.sh) trabaja sobre una base **descartable**: `foodstore_maint_test`, una copia de `foodstore` que se borra al terminar. Para lo que verifica, arma su propio escenario: 12 000 tuplas muertas en `cliente` (umbral 4 051) y una tabla nueva con datos y sin estadísticas. Sí necesita que `foodstore` tenga cargados el esquema y los datos del proyecto integrador. Después comprueba que:
- con una tabla bloqueada por otra sesión, la revisión no espera: la informa como bloqueada y no propone actuar sobre ella;
- con `solo_revision` no se ejecuta nada;
- solo se vacía `cliente`;
- se analiza la tabla sin estadísticas;
- no se tocan las demás;
- una segunda corrida no propone acciones;
- no hay `VACUUM FULL`.

Ciclo seguido:
- **RED:** el test falló porque `maintenance.sql` no existía.
- **Primera corrida de GREEN:** destapó un defecto. En una base recién copiada, `n_live_tup` es 0, y en una tabla que nunca se vació ni analizó `reltuples` es -1, así que la regla "tiene filas" no detectaba nada. Se corrigió usando el tamaño físico (`pg_relation_size > 0`).
- **Mutaciones:** cada una hizo fallar el test:
  - quitar la regla de vacuum;
  - analizar todo;
  - quitar la regla de estadísticas;
  - ignorar `solo_revision`;
  - quitar la protección contra bloqueos de `pg_relation_size`.

**Defecto encontrado en la revisión antes del commit.** Un agente revisor de solo lectura notó que `pg_relation_size` repetía el defecto de `health_check.sql`. Con una tabla bloqueada, la revisión esperaba 1 min y abortaba sin dejar evidencia. La alternativa sin bloqueos (`relpages`/`reltuples`) no sirve justo para las tablas que nunca se vaciaron ni analizaron, así que se consulta `pg_locks` primero. Se agregó al test el caso de la tabla bloqueada (RED: la revisión esperó; GREEN: la informa y sigue). También corrigió dos verificaciones del test que no podían fallar: una revisaba la salida equivocada y la otra podía dar un falso OK por `SIGPIPE` con `pipefail`.

**Defecto del propio test.** La primera versión dependía de que `categoria` no tuviera estadísticas en `foodstore`. Cuando `maintenance.sql` se ejecutó sobre la base real, el test empezó a fallar. Se rehízo para que arme su propio escenario.
