#!/usr/bin/env bash
# test_carga_cache: valida la recarga de producto_cache desde la instantanea (upsert, nunca borrar).
export PATH="$PATH:/d/DevTools/miniconda3/Library/bin"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$RAIZ/tests/fixtures"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
D="$TMP"
DB="movil/foodstore_movil.db"
U1='11111111-1111-4111-8111-111111111111'

falla() { echo "test_carga_cache: FALLA - $1"; exit 1; }
q() { (cd "$D" && sqlite3 "$DB" "$1" | tr -d '\r'); }
importar() { # csv
  cp "$1" "$D/movil/servidor_snapshot.csv"
  (cd "$D" && sqlite3 "$DB" < movil/importar_snapshot.sql > salida.txt 2>&1) || falla "el importador fallo con $(basename "$1"): $(cat "$D/salida.txt")"
}

mkdir -p "$D/movil"
cp "$RAIZ/movil/schema_sqlite.sql" "$RAIZ/movil/importar_snapshot.sql" "$D/movil/"
(cd "$D" && sqlite3 "$DB" < movil/schema_sqlite.sql) || falla "no se pudo crear el esquema"

# 1. Carga inicial: el cache queda igual a la instantanea.
importar "$FIX/snapshot_valido.csv"
[ "$(q "SELECT count(*) FROM producto_cache")" = "5" ] || falla "la carga inicial dejo $(q "SELECT count(*) FROM producto_cache") filas (se esperaban 5)"
dif="$(q "SELECT count(*) FROM snapshot_servidor s LEFT JOIN producto_cache c ON c.id=s.id WHERE c.id IS NULL OR c.nombre<>s.nombre OR c.precio_centavos<>s.precio_centavos OR c.stock_visto<>s.stock OR c.disponible<>s.disponible OR c.eliminado<>s.eliminado OR c.copiado_en<>s.copiado_en")"
[ "$dif" = "0" ] || falla "$dif filas del cache difieren de snapshot_servidor tras la carga inicial"

# Un borrador que referencia los productos 3 y 4 (para probar que las lapidas no rompen las FKs).
(cd "$D" && sqlite3 "$DB" "PRAGMA foreign_keys=ON;
  INSERT INTO pedido_borrador (id_local,usuario,forma_pago) VALUES ('$U1','vendedor_feria_1','EFECTIVO');
  INSERT INTO item_borrador VALUES ('$U1',3,1,180000);
  INSERT INTO item_borrador VALUES ('$U1',4,2,320000);") || falla "no se pudo armar el borrador de prueba"

# 2. Precio cambiado: se actualiza, y copiado_en pasa a ser el de la nueva instantanea.
importar "$FIX/snapshot_s1_precio.csv"
[ "$(q "SELECT precio_centavos FROM producto_cache WHERE id=1")" = "299900" ] || falla "el precio del producto 1 no se actualizo (es $(q "SELECT precio_centavos FROM producto_cache WHERE id=1"))"
[ "$(q "SELECT group_concat(DISTINCT copiado_en) FROM producto_cache")" = "2026-11-02T09:00:00Z" ] || falla "copiado_en del cache no es el de la ultima instantanea"
[ "$(q "SELECT count(*) FROM producto_cache")" = "5" ] || falla "tras el cambio de precio hay $(q "SELECT count(*) FROM producto_cache") filas"

# 3. Producto dado de baja: la fila sigue con eliminado=1 y el item que la referencia sigue valido.
importar "$FIX/snapshot_s1_baja.csv"
[ "$(q "SELECT eliminado||','||disponible FROM producto_cache WHERE id=3")" = "1,0" ] || falla "el producto 3 dado de baja no quedo eliminado=1, disponible=0"
[ "$(q "SELECT count(*) FROM producto_cache")" = "5" ] || falla "la baja borro filas del cache"
[ "$(q "PRAGMA foreign_keys=ON; PRAGMA foreign_key_check")" = "" ] || falla "foreign_key_check reporta filas huerfanas tras la baja"
[ "$(q "SELECT count(*) FROM item_borrador i JOIN producto_cache c ON c.id=i.producto_id WHERE i.producto_id=3")" = "1" ] || falla "el item del producto 3 ya no encuentra su producto"
# El catalogo disponible (C1) ya no lo muestra.
[ "$(q "SELECT count(*) FROM producto_cache WHERE disponible=1 AND eliminado=0 AND id=3")" = "0" ] || falla "el producto dado de baja sigue en el catalogo disponible"

# 4. Producto ausente de la instantanea: se marca eliminado=1, disponible=0 y no se borra.
importar "$FIX/snapshot_s1_ausente.csv"
[ "$(q "SELECT count(*) FROM producto_cache WHERE id=4")" = "1" ] || falla "el producto ausente (4) fue borrado del cache"
[ "$(q "SELECT eliminado||','||disponible FROM producto_cache WHERE id=4")" = "1,0" ] || falla "el producto ausente (4) no quedo eliminado=1, disponible=0"
[ "$(q "PRAGMA foreign_keys=ON; PRAGMA foreign_key_check")" = "" ] || falla "foreign_key_check reporta filas huerfanas tras el producto ausente"
[ "$(q "SELECT eliminado FROM producto_cache WHERE id=1")" = "0" ] || falla "un producto presente (1) quedo marcado eliminado"

# 5. Triangulacion: si el producto vuelve a aparecer, deja de estar eliminado.
importar "$FIX/snapshot_valido.csv"
[ "$(q "SELECT eliminado||','||disponible FROM producto_cache WHERE id=4")" = "0,1" ] || falla "el producto 4 no se recupero cuando volvio a la instantanea"
[ "$(q "SELECT eliminado||','||disponible FROM producto_cache WHERE id=3")" = "0,1" ] || falla "el producto 3 no se recupero cuando volvio a la instantanea"

# 6. Una instantanea incompleta no toca el cache: queda exactamente como antes.
antes="$(q "SELECT group_concat(id||':'||precio_centavos||':'||eliminado||':'||copiado_en, ';') FROM (SELECT * FROM producto_cache ORDER BY id)")"
cp "$FIX/snapshot_incompleto.csv" "$D/movil/servidor_snapshot.csv"
(cd "$D" && sqlite3 "$DB" < movil/importar_snapshot.sql > salida.txt 2>&1) && falla "el CSV incompleto no hizo fallar el importador"
despues="$(q "SELECT group_concat(id||':'||precio_centavos||':'||eliminado||':'||copiado_en, ';') FROM (SELECT * FROM producto_cache ORDER BY id)")"
[ "$antes" = "$despues" ] || falla "una instantanea incompleta modifico producto_cache"

echo "test_carga_cache: OK"
