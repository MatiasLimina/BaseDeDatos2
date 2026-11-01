#!/usr/bin/env bash
# test_vista_snapshot: valida v_snapshot_movil en food_store_copia (solo lectura).
# Requiere psql con autenticacion por pgpass.conf (sin PGPASSWORD).
export PATH="$PATH:/d/DevTools/PosgresSQL/bin"
export PGCLIENTENCODING=UTF8
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ" || exit 1

falla() { echo "test_vista_snapshot: FALLA - $1"; exit 1; }
q() { psql -X -w -h localhost -U postgres -d food_store_copia -v ON_ERROR_STOP=1 -At -c "$1" 2>&1 | tr -d '\r'; }

[ "$(q 'SELECT current_database()')" = "food_store_copia" ] || falla "no se pudo consultar food_store_copia: $(q 'SELECT 1')"

# La vista existe con las columnas en el orden esperado.
cols="$(q "SELECT string_agg(column_name, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='public' AND table_name='v_snapshot_movil'")"
[ "$cols" = "id,nombre,precio_centavos,stock,disponible,eliminado,copiado_en,filas_copia" ] || falla "la vista no existe o sus columnas son: '$cols'"

# Banderas 0/1 y sin nulos.
[ "$(q "SELECT count(*) FROM v_snapshot_movil WHERE disponible NOT IN (0,1) OR eliminado NOT IN (0,1)")" = "0" ] || falla "hay banderas fuera de {0,1}"
[ "$(q "SELECT count(*) FROM v_snapshot_movil v WHERE v.id IS NULL OR v.nombre IS NULL OR v.precio_centavos IS NULL OR v.stock IS NULL OR v.disponible IS NULL OR v.eliminado IS NULL OR v.copiado_en IS NULL OR v.filas_copia IS NULL")" = "0" ] || falla "hay columnas nulas"

# Conteos.
n_vista="$(q "SELECT count(*) FROM v_snapshot_movil")"
n_prod="$(q "SELECT count(*) FROM producto")"
filas="$(q "SELECT DISTINCT filas_copia FROM v_snapshot_movil")"
[ "$n_vista" = "$n_prod" ] && [ "$n_vista" = "$filas" ] || falla "conteos distintos: vista=$n_vista producto=$n_prod filas_copia=$filas"

# Inactivos = eliminados; activo con stock 0 = no disponible pero no eliminado.
[ "$(q "SELECT count(*) FROM v_snapshot_movil v JOIN producto p USING (id) WHERE NOT p.activo AND NOT (v.eliminado=1 AND v.disponible=0)")" = "0" ] || falla "algun inactivo no quedo eliminado=1, disponible=0"
[ "$(q "SELECT count(*) FROM v_snapshot_movil WHERE eliminado=1")" = "$(q "SELECT count(*) FROM producto WHERE NOT activo")" ] || falla "la cantidad de eliminados no coincide con la de inactivos"
[ "$(q "SELECT count(*) FROM v_snapshot_movil v JOIN producto p USING (id) WHERE p.activo AND p.stock=0")" -gt 0 ] || falla "no hay activos con stock 0 para probar"
[ "$(q "SELECT count(*) FROM v_snapshot_movil v JOIN producto p USING (id) WHERE p.activo AND p.stock=0 AND NOT (v.disponible=0 AND v.eliminado=0)")" = "0" ] || falla "un activo con stock 0 no quedo disponible=0, eliminado=0"
[ "$(q "SELECT count(*) FROM v_snapshot_movil v JOIN producto p USING (id) WHERE p.activo AND p.stock>0 AND NOT (v.disponible=1 AND v.eliminado=0)")" = "0" ] || falla "un activo con stock no quedo disponible=1, eliminado=0"

# Precio en centavos y una sola fecha de copia.
[ "$(q "SELECT count(*) FROM v_snapshot_movil v JOIN producto p USING (id) WHERE v.precio_centavos <> round(p.precio*100) OR v.stock <> p.stock")" = "0" ] || falla "precio_centavos o stock no coinciden con producto"
[ "$(q "SELECT count(DISTINCT copiado_en) FROM v_snapshot_movil")" = "1" ] || falla "hay mas de una copiado_en"
[ "$(q "SELECT count(*) FROM v_snapshot_movil WHERE copiado_en !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'")" = "0" ] || falla "copiado_en no es ISO-8601 UTC"

# El esquema de las tablas base no cambio respecto de la evidencia previa.
actual="$(q "SELECT c.table_name || ': ' || string_agg(c.column_name || ':' || c.data_type, ', ' ORDER BY c.ordinal_position) FROM information_schema.columns c JOIN information_schema.tables t ON t.table_schema=c.table_schema AND t.table_name=c.table_name WHERE c.table_schema='public' AND t.table_type='BASE TABLE' GROUP BY c.table_name ORDER BY 1")"
esperado="$(tr -d '\r' < evidencias/esquema_servidor_antes.txt)"
[ "$actual" = "$esperado" ] || falla "el esquema de las tablas base cambio respecto de evidencias/esquema_servidor_antes.txt"

# Exportacion (S0): el CSV tiene filas_copia + 1 lineas y es UTF-8.
CSV=movil/servidor_snapshot.csv
[ -f "$CSV" ] || falla "no existe $CSV (falta correr sql/02_exportar_snapshot.sql)"
lineas="$(wc -l < "$CSV" | tr -d ' \r')"
[ "$lineas" = "$((filas + 1))" ] || falla "el CSV tiene $lineas lineas, se esperaban $((filas + 1))"
iconv -f UTF-8 -t UTF-8 "$CSV" > /dev/null 2>&1 || falla "el CSV no es UTF-8 valido"
[ "$(head -1 "$CSV" | tr -d '\r')" = "id,nombre,precio_centavos,stock,disponible,eliminado,copiado_en,filas_copia" ] || falla "encabezado del CSV inesperado"

echo "test_vista_snapshot: OK"
