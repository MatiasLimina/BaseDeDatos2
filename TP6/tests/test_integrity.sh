#!/usr/bin/env bash
# Prueba de integrity_check.sql sobre una base DESCARTABLE (SPEC_U6.md, regla 2).
#
# Crea foodstore_integ_test vacía con su propio escenario (no depende de foodstore)
# y comprueba que integrity_check.sql:
#   1. sobre datos sanos termina con código 0 e informa OK para tablas e índices;
#   2. ante un índice inconsistente con su tabla termina con código distinto de 0 y
#      nombra el índice. La inconsistencia se provoca sin tocar archivos: un índice
#      sobre una función IMMUTABLE que después se redefine queda con entradas
#      calculadas con la versión vieja, y amcheck (heapallindexed) no las encuentra;
#   3. con una tabla bloqueada por otra sesión no espera: la informa como omitida
#      y no la cuenta como corrupción.
#
# Uso, desde TP6/:  bash tests/test_integrity.sh   (imprime "test_integrity: OK")
# Requiere pgpass.conf para PGUSER.
set -euo pipefail

export PGHOST="${PGHOST:-localhost}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}"
export PGCLIENTENCODING=UTF8
BASE=foodstore_integ_test
DIR="$(cd "$(dirname "$0")/.." && pwd)"
SALIDA="$(mktemp)"
ERRORES="$(mktemp)"

q() { psql -X -w -d "$BASE" -v ON_ERROR_STOP=1 -Atc "$1"; }
falla() { echo "test_integrity: FALLA - $1" >&2; exit 1; }
chequear() { psql -X -w -d "$BASE" -v ON_ERROR_STOP=1 -f "$DIR/integrity_check.sql" > "$SALIDA" 2> "$ERRORES"; }
limpiar() { rm -f "$SALIDA" "$ERRORES"; dropdb -w --if-exists "$BASE"; }
trap limpiar EXIT

dropdb -w --if-exists "$BASE"
createdb -w "$BASE"
q "CREATE TABLE producto_prueba (id int PRIMARY KEY, precio int NOT NULL)" >/dev/null
q "INSERT INTO producto_prueba SELECT g, g % 97 FROM generate_series(1, 5000) g" >/dev/null
q "CREATE FUNCTION precio_lista(int) RETURNS int IMMUTABLE LANGUAGE sql AS 'SELECT \$1'" >/dev/null
q "CREATE INDEX idx_precio_lista ON producto_prueba (precio_lista(precio))" >/dev/null
q "CREATE TABLE otra (id int PRIMARY KEY)" >/dev/null

# 1. Datos sanos: código 0 y OK en la tabla y en sus índices.
chequear || falla "falló sobre datos sanos: $(cat "$ERRORES")"
grep -q 'producto_prueba.*OK' "$SALIDA"   || falla "no informa la tabla producto_prueba como OK"
grep -q 'producto_prueba_pkey.*OK' "$SALIDA" || falla "no informa producto_prueba_pkey como OK"
grep -q 'idx_precio_lista.*OK' "$SALIDA"  || falla "no informa idx_precio_lista como OK"

# 3. Tabla bloqueada por otra sesión: no espera, la marca como omitida y termina bien.
psql -X -w -d "$BASE" -q -c "BEGIN; LOCK TABLE otra IN ACCESS EXCLUSIVE MODE;
                            SELECT pg_sleep(20); ROLLBACK;" >/dev/null 2>&1 &
BLOQUEO=$!
sleep 3
[ "$(q "SELECT EXISTS (SELECT 1 FROM pg_locks WHERE relation = 'otra'::regclass
                         AND mode = 'AccessExclusiveLock' AND granted)")" = "t" ] \
    || falla "la sesión de prueba no tomó el bloqueo"
inicio=$(date +%s)
chequear || falla "una tabla bloqueada se contó como corrupción: $(cat "$ERRORES")"
[ $(( $(date +%s) - inicio )) -lt 15 ] || falla "esperó detrás del bloqueo"
grep -q 'otra.*OMITIDA' "$SALIDA" || falla "no informa la tabla bloqueada como OMITIDA"
wait "$BLOQUEO" || true

# 2. Índice inconsistente: código distinto de 0 y el índice nombrado.
q "CREATE OR REPLACE FUNCTION precio_lista(int) RETURNS int IMMUTABLE LANGUAGE sql AS 'SELECT \$1 + 1'" >/dev/null
if chequear; then falla "terminó con código 0 con un índice inconsistente"; fi
grep -q 'idx_precio_lista.*FALLA' "$SALIDA" || falla "no nombra idx_precio_lista como FALLA"
grep -q 'producto_prueba_pkey.*OK' "$SALIDA" || falla "dejó de revisar los demás índices tras la primera falla"

echo "test_integrity: OK"
