#!/usr/bin/env bash
# test_importacion: valida movil/importar_snapshot.sql (carga tipada de snapshot_servidor).
export PATH="$PATH:/d/DevTools/miniconda3/Library/bin"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$RAIZ/tests/fixtures"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

falla() { echo "test_importacion: FALLA - $1"; exit 1; }
q() { sqlite3 "$@" | tr -d '\r'; }

[ -f "$RAIZ/movil/importar_snapshot.sql" ] || falla "no existe movil/importar_snapshot.sql"

# Cada caso trabaja en su propia carpeta temporal con la misma estructura que TP8/ (movil/...).
nueva_carpeta() { # nombre -> crea $TMP/nombre/movil con esquema + script
  mkdir -p "$TMP/$1/movil"
  cp "$RAIZ/movil/schema_sqlite.sql" "$RAIZ/movil/importar_snapshot.sql" "$TMP/$1/movil/"
  (cd "$TMP/$1" && sqlite3 movil/foodstore_movil.db < movil/schema_sqlite.sql) || falla "no se pudo crear el esquema en $1"
}
importar() { # carpeta csv -> ejecuta el importador; devuelve su codigo
  cp "$2" "$TMP/$1/movil/servidor_snapshot.csv"
  (cd "$TMP/$1" && sqlite3 movil/foodstore_movil.db < movil/importar_snapshot.sql > salida.txt 2>&1)
}
cuenta() { (cd "$TMP/$1" && q movil/foodstore_movil.db "SELECT count(*) FROM snapshot_servidor"); }

# 1. CSV valido: 5 filas con tipos enteros.
nueva_carpeta ok
importar ok "$FIX/snapshot_valido.csv" || falla "el CSV valido hizo fallar el script: $(cat "$TMP/ok/salida.txt")"
[ "$(cuenta ok)" = "5" ] || falla "el CSV valido dejo $(cuenta ok) filas (se esperaban 5)"
tipos="$(cd "$TMP/ok" && q movil/foodstore_movil.db "SELECT count(*) FROM snapshot_servidor WHERE typeof(id)='integer' AND typeof(precio_centavos)='integer' AND typeof(stock)='integer' AND typeof(disponible)='integer' AND typeof(eliminado)='integer' AND typeof(filas_copia)='integer' AND typeof(nombre)='text'")"
[ "$tipos" = "5" ] || falla "solo $tipos de 5 filas tienen los tipos esperados (integer/text)"
coma="$(cd "$TMP/ok" && q movil/foodstore_movil.db "SELECT nombre FROM snapshot_servidor WHERE id=2")"
[ "$coma" = "Pan, lactal" ] || falla "el nombre con coma entre comillas se importo como '$coma'"

# 2. Importar dos veces reemplaza, no acumula.
importar ok "$FIX/snapshot_valido.csv" || falla "la segunda importacion fallo: $(cat "$TMP/ok/salida.txt")"
[ "$(cuenta ok)" = "5" ] || falla "importar dos veces dejo $(cuenta ok) filas (acumula)"

# 3. Banderas t/f: el script falla y la instantanea anterior queda intacta.
importar ok "$FIX/snapshot_tf.csv" && falla "el CSV con t/f no hizo fallar el script"
[ "$(cuenta ok)" = "5" ] || falla "tras el CSV con t/f quedaron $(cuenta ok) filas (se esperaban las 5 de antes)"
[ "$(cd "$TMP/ok" && q movil/foodstore_movil.db "SELECT count(*) FROM snapshot_servidor WHERE typeof(disponible)='integer'")" = "5" ] || falla "las filas anteriores cambiaron tras el CSV con t/f"

# 4. CSV incompleto (4 filas, filas_copia = 5): falla y deja lo anterior.
importar ok "$FIX/snapshot_incompleto.csv" && falla "el CSV incompleto no hizo fallar el script"
[ "$(cuenta ok)" = "5" ] || falla "tras el CSV incompleto quedaron $(cuenta ok) filas (se esperaban 5)"

# 4b. Lo mismo sobre una base vacia: no queda nada cargado.
nueva_carpeta vacia
importar vacia "$FIX/snapshot_incompleto.csv" && falla "el CSV incompleto no hizo fallar el script (base vacia)"
[ "$(cuenta vacia)" = "0" ] || falla "el CSV incompleto dejo $(cuenta vacia) filas en una base vacia"
importar vacia "$FIX/snapshot_tf.csv" && falla "el CSV con t/f no hizo fallar el script (base vacia)"
[ "$(cuenta vacia)" = "0" ] || falla "el CSV con t/f dejo $(cuenta vacia) filas en una base vacia"

# 5. Fin de linea \r\n: nunca se carga basura (copiado_en sin char(13)) o el script falla.
sed 's/$/\r/' "$FIX/snapshot_valido.csv" > "$TMP/crlf.csv"
[ "$(head -c 200 "$TMP/crlf.csv" | grep -c $'\r')" -ge 1 ] || falla "no se pudo armar el CSV con \r\n"
nueva_carpeta crlf
if importar crlf "$TMP/crlf.csv"; then
  basura="$(cd "$TMP/crlf" && q movil/foodstore_movil.db "SELECT count(*) FROM snapshot_servidor WHERE instr(copiado_en, char(13)) > 0 OR instr(nombre, char(13)) > 0")"
  [ "$basura" = "0" ] || falla "con \r\n se cargaron $basura filas con char(13)"
  [ "$(cuenta crlf)" = "5" ] || falla "con \r\n el script termino bien pero dejo $(cuenta crlf) filas"
else
  [ "$(cuenta crlf)" = "0" ] || falla "con \r\n el script fallo pero dejo $(cuenta crlf) filas cargadas"
fi

# 6. Triangulacion: CSV con una fila de mas respecto de filas_copia tambien falla.
{ cat "$FIX/snapshot_valido.csv"; echo '6,Fila extra,100,1,1,0,2026-11-01T10:00:00Z,5'; } > "$TMP/extra.csv"
importar ok "$TMP/extra.csv" && falla "el CSV con una fila de mas no hizo fallar el script"
[ "$(cuenta ok)" = "5" ] || falla "tras el CSV con fila de mas quedaron $(cuenta ok) filas (se esperaban 5)"

echo "test_importacion: OK"
