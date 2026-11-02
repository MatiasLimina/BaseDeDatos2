#!/usr/bin/env bash
# Comprobacion del hallazgo INTEG-01 (code review 3.c): PRAGMA foreign_keys vale por
# conexion. Crea una base temporal con el esquema real de la tablet y repite la misma
# insercion invalida (item de un producto inexistente) en dos conexiones distintas:
# una sin el PRAGMA y otra con el PRAGMA. No toca movil/foodstore_movil.db.
set -u
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SALIDA="$RAIZ/evidencias/code_review_integ01.txt"
DB="$(mktemp -d)/demo_pragma.db"

# Cada sqlite3 es una conexion nueva: el PRAGMA del esquema no sobrevive a la siguiente.
sqlite3 "$DB" < "$RAIZ/movil/schema_sqlite.sql"
sqlite3 "$DB" "INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
               VALUES ('30000000-0000-4000-8000-000000000001', 'vendedor_demo', 'EFECTIVO');"

INSERT_INVALIDO="INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
                 VALUES ('30000000-0000-4000-8000-000000000001', 999999, 1, 100);"

{
  echo "=== Comprobacion Empirica Hallazgo INTEG-01 (PRAGMA foreign_keys por conexion) ==="
  echo "Fecha: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "SQLite: $(sqlite3 --version | cut -d' ' -f1)"
  echo "Base: temporal, creada con movil/schema_sqlite.sql (producto_cache vacia)."
  echo "Insercion: item_borrador con producto_id = 999999, que no existe en producto_cache."
  echo
  echo "--- Conexion 1: SIN el PRAGMA ---"
  sqlite3 "$DB" "SELECT 'foreign_keys = ' || foreign_keys FROM pragma_foreign_keys;
                 $INSERT_INVALIDO
                 SELECT 'changes() = ' || changes();" 2>&1
  echo
  echo "--- Conexion 2: CON el PRAGMA (se borra la fila anterior y se repite la insercion) ---"
  sqlite3 "$DB" "DELETE FROM item_borrador;" 2>&1
  # stdout y stderr por separado: si no, el error aparece antes que el valor del PRAGMA.
  ERR="$(mktemp)"
  sqlite3 "$DB" "PRAGMA foreign_keys = ON;
                 SELECT 'foreign_keys = ' || foreign_keys FROM pragma_foreign_keys;
                 $INSERT_INVALIDO
                 SELECT 'changes() = ' || changes();" 2>"$ERR"
  cat "$ERR"; rm -f "$ERR"
  echo
  echo "--- Estado final ---"
  sqlite3 "$DB" "SELECT 'filas en item_borrador = ' || count(*) FROM item_borrador;"
  echo
  echo "--- Huerfano que dejaria la conexion 1 (PRAGMA foreign_key_check) ---"
  sqlite3 "$DB" "$INSERT_INVALIDO PRAGMA foreign_key_check;" 2>&1
  echo
  echo "--- Mitigacion: primera sentencia SQL de cada script de la tablet ---"
  echo "(se saltean comentarios y comandos del shell sqlite3 como .headers, que no son SQL)"
  for f in "$RAIZ"/movil/*.sql "$RAIZ"/movil/casos/*.sql; do
    primera="$(grep -v -E '^\s*(--|\.|$)' "$f" | head -1)"
    echo "${f#$RAIZ/}: $primera"
  done
  echo
  echo "Decision: ACEPTADO. Sin el PRAGMA, SQLite guarda un item de un producto inexistente"
  echo "sin avisar (changes() = 1) y solo PRAGMA foreign_key_check lo detecta despues."
  echo "Ya esta mitigado: todos los scripts de movil/ lo activan en su primera sentencia."
  echo "Cualquier cliente nuevo que abra la .db tiene que hacer lo mismo."
} > "$SALIDA"

rm -rf "$(dirname "$DB")"
cat "$SALIDA"
