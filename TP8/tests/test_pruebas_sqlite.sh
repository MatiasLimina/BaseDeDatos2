#!/usr/bin/env bash
# test_pruebas_sqlite: valida transacciones atomicas (COMMIT y ROLLBACK), catalogo offline (C1) y rechazo de datos invalidos (C7).
export PATH="$PATH:/d/DevTools/miniconda3/Library/bin"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$RAIZ/tests/fixtures"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
D="$TMP"
DB="movil/foodstore_movil.db"

falla() { echo "test_pruebas_sqlite: FALLA - $1"; exit 1; }
q() { (cd "$D" && sqlite3 "$DB" "$1" | tr -d '\r'); }

mkdir -p "$D/movil"
cp "$RAIZ/movil/schema_sqlite.sql" "$RAIZ/movil/importar_snapshot.sql" "$D/movil/"
(cd "$D" && sqlite3 "$DB" < movil/schema_sqlite.sql) || falla "no se pudo crear el esquema"

# Cargar fixture si no hay base real cargada
cp "$FIX/snapshot_valido.csv" "$D/movil/servidor_snapshot.csv"
(cd "$D" && sqlite3 "$DB" < movil/importar_snapshot.sql > /dev/null 2>&1) || falla "no se pudo cargar la instantanea de prueba"

[ -f "$RAIZ/movil/pruebas_sqlite.sql" ] || falla "movil/pruebas_sqlite.sql no existe"

n_ped_0="$(q "SELECT count(*) FROM pedido_borrador")"
n_item_0="$(q "SELECT count(*) FROM item_borrador")"
n_cola_0="$(q "SELECT count(*) FROM cola_sync")"
n_prod_0="$(q "SELECT count(*) FROM producto_cache")"

[ "$n_ped_0" = "0" ] && [ "$n_item_0" = "0" ] && [ "$n_cola_0" = "0" ] || falla "la base de prueba no inicio limpia"
[ "$n_prod_0" -gt "0" ] || falla "producto_cache no tiene filas"

# Ejecutar pruebas_sqlite.sql (salida a salida.txt; codigo != 0 esperado por los errores de C7 con .bail off)
(cd "$D" && sqlite3 "$DB" < "$RAIZ/movil/pruebas_sqlite.sql" > salida.txt 2>&1)

# 1. PRAGMA foreign_keys = 1 en la sesion
grep -q -E "^1$|foreign_keys.*1" "$D/salida.txt" || falla "PRAGMA foreign_keys no devolvio 1"

# 2. C7: errores esperados capturados en la salida
grep -i -q "CHECK constraint failed" "$D/salida.txt" || falla "C7 no mostro error de CHECK constraint"
grep -i -q "FOREIGN KEY constraint failed" "$D/salida.txt" || falla "C7 no mostro error de FOREIGN KEY constraint"

# 3. Estado de la base: exactamente un borrador (C5), un item y una solicitud PENDIENTE
[ "$(q "SELECT count(*) FROM pedido_borrador")" = "1" ] || falla "se esperaba 1 pedido_borrador, hay $(q "SELECT count(*) FROM pedido_borrador")"
[ "$(q "SELECT id_local FROM pedido_borrador")" = "c5000000-0000-4000-8000-000000000001" ] || falla "id_local de C5 no coincide"
[ "$(q "SELECT usuario FROM pedido_borrador")" = "vendedor_feria_1" ] || falla "usuario no es vendedor_feria_1"

[ "$(q "SELECT count(*) FROM item_borrador")" = "1" ] || falla "se esperaba 1 item_borrador, hay $(q "SELECT count(*) FROM item_borrador")"
[ "$(q "SELECT producto_id FROM item_borrador")" = "4" ] || falla "el item no es el producto D (id 4)"
[ "$(q "SELECT precio_centavos_visto FROM item_borrador")" = "320000" ] || falla "el precio visto no es 320000"

[ "$(q "SELECT count(*) FROM cola_sync")" = "1" ] || falla "se esperaba 1 solicitud en cola_sync, hay $(q "SELECT count(*) FROM cola_sync")"
[ "$(q "SELECT solicitud_uuid FROM cola_sync")" = "c5000000-0000-4000-8000-000000000002" ] || falla "solicitud_uuid no coincide"
[ "$(q "SELECT estado FROM cola_sync")" = "PENDIENTE" ] || falla "el estado de la solicitud no es PENDIENTE"

# La operacion con ROLLBACK no dejo filas a medias
[ "$(q "SELECT count(*) FROM pedido_borrador WHERE id_local <> 'c5000000-0000-4000-8000-000000000001'")" = "0" ] || falla "quedaron filas de la operacion deshecha con ROLLBACK"

# Los conteos de producto_cache no cambiaron
[ "$(q "SELECT count(*) FROM producto_cache")" = "$n_prod_0" ] || falla "producto_cache cambio durante las pruebas"

# 4. Caso C1: consulta del catalogo disponible offline en modo readonly
TMP_C1="$(mktemp -d)"
cp "$D/$DB" "$TMP_C1/cat.db"
cat_filas="$(sqlite3 -readonly "$TMP_C1/cat.db" "SELECT id, nombre, precio_centavos, stock_visto FROM producto_cache WHERE disponible = 1 AND eliminado = 0 ORDER BY id;" | tr -d '\r')"
[ -n "$cat_filas" ] || falla "C1: la consulta del catalogo disponible no devolvio filas"

# Ningun producto no disponible o eliminado debe figurar
disp_invalido="$(sqlite3 -readonly "$TMP_C1/cat.db" "SELECT count(*) FROM producto_cache WHERE disponible = 1 AND eliminado = 0 AND (disponible <> 1 OR eliminado <> 0);" | tr -d '\r')"
[ "$disp_invalido" = "0" ] || falla "C1: se devolvieron productos con disponible <> 1 o eliminado <> 0"
echo "$cat_filas" | grep -q "^2|" && falla "C1: producto sin stock (id 2) figura en el catalogo disponible"
echo "$cat_filas" | grep -q "^5|" && falla "C1: producto eliminado (id 5) figura en el catalogo disponible"
rm -rf "$TMP_C1"

# 5. Triangulacion: re-ejecutar pruebas_sqlite.sql falla por PK duplicada y no duplica filas
(cd "$D" && sqlite3 "$DB" < "$RAIZ/movil/pruebas_sqlite.sql" > salida2.txt 2>&1)
grep -i -q "UNIQUE constraint failed" "$D/salida2.txt" || falla "la re-ejecucion no reporto error de clave primaria"
[ "$(q "SELECT count(*) FROM pedido_borrador")" = "1" ] || falla "la re-ejecucion duplico pedido_borrador"
[ "$(q "SELECT count(*) FROM item_borrador")" = "1" ] || falla "la re-ejecucion duplico item_borrador"
[ "$(q "SELECT count(*) FROM cola_sync")" = "1" ] || falla "la re-ejecucion duplico cola_sync"

echo "test_pruebas_sqlite: OK"
