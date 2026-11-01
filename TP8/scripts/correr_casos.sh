#!/usr/bin/env bash
# scripts/correr_casos.sh: orquesta la ejecucion completa de los casos C2 a C6,
# exporta e importa las instantaneas correspondientes, guarda las evidencias en evidencias/
# y asegura la restauracion de PostgreSQL ante cualquier interrupcion.
set -eo pipefail

export PATH="$PATH:/d/DevTools/PosgresSQL/bin:/d/DevTools/PostgreSQL/bin:/d/DevTools/miniconda3/Library/bin"
export PGCLIENTENCODING=UTF8

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
DB="$RAIZ/movil/foodstore_movil.db"
EVID="$RAIZ/evidencias"
P="psql -X -w -h localhost -U postgres -d food_store_copia -v ON_ERROR_STOP=1"

mkdir -p "$EVID"

# Trap para restaurar PostgreSQL si el script se interrumpe
trap 'echo "AVISO: Restaurando PostgreSQL tras interrupcion..."; $P -f "$RAIZ/sql/casos/restaurar_casos.sql" > /dev/null 2>&1 || true' ERR

echo "=== 0. Linea base de PostgreSQL ==="
$P -At -f "$RAIZ/sql/linea_base.sql" > "$EVID/linea_base.txt"

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

trap - ERR
echo "=== Secuencia de casos completada exitosamente ==="
