#!/usr/bin/env bash
# test_casos: valida los estados y evidencias de los casos C2 a C6 en SQLite,
# y que PostgreSQL quedo identico a la linea base tras la restauracion.
export PATH="$PATH:/d/DevTools/miniconda3/Library/bin:/d/DevTools/PosgresSQL/bin"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
DB="$RAIZ/movil/foodstore_movil.db"
EVID="$RAIZ/evidencias"

falla() { echo "test_casos: FALLA - $1"; exit 1; }
q() { sqlite3 "$DB" "$1" | tr -d '\r'; }

# 1. Comprobar que la base SQLite de la tablet existe
[ -f "$DB" ] || falla "movil/foodstore_movil.db no existe (ejecutar scripts/correr_casos.sh)"

# 2. Caso C5: SIMULADO_APROBADO
c5_estado="$(q "SELECT estado FROM cola_sync WHERE solicitud_uuid='c5000000-0000-4000-8000-000000000002'")"
[ "$c5_estado" = "SIMULADO_APROBADO" ] || falla "C5: se esperaba SIMULADO_APROBADO, es $c5_estado"

# 3. Caso C6: reintento del mismo UUID produce error de PK, no duplica y no reevalua
c6_filas="$(q "SELECT count(*) FROM cola_sync WHERE solicitud_uuid='c5000000-0000-4000-8000-000000000002'")"
[ "$c6_filas" = "1" ] || falla "C6: solicitud_uuid de C5 aparece $c6_filas veces (esperado 1)"
[ -f "$EVID/c6_reintento.txt" ] || falla "evidencias/c6_reintento.txt no existe"
grep -i -q "UNIQUE constraint failed" "$EVID/c6_reintento.txt" || falla "C6: la evidencia no muestra error de UNIQUE constraint"

# 4. Caso C2: solicitud original en CONFLICTO y nueva solicitud en SIMULADO_APROBADO
c2_orig="$(q "SELECT estado FROM cola_sync WHERE solicitud_uuid='c2000000-0000-4000-8000-000000000002'")"
[ "$c2_orig" = "CONFLICTO" ] || falla "C2 original: se esperaba CONFLICTO, es $c2_orig"
c2_nueva="$(q "SELECT estado FROM cola_sync WHERE solicitud_uuid='c2000000-0000-4000-8000-000000000003'")"
[ "$c2_nueva" = "SIMULADO_APROBADO" ] || falla "C2 nueva (aceptada): se esperaba SIMULADO_APROBADO, es $c2_nueva"
c2_prec_visto="$(q "SELECT precio_centavos_visto FROM item_borrador WHERE id_local='c2000000-0000-4000-8000-000000000001' AND producto_id=1")"
[ "$c2_prec_visto" = "299000" ] || falla "C2: precio visto no se actualizo al de la instantanea (es $c2_prec_visto)"

# 5. Caso C3: RECHAZADO por stock insuficiente
c3_estado="$(q "SELECT estado FROM cola_sync WHERE solicitud_uuid='c3000000-0000-4000-8000-000000000002'")"
[ "$c3_estado" = "RECHAZADO" ] || falla "C3: se esperaba RECHAZADO, es $c3_estado"
c3_motivo="$(q "SELECT motivo FROM cola_sync WHERE solicitud_uuid='c3000000-0000-4000-8000-000000000002'")"
echo "$c3_motivo" | grep -i -q "stock" || falla "C3: motivo no menciona stock ($c3_motivo)"

# 6. Caso C4: RECHAZADO por producto dado de baja; la fila sigue en producto_cache fuera del catalogo disponible
c4_estado="$(q "SELECT estado FROM cola_sync WHERE solicitud_uuid='c4000000-0000-4000-8000-000000000002'")"
[ "$c4_estado" = "RECHAZADO" ] || falla "C4: se esperaba RECHAZADO, es $c4_estado"
c4_motivo="$(q "SELECT motivo FROM cola_sync WHERE solicitud_uuid='c4000000-0000-4000-8000-000000000002'")"
echo "$c4_motivo" | grep -i -q "baja" || falla "C4: motivo no menciona baja ($c4_motivo)"
c4_cache="$(q "SELECT count(*)||','||eliminado||','||disponible FROM producto_cache WHERE id=3")"
[ "$c4_cache" = "1,1,0" ] || falla "C4: producto 3 en producto_cache no quedo con eliminado=1, disponible=0 ($c4_cache)"
c4_cat_disp="$(q "SELECT count(*) FROM producto_cache WHERE disponible=1 AND eliminado=0 AND id=3")"
[ "$c4_cat_disp" = "0" ] || falla "C4: producto 3 sigue en el catalogo disponible"

# 7. Verificacion de linea base de PostgreSQL vs verificacion final
[ -f "$EVID/linea_base.txt" ] || falla "evidencias/linea_base.txt no existe"
[ -f "$EVID/verificacion_final.txt" ] || falla "evidencias/verificacion_final.txt no existe"

grep -E "^pedidos=" "$EVID/linea_base.txt" > "$RAIZ/tests/lb_p.tmp"
grep -E "^pedidos=" "$EVID/verificacion_final.txt" > "$RAIZ/tests/vf_p.tmp"
diff -u "$RAIZ/tests/lb_p.tmp" "$RAIZ/tests/vf_p.tmp" > /dev/null || falla "PostgreSQL: conteo de pedidos cambio respecto de la linea base"

grep -E "^productos=" "$EVID/linea_base.txt" > "$RAIZ/tests/lb_prod.tmp"
grep -E "^productos=" "$EVID/verificacion_final.txt" > "$RAIZ/tests/vf_prod.tmp"
diff -u "$RAIZ/tests/lb_prod.tmp" "$RAIZ/tests/vf_prod.tmp" > /dev/null || falla "PostgreSQL: conteo de productos cambio respecto de la linea base"

grep -E "^suma_stock=" "$EVID/linea_base.txt" > "$RAIZ/tests/lb_s.tmp"
grep -E "^suma_stock=" "$EVID/verificacion_final.txt" > "$RAIZ/tests/vf_s.tmp"
diff -u "$RAIZ/tests/lb_s.tmp" "$RAIZ/tests/vf_s.tmp" > /dev/null || falla "PostgreSQL: suma_stock cambio respecto de la linea base"

grep -E "^huella_producto=" "$EVID/linea_base.txt" > "$RAIZ/tests/lb_h.tmp"
grep -E "^huella_producto=" "$EVID/verificacion_final.txt" > "$RAIZ/tests/vf_h.tmp"
diff -u "$RAIZ/tests/lb_h.tmp" "$RAIZ/tests/vf_h.tmp" > /dev/null || falla "PostgreSQL: la huella_producto cambio (no se restauro el catalogo)"

rm -f "$RAIZ/tests/"*.tmp

echo "test_casos: OK"
