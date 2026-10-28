#!/usr/bin/env bash
# Prueba de restore_test.ps1 (SPEC_U6.md, "Restauración de prueba" y regla 2).
#
# Trabaja con una carpeta temporal de respaldos, para controlar cuál es "el último",
# y comprueba que el script:
#   - se niega a restaurar sobre cualquier base que no sea foodstore_restore_test
#     (probado con una base canario descartable, nunca con foodstore);
#   - falla si el último respaldo no tiene su archivo de conteos;
#   - falla si el respaldo está dañado;
#   - falla si los conteos no coinciden con los registrados antes del respaldo;
#   - con un respaldo sano, restaura, valida y registra RPO y RTO;
#   - nunca modifica foodstore.
#
# Uso, desde TP6/:  bash tests/test_restore.sh   (imprime "test_restore: OK")
# Requiere un respaldo ya generado por backup_foodstore.ps1 en backups/.
set -euo pipefail

export PGHOST="${PGHOST:-localhost}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}"
export PGCLIENTENCODING=UTF8
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
DESTINO=foodstore_restore_test
CANARIO=foodstore_canario_test

falla() { echo "test_restore: FALLA - $1" >&2; exit 1; }
limpiar() { rm -rf "$TMP"; dropdb -w --if-exists "$CANARIO" 2>/dev/null || true; }
trap limpiar EXIT

# Ejecuta restore_test.ps1 con la carpeta temporal; deja el código en $codigo.
restaurar() {
    set +e
    powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$DIR/restore_test.ps1")" \
        -BackupDir "$(cygpath -w "$TMP/backups")" -LogDir "$(cygpath -w "$TMP/logs")" "$@" \
        > "$TMP/salida.txt" 2>&1
    codigo=$?
    set -e
}
huella_foodstore() {  # conteos + oid: si foodstore se recreara o cambiara, cambia
    psql -X -w -d foodstore -Atc "SELECT (SELECT oid FROM pg_database WHERE datname = 'foodstore'),
        (SELECT count(*) FROM cliente), (SELECT count(*) FROM pedido_detalle)"
}

ultimo=$(ls -t "$DIR"/backups/foodstore_*.dump | head -1)
base=$(basename "$ultimo" .dump)
[ -f "$DIR/backups/$base.counts.csv" ] || falla "el respaldo $base no tiene .counts.csv"
mkdir -p "$TMP/backups"
cp "$ultimo" "$DIR/backups/$base.counts.csv" "$TMP/backups/"
huella_antes=$(huella_foodstore)

# 1. Destino distinto de foodstore_restore_test. Se prueba con una base canario
#    descartable y no con foodstore: si el control fallara, el propio test borraría
#    y restauraría la base que se quiere proteger.
dropdb -w --if-exists "$CANARIO"
createdb -w "$CANARIO"
psql -X -w -d "$CANARIO" -q -c "CREATE TABLE marca (x int); INSERT INTO marca VALUES (42)"
restaurar -Target "$CANARIO"
[ "$codigo" -ne 0 ] || falla "aceptó restaurar sobre $CANARIO"
grep -q 'foodstore_restore_test' "$TMP/salida.txt" || falla "el rechazo no explica el destino permitido"
[ "$(psql -X -w -d "$CANARIO" -Atc "SELECT x FROM marca")" = "42" ] || falla "$CANARIO fue modificada"
# Los nombres de base distinguen mayúsculas: este sería otro destino.
restaurar -Target FOODSTORE_RESTORE_TEST
[ "$codigo" -ne 0 ] || falla "aceptó FOODSTORE_RESTORE_TEST (comparación sin distinguir mayúsculas)"
grep -q 'rechazado' "$TMP/salida.txt" || falla "FOODSTORE_RESTORE_TEST falló, pero no por el control de destino"

# 2. Respaldo sin archivo de conteos.
mv "$TMP/backups/$base.counts.csv" "$TMP/conteos.csv"
restaurar
[ "$codigo" -ne 0 ] || falla "restauró sin archivo de conteos"
grep -q 'conteos previos' "$TMP/salida.txt" || falla "falló sin conteos, pero por otro motivo"
mv "$TMP/conteos.csv" "$TMP/backups/$base.counts.csv"

# 3. Respaldo dañado (truncado a la mitad), más nuevo que el sano.
danado="foodstore_29991231_235959"
head -c $(( $(stat -c %s "$ultimo") / 2 )) "$ultimo" > "$TMP/backups/$danado.dump"
cp "$TMP/backups/$base.counts.csv" "$TMP/backups/$danado.counts.csv"
restaurar
[ "$codigo" -ne 0 ] || falla "aceptó un respaldo truncado"
tail -1 "$TMP/logs/restore_test.log" | grep -q 'ERROR.*pg_restore' \
    || falla "el respaldo truncado no falló en pg_restore"
rm "$TMP/backups/$danado".*

# 4. Conteos que no coinciden (alguien escribió entre los conteos y el respaldo).
cp "$TMP/backups/$base.counts.csv" "$TMP/conteos.csv"
sed -i 's/^cliente;.*/cliente;1/' "$TMP/backups/$base.counts.csv"
restaurar
[ "$codigo" -ne 0 ] || falla "validó con conteos distintos"
grep -q 'cliente tiene .* filas y se esperaban 1' "$TMP/salida.txt" || falla "no dice qué tabla no coincide"
mv "$TMP/conteos.csv" "$TMP/backups/$base.counts.csv"

# 5. Respaldo sano: restaura, valida y registra RPO y RTO.
restaurar
[ "$codigo" -eq 0 ] || { cat "$TMP/salida.txt"; falla "la restauración del respaldo sano falló"; }
tail -1 "$TMP/logs/restore_test.log" | grep -q "OK .*$base.*RPO .*RTO " \
    || falla "la línea OK no tiene el respaldo, el RPO y el RTO"
[ "$(psql -X -w -d "$DESTINO" -Atc "SELECT count(*) FROM pedido_detalle")" = \
  "$(grep '^pedido_detalle;' "$TMP/backups/$base.counts.csv" | cut -d';' -f2 | tr -d '\r')" ] \
    || falla "foodstore_restore_test no tiene las filas del respaldo"

# 6. foodstore no se tocó.
[ "$(huella_foodstore)" = "$huella_antes" ] || falla "foodstore cambió"

echo "test_restore: OK"
