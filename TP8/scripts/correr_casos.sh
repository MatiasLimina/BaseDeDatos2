#!/usr/bin/env bash
# scripts/correr_casos.sh: orquesta la ejecucion completa de los casos C2 a C6,
# exporta e importa las instantaneas correspondientes, guarda las evidencias en evidencias/
# y asegura la restauracion de PostgreSQL ante cualquier interrupcion.
set -eo pipefail

export PATH="$PATH:/d/DevTools/PosgresSQL/bin:/d/DevTools/PostgreSQL/bin:/d/DevTools/miniconda3/Library/bin"
export PGCLIENTENCODING=UTF8

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
# \copy y \i usan rutas relativas a TP8/: se corre siempre desde ahi.
cd "$RAIZ"
DB="$RAIZ/movil/foodstore_movil.db"
EVID="$RAIZ/evidencias"
P="psql -X -w -h localhost -U postgres -d food_store_copia -v ON_ERROR_STOP=1"

mkdir -p "$EVID"

# Metricas comparables de una linea base: sin comentarios ni la hora de medicion, y
# ordenadas (UNION ALL no garantiza el orden de las filas: se vio a pedidos= salir ultimo).
metricas() { grep -v -e '^#' -e '^medido_en=' "$1" | sort; }

# Restaurar PostgreSQL ante cualquier salida con error, incluido Ctrl+C
# (un trap ERR solo no se dispara con una interrupcion).
trap 'exit 130' INT TERM
trap 'rc=$?; if [ "$rc" -ne 0 ]; then echo "AVISO: restaurando PostgreSQL tras error o interrupcion (rc=$rc)..."; $P -f sql/casos/restaurar_casos.sql > /dev/null 2>&1 || true; fi' EXIT

echo "=== 0. Linea base de PostgreSQL ==="
# evidencias/linea_base.txt es la referencia limpia (tomada antes de tocar la base).
# Si la base actual no coincide, una corrida anterior la dejo modificada: no se sigue.
$P -At -f sql/linea_base.sql > "$EVID/linea_base_corrida.txt"
if ! diff <(metricas "$EVID/linea_base.txt") <(metricas "$EVID/linea_base_corrida.txt"); then
  echo "ERROR: food_store_copia no coincide con la linea base de referencia; correr sql/casos/restaurar_casos.sql y revisar" >&2
  exit 1
fi

echo "=== 1. Crear vista y exportar instantanea inicial S0 ==="
$P -f "$RAIZ/sql/01_v_snapshot_movil.sql" > /dev/null
$P -f "$RAIZ/sql/02_exportar_snapshot.sql" > /dev/null

echo "=== 2. Inicializar SQLite con schema e importar S0 ==="
rm -f "$DB"
sqlite3 "$DB" < "$RAIZ/movil/schema_sqlite.sql"
sqlite3 "$DB" < "$RAIZ/movil/importar_snapshot.sql" > "$EVID/importacion_s0.txt" 2>&1

echo "=== 3. Pruebas de la tablet (C1, C7 y borrador C5) ==="
# .bail off dentro de pruebas_sqlite.sql captura los errores de C7
sqlite3 "$DB" < "$RAIZ/movil/pruebas_sqlite.sql" > "$EVID/c1_c7_pruebas_sqlite.txt" 2>&1 || true

echo "=== 4. Caso C5: Evaluacion del borrador -> SIMULADO_APROBADO ==="
sqlite3 "$DB" < "$RAIZ/movil/semaforo.sql" > "$EVID/c5_aprobado.txt" 2>&1

echo "=== 5. Caso C6: Reintento de solicitud (error PK) y re-ejecucion (changes() = 0) ==="
sqlite3 "$DB" < "$RAIZ/movil/casos/c5_c6.sql" > "$EVID/c6_reintento.txt" 2>&1 || true
sqlite3 "$DB" < "$RAIZ/movil/semaforo.sql" > "$EVID/c6_semaforo_idempotente.txt" 2>&1

echo "=== 6. Caso C2: Suba de precio en servidor -> CONFLICTO y aceptacion -> SIMULADO_APROBADO ==="
sqlite3 "$DB" < "$RAIZ/movil/casos/c2_borrador.sql" > "$EVID/c2_borrador.txt" 2>&1
$P -f "$RAIZ/sql/casos/preparar_c2.sql" > "$EVID/c2_preparar_pg.txt" 2>&1
$P -f "$RAIZ/sql/02_exportar_snapshot.sql" > /dev/null
sqlite3 "$DB" < "$RAIZ/movil/importar_snapshot.sql" > /dev/null 2>&1
sqlite3 "$DB" < "$RAIZ/movil/semaforo.sql" > "$EVID/c2_conflicto.txt" 2>&1
sqlite3 "$DB" < "$RAIZ/movil/casos/c2_aceptar.sql" > "$EVID/c2_aceptar.txt" 2>&1
sqlite3 "$DB" < "$RAIZ/movil/semaforo.sql" > "$EVID/c2_aceptado.txt" 2>&1

echo "=== 7. Caso C3: Pedido por mas unidades que el stock -> RECHAZADO ==="
sqlite3 "$DB" < "$RAIZ/movil/casos/c3_borrador.sql" > "$EVID/c3_borrador.txt" 2>&1
sqlite3 "$DB" < "$RAIZ/movil/semaforo.sql" > "$EVID/c3_rechazado.txt" 2>&1

echo "=== 8. Caso C4: Baja logica en servidor -> RECHAZADO y conservacion de lapida ==="
sqlite3 "$DB" < "$RAIZ/movil/casos/c4_borrador.sql" > "$EVID/c4_borrador.txt" 2>&1
$P -f "$RAIZ/sql/casos/preparar_c4.sql" > "$EVID/c4_preparar_pg.txt" 2>&1
$P -f "$RAIZ/sql/02_exportar_snapshot.sql" > /dev/null
sqlite3 "$DB" < "$RAIZ/movil/importar_snapshot.sql" > /dev/null 2>&1
sqlite3 "$DB" < "$RAIZ/movil/semaforo.sql" > "$EVID/c4_rechazado.txt" 2>&1

echo "=== 9. Restauracion de PostgreSQL y verificacion final ==="
$P -f "$RAIZ/sql/casos/restaurar_casos.sql" > "$EVID/restaurar_casos.txt" 2>&1
$P -At -f "$RAIZ/sql/verificacion_final.sql" > "$EVID/verificacion_final.txt" 2>&1
if diff <(metricas "$EVID/linea_base.txt") <(metricas "$EVID/verificacion_final.txt") > "$EVID/verificacion_final_diff.txt"; then
  echo "verificacion_final: PostgreSQL igual a la linea base (pedidos, stock y huella)" | tee -a "$EVID/verificacion_final_diff.txt"
else
  echo "ERROR: PostgreSQL quedo distinto de la linea base, ver evidencias/verificacion_final_diff.txt" >&2
  exit 1
fi

echo "=== 10. Reexportar S0 con el servidor restaurado ==="
# Sin esto el CSV entregado queda con la instantanea de C4. Solo se exporta: la .db no se
# reimporta, asi conserva cola_sync con los resultados y la lapida del producto 3 (C4).
$P -f "$RAIZ/sql/02_exportar_snapshot.sql" > /dev/null

echo "=== Secuencia de casos completada exitosamente ==="
