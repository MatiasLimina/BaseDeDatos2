#!/usr/bin/env bash
# test_esquema_sqlite: valida movil/schema_sqlite.sql sobre una base temporal.
export PATH="$PATH:/d/DevTools/miniconda3/Library/bin"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
DB="$TMP/t.db"
SCHEMA="$RAIZ/movil/schema_sqlite.sql"
U1='11111111-1111-4111-8111-111111111111'
U2='22222222-2222-4222-8222-222222222222'

falla() { echo "test_esquema_sqlite: FALLA - $1"; exit 1; }

[ -f "$SCHEMA" ] || falla "no existe movil/schema_sqlite.sql"
sqlite3 -bail "$DB" < "$SCHEMA" 2>"$TMP/err" || falla "el esquema no se ejecuta: $(cat "$TMP/err")"

# La primera sentencia debe ser el PRAGMA (se ignoran comentarios y líneas vacías).
q() { sqlite3 "$@" | tr -d '\r'; }
primera="$(grep -v -E '^\s*(--|$)' "$SCHEMA" | head -1 | tr -d '\r')"
[ "$primera" = "PRAGMA foreign_keys = ON;" ] || falla "la primera sentencia no es PRAGMA foreign_keys = ON; (es: $primera)"

# Las 5 tablas existen y son STRICT.
for t in producto_cache pedido_borrador item_borrador cola_sync snapshot_servidor; do
  s="$(q "$DB" "SELECT strict FROM pragma_table_list WHERE name='$t' AND schema='main'")"
  [ "$s" = "1" ] || falla "la tabla $t no existe o no es STRICT (strict='$s')"
done

fk() { q "$DB" "SELECT group_concat(\"table\", ',') FROM (SELECT \"table\" FROM pragma_foreign_key_list('$1') ORDER BY \"table\")"; }
# Claves foráneas esperadas.
[ "$(fk item_borrador)" = "pedido_borrador,producto_cache" ] || falla "FKs de item_borrador: $(fk item_borrador)"
[ "$(fk cola_sync)" = "pedido_borrador" ] || falla "FKs de cola_sync: $(fk cola_sync)"

sql() { sqlite3 -bail "$DB" "PRAGMA foreign_keys = ON; $1" 2>&1; }
acepta() { # descripcion, sql
  out="$(sql "$2")"; rc=$?
  [ $rc -eq 0 ] || falla "debía aceptar: $1 ($out)"
}
rechaza() { # descripcion, sql
  out="$(sql "$2")"; rc=$?
  [ $rc -ne 0 ] || falla "debía rechazar: $1"
}
base="INSERT INTO producto_cache VALUES (1,'Cola',275000,48,1,0,'2026-11-01T00:00:00Z');
INSERT INTO producto_cache VALUES (2,'Papas',180000,29,1,0,'2026-11-01T00:00:00Z');
INSERT INTO pedido_borrador (id_local,usuario,forma_pago) VALUES ('$U1','vendedor_feria_1','EFECTIVO');"
acepta "datos válidos de base" "$base"

# Rechazos de dominio en producto_cache.
rechaza "precio negativo" "INSERT INTO producto_cache VALUES (3,'X',-1,5,1,0,'2026-11-01T00:00:00Z');"
rechaza "disponible = 2" "INSERT INTO producto_cache VALUES (3,'X',100,5,2,0,'2026-11-01T00:00:00Z');"
rechaza "eliminado = 't'" "INSERT INTO producto_cache VALUES (3,'X',100,5,1,'t','2026-11-01T00:00:00Z');"
rechaza "precio 12.5" "INSERT INTO producto_cache VALUES (3,'X',12.5,5,1,0,'2026-11-01T00:00:00Z');"
rechaza "stock negativo" "INSERT INTO producto_cache VALUES (3,'X',100,-5,1,0,'2026-11-01T00:00:00Z');"

# Rechazos en pedido_borrador.
rechaza "forma de pago OTRO" "INSERT INTO pedido_borrador (id_local,usuario,forma_pago) VALUES ('$U2','v','OTRO');"
rechaza "id_local = 'pedido-1'" "INSERT INTO pedido_borrador (id_local,usuario,forma_pago) VALUES ('pedido-1','v','EFECTIVO');"
rechaza "UUID con guiones mal puestos" "INSERT INTO pedido_borrador (id_local,usuario,forma_pago) VALUES ('22222222222222222222222222222222----','v','EFECTIVO');"
acepta "forma de pago TARJETA" "INSERT INTO pedido_borrador (id_local,usuario,forma_pago) VALUES ('$U2','v','TARJETA');"

# Ítems.
acepta "ítem válido" "INSERT INTO item_borrador VALUES ('$U1',1,2,275000);"
rechaza "ítem con cantidad 0" "INSERT INTO item_borrador VALUES ('$U1',2,0,180000);"
rechaza "producto repetido en el borrador" "INSERT INTO item_borrador VALUES ('$U1',1,3,275000);"
rechaza "ítem de borrador inexistente" "INSERT INTO item_borrador VALUES ('33333333-3333-4333-8333-333333333333',1,1,275000);"
rechaza "ítem de producto inexistente" "INSERT INTO item_borrador VALUES ('$U1',999,1,100);"

# Solicitudes.
rechaza "estado APROBADO" "INSERT INTO cola_sync (solicitud_uuid,id_local,estado) VALUES ('44444444-4444-4444-8444-444444444444','$U1','APROBADO');"
acepta "solicitud sin estado" "INSERT INTO cola_sync (solicitud_uuid,id_local) VALUES ('44444444-4444-4444-8444-444444444444','$U1');"
est="$(q "$DB" "SELECT estado FROM cola_sync WHERE solicitud_uuid='44444444-4444-4444-8444-444444444444'")"
[ "$est" = "PENDIENTE" ] || falla "la solicitud sin estado nació '$est' en vez de PENDIENTE"
rechaza "solicitud con UUID repetido" "INSERT INTO cola_sync (solicitud_uuid,id_local) VALUES ('44444444-4444-4444-8444-444444444444','$U1');"
rechaza "solicitud de borrador inexistente" "INSERT INTO cola_sync (solicitud_uuid,id_local) VALUES ('55555555-5555-4555-8555-555555555555','33333333-3333-4333-8333-333333333333');"

# Sin ON DELETE CASCADE: no se puede borrar un borrador con ítems.
rechaza "borrar borrador con ítems" "DELETE FROM pedido_borrador WHERE id_local='$U1';"

# snapshot_servidor: mismas columnas y orden que la vista.
cols="$(q "$DB" "SELECT group_concat(name,',') FROM (SELECT name FROM pragma_table_info('snapshot_servidor') ORDER BY cid)")"
[ "$cols" = "id,nombre,precio_centavos,stock,disponible,eliminado,copiado_en,filas_copia" ] || falla "columnas de snapshot_servidor: $cols"
rechaza "snapshot con t/f" "INSERT INTO snapshot_servidor VALUES (1,'X',100,5,'t','f','2026-11-01T00:00:00Z',1);"

# Triangulación: UUID en mayúsculas rechazado (solo hexadecimal en minúsculas).
rechaza "UUID en mayúsculas" "INSERT INTO pedido_borrador (id_local,usuario,forma_pago) VALUES ('AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA','v','EFECTIVO');"
rechaza "solicitud con UUID en mayúsculas" "INSERT INTO cola_sync (solicitud_uuid,id_local) VALUES ('AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA','$U1');"

# Triangulación: re-ejecutar el esquema sobre la misma base deja las tablas vacías y el mismo sqlite_schema.
antes="$(q "$DB" "SELECT group_concat(sql, ';') FROM (SELECT sql FROM sqlite_schema WHERE type='table' ORDER BY name)")"
sqlite3 -bail "$DB" < "$SCHEMA" 2>"$TMP/err" || falla "re-ejecutar el esquema falló: $(cat "$TMP/err")"
despues="$(q "$DB" "SELECT group_concat(sql, ';') FROM (SELECT sql FROM sqlite_schema WHERE type='table' ORDER BY name)")"
[ "$antes" = "$despues" ] || falla "sqlite_schema cambió al re-ejecutar el esquema"
for t in producto_cache pedido_borrador item_borrador cola_sync snapshot_servidor; do
  n="$(q "$DB" "SELECT count(*) FROM $t")"
  [ "$n" = "0" ] || falla "tras re-ejecutar, $t tiene $n filas (debía quedar vacía)"
done

echo "test_esquema_sqlite: OK"
