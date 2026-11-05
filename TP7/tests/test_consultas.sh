#!/usr/bin/env bash
# Prueba de la Parte 2: ejecuta consultas_mongodb.js y consultas_postgresql.sql y compara,
# consulta por consulta, los ids de pedidos que devuelve cada motor.
#
# Cada archivo imprime, después de cada consulta, una línea "RESULTADO <x>: <ids separados
# por coma>" que sale de la misma consulta (no se reescribe acá). Se comprueba que:
#   - a) MongoDB devuelve los 9 pedidos migrados (sql/01_seleccion_pedidos.sql), y la
#     lista literal de pedidos de consultas_postgresql.sql es esa misma;
#   - b), c) y d) devuelven los mismos ids en PostgreSQL y en MongoDB;
#   - b), c) y d) no son triviales: ninguna devuelve 0 pedidos ni los 9.
#
# Uso, desde la raíz del repo:  bash tests/test_consultas.sh   (imprime "test_consultas: OK")
set -euo pipefail

export PGHOST="${PGHOST:-localhost}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}"
export PGCLIENTENCODING=UTF8
MONGOSH="${MONGOSH:-$(command -v mongosh || echo /c/Users/Nico/AppData/Local/Programs/mongosh/mongosh.exe)}"
URI="${MONGO_URI:-mongodb://localhost:27017/foodstore}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

falla() { echo "test_consultas: FALLA - $1" >&2; exit 1; }
resultado() {  # resultado <archivo> <consulta>: ids de la línea RESULTADO
    local linea
    linea=$(grep "^RESULTADO $2:" "$1" || true)
    [ -n "$linea" ] || falla "$(basename "$1") no imprime RESULTADO $2"
    echo "${linea#RESULTADO $2: }"
}

"$MONGOSH" "$URI" --quiet --file "$DIR/consultas_mongodb.js" | tr -d '\r' > "$TMP/mongo.txt" \
    || falla "consultas_mongodb.js terminó con error"
psql -X -w -d foodstore -v ON_ERROR_STOP=1 -f "$DIR/consultas_postgresql.sql" 2>&1 | tr -d '\r' > "$TMP/pg.txt" \
    || { cat "$TMP/pg.txt" >&2; falla "consultas_postgresql.sql terminó con error"; }

migrados=$(psql -X -w -d foodstore -At -f "$DIR/sql/01_seleccion_pedidos.sql" | tr -d '\r' | paste -sd',')
[ "$(resultado "$TMP/mongo.txt" a)" = "$migrados" ] || falla "a) no devuelve los pedidos migrados ($migrados)"
[ "$(resultado "$TMP/pg.txt" a)" = "$migrados" ] \
    || falla "la lista migrados de consultas_postgresql.sql no coincide con la selección ($migrados)"

for c in b c d; do
    m=$(resultado "$TMP/mongo.txt" "$c")
    p=$(resultado "$TMP/pg.txt" "$c")
    [ "$m" = "$p" ] || falla "$c) MongoDB [$m] y PostgreSQL [$p] no coinciden"
    [ -n "$m" ] || falla "$c) no devuelve ningún pedido"
    [ "$m" != "$migrados" ] || falla "$c) devuelve todos los pedidos: no filtra nada"
done

echo "test_consultas: OK"
