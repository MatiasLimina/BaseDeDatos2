#!/usr/bin/env bash
# Prueba de maintenance.sql sobre una base DESCARTABLE (SPEC_U6.md, regla 2).
#
# Crea foodstore_maint_test como copia de foodstore y arma su propio escenario, sin
# depender del estado de foodstore: tuplas muertas solo en cliente y una tabla nueva,
# sin_estadisticas, cargada con CREATE TABLE AS (que no analiza). Comprueba que
# maintenance.sql:
#   - con -v solo_revision=1 no ejecuta nada;
#   - ejecuta VACUUM (ANALYZE) solo sobre la tabla que supera el umbral de autovacuum;
#   - ejecuta ANALYZE sobre las tablas sin estadísticas del planificador;
#   - no toca las tablas que no lo necesitan.
#
# Uso, desde TP6/:  bash tests/test_maintenance.sh   (imprime "test_maintenance: OK")
# Requiere pgpass.conf para PGUSER; foodstore solo se lee (como plantilla).
set -euo pipefail

export PGHOST="${PGHOST:-localhost}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}"
export PGCLIENTENCODING=UTF8
BASE=foodstore_maint_test
DIR="$(cd "$(dirname "$0")/.." && pwd)"
SALIDA="$(mktemp)"

q() { psql -X -w -d "$BASE" -v ON_ERROR_STOP=1 -Atc "$1"; }
falla() { echo "test_maintenance: FALLA - $1" >&2; exit 1; }
esperar() {  # esperar <descripción> <consulta que debe devolver t>
    [ "$(q "$2")" = "t" ] || falla "$1"
}
limpiar() { rm -f "$SALIDA" "${EJECUCION:-}"; dropdb -w --if-exists "$BASE"; }
trap limpiar EXIT

dropdb -w --if-exists "$BASE"
createdb -w -T foodstore "$BASE"

# Sin autovacuum en cliente, para que no limpie antes que maintenance.sql.
# 12 000 tuplas muertas superan el umbral 50 + 0,2 * 20 003 = 4 050,6.
q "ALTER TABLE cliente SET (autovacuum_enabled = false)" >/dev/null
q "UPDATE cliente SET nombre = nombre WHERE id <= 12000" >/dev/null
# Una tabla con filas y sin estadísticas del planificador.
q "CREATE TABLE sin_estadisticas AS SELECT g AS id FROM generate_series(1, 10) g" >/dev/null
q "SELECT pg_stat_force_next_flush()" >/dev/null
sleep 2
esperar "la preparación no generó tuplas muertas en cliente" \
    "SELECT n_dead_tup >= 12000 FROM pg_stat_user_tables WHERE relname = 'cliente'"

# 0. Con una tabla bloqueada por otra sesión, la revisión no espera: la marca y sigue.
psql -X -w -d "$BASE" -q -c "BEGIN; LOCK TABLE sin_estadisticas IN ACCESS EXCLUSIVE MODE;
                            SELECT pg_sleep(20); ROLLBACK;" >/dev/null 2>&1 &
BLOQUEO=$!
sleep 3
esperar "la sesión de prueba no tomó el bloqueo" \
    "SELECT EXISTS (SELECT 1 FROM pg_locks WHERE relation = 'sin_estadisticas'::regclass
                      AND mode = 'AccessExclusiveLock' AND granted)"
inicio=$(date +%s)
psql -X -w -d "$BASE" -v ON_ERROR_STOP=1 -v solo_revision=1 -f "$DIR/maintenance.sql" > "$SALIDA" \
    || falla "la revisión falló con una tabla bloqueada"
[ $(( $(date +%s) - inicio )) -lt 10 ] || falla "la revisión esperó detrás del bloqueo"
grep -q 'sin_estadisticas.*bloqueada' "$SALIDA" || falla "no informa la tabla bloqueada"
grep -q 'ANALYZE public.sin_estadisticas' "$SALIDA" && falla "propone actuar sobre una tabla bloqueada"
wait "$BLOQUEO"

# 1. Solo revisión: muestra el plan pero no ejecuta nada.
psql -X -w -d "$BASE" -v ON_ERROR_STOP=1 -v solo_revision=1 -f "$DIR/maintenance.sql" > "$SALIDA"
grep -q 'VACUUM (ANALYZE) public.cliente' "$SALIDA" || falla "el plan no propone VACUUM (ANALYZE) para cliente"
grep -q 'ANALYZE public.sin_estadisticas' "$SALIDA" || falla "el plan no propone ANALYZE para sin_estadisticas"
esperar "solo_revision ejecutó un VACUUM" \
    "SELECT n_dead_tup >= 12000 AND last_vacuum IS NULL FROM pg_stat_user_tables WHERE relname = 'cliente'"

# 2. Ejecución real. Con -e quedan en la salida las sentencias que se ejecutaron.
EJECUCION="$(mktemp)"
psql -X -w -d "$BASE" -v ON_ERROR_STOP=1 -e -f "$DIR/maintenance.sql" > "$EJECUCION"
esperar "cliente no fue vaciada" \
    "SELECT last_vacuum IS NOT NULL AND last_analyze IS NOT NULL AND n_dead_tup = 0
       FROM pg_stat_user_tables WHERE relname = 'cliente'"
esperar "sin_estadisticas sigue sin estadísticas" \
    "SELECT EXISTS (SELECT 1 FROM pg_stats WHERE schemaname = 'public' AND tablename = 'sin_estadisticas')"
esperar "se tocaron tablas que no lo necesitaban" \
    "SELECT bool_and(last_vacuum IS NULL AND last_analyze IS NULL) FROM pg_stat_user_tables
      WHERE relname IN ('pedido', 'pedido_detalle', 'producto')"

# 3. Segunda corrida: ya no queda nada por hacer.
psql -X -w -d "$BASE" -v ON_ERROR_STOP=1 -f "$DIR/maintenance.sql" > "$SALIDA"
grep -q 'Sin acciones' "$SALIDA" || falla "la segunda corrida volvió a proponer acciones"

# 4. Nunca VACUUM FULL, ni en el código ni en lo que se ejecutó (los comentarios lo
#    mencionan). Sin grep -q en la tubería: con pipefail, el SIGPIPE daría un falso OK.
if grep -v '^ *--' "$DIR/maintenance.sql" | grep -i 'FULL' >/dev/null; then
    falla "maintenance.sql contiene VACUUM FULL"
fi
grep -q 'VACUUM (ANALYZE) public.cliente' "$EJECUCION" || falla "la salida de la ejecución no tiene el VACUUM"
if grep -i 'VACUUM *(FULL\|VACUUM FULL' "$EJECUCION" >/dev/null; then
    falla "se ejecutó un VACUUM FULL"
fi

echo "test_maintenance: OK"
