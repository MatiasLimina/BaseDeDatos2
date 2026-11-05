#!/usr/bin/env bash
# test_semaforo: valida la simulacion de sincronizacion (semaforo rojo, amarillo, verde),
# prioridad de rechazo sobre conflicto, trazabilidad, estabilidad e idempotencia.
export PATH="$PATH:/d/DevTools/miniconda3/Library/bin"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
D="$TMP"
DB="movil/foodstore_movil.db"

falla() { echo "test_semaforo: FALLA - $1"; exit 1; }
q() { (cd "$D" && sqlite3 "$DB" "$1" | tr -d '\r'); }

mkdir -p "$D/movil"
cp "$RAIZ/movil/schema_sqlite.sql" "$D/movil/"
(cd "$D" && sqlite3 "$DB" < movil/schema_sqlite.sql) || falla "no se pudo crear el esquema"

[ -f "$RAIZ/movil/semaforo.sql" ] || falla "movil/semaforo.sql no existe"

# Preparar datos sinteticos para probar cada rama del semaforo
(cd "$D" && sqlite3 "$DB" << 'EOF'
PRAGMA foreign_keys = ON;

-- 1. Snapshot del servidor con fecha de copia y filas
INSERT INTO snapshot_servidor (id, nombre, precio_centavos, stock, disponible, eliminado, copiado_en, filas_copia) VALUES
  (1, 'Coca Cola 1.5L', 275000, 48, 1, 0, '2026-11-01T12:00:00Z', 8),
  (2, 'Pan lactal', 120050, 0, 0, 0, '2026-11-01T12:00:00Z', 8),
  (3, 'Papas Fritas 150g', 180000, 29, 1, 0, '2026-11-01T12:00:00Z', 8),
  (4, 'Queso Tybo x 200g', 320000, 15, 1, 0, '2026-11-01T12:00:00Z', 8),
  (5, 'Galletitas', 50000, 10, 0, 1, '2026-11-01T12:00:00Z', 8),
  (7, 'Yerba 500g', 350000, 50, 1, 0, '2026-11-01T12:00:00Z', 8),
  (8, 'Cafe 250g', 400000, 50, 1, 0, '2026-11-01T12:00:00Z', 8),
  (9, 'Cerveza', 250000, 10, 0, 1, '2026-11-01T12:00:00Z', 8);
-- Nota: id 6 existe en producto_cache pero NO en snapshot_servidor (producto ausente en el servidor)

INSERT INTO producto_cache (id, nombre, precio_centavos, stock_visto, disponible, eliminado, copiado_en) VALUES
  (1, 'Coca Cola 1.5L', 275000, 48, 1, 0, '2026-11-01T12:00:00Z'),
  (2, 'Pan lactal', 120050, 0, 0, 0, '2026-11-01T12:00:00Z'),
  (3, 'Papas Fritas 150g', 180000, 29, 1, 0, '2026-11-01T12:00:00Z'),
  (4, 'Queso Tybo x 200g', 320000, 15, 1, 0, '2026-11-01T12:00:00Z'),
  (5, 'Galletitas', 50000, 10, 0, 1, '2026-11-01T12:00:00Z'),
  (6, 'Alfajor', 200000, 20, 1, 0, '2026-11-01T10:00:00Z'),
  (7, 'Yerba 500g', 300000, 50, 1, 0, '2026-11-01T10:00:00Z'),
  (8, 'Cafe 250g', 450000, 50, 1, 0, '2026-11-01T10:00:00Z'),
  (9, 'Cerveza', 220000, 10, 1, 0, '2026-11-01T10:00:00Z');

-- 2. Borradores y solicitudes (una por cada rama)
-- R1: Producto inexistente en snapshot_servidor (id 6)
INSERT INTO pedido_borrador VALUES ('10000000-0000-4000-8000-000000000001','vend1','EFECTIVO','2026-11-01T12:00:00Z');
INSERT INTO item_borrador VALUES ('10000000-0000-4000-8000-000000000001',6,1,200000);
INSERT INTO cola_sync (solicitud_uuid,id_local) VALUES ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001');

-- R2: Producto dado de baja (id 5, eliminado=1)
INSERT INTO pedido_borrador VALUES ('10000000-0000-4000-8000-000000000002','vend1','EFECTIVO','2026-11-01T12:00:00Z');
INSERT INTO item_borrador VALUES ('10000000-0000-4000-8000-000000000002',5,1,50000);
INSERT INTO cola_sync (solicitud_uuid,id_local) VALUES ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002');

-- R3: Producto no disponible (id 2, disponible=0)
INSERT INTO pedido_borrador VALUES ('10000000-0000-4000-8000-000000000003','vend1','EFECTIVO','2026-11-01T12:00:00Z');
INSERT INTO item_borrador VALUES ('10000000-0000-4000-8000-000000000003',2,1,120050);
INSERT INTO cola_sync (solicitud_uuid,id_local) VALUES ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000003');

-- R4: Cantidad > stock (id 4, pide 20, stock 15)
INSERT INTO pedido_borrador VALUES ('10000000-0000-4000-8000-000000000004','vend1','EFECTIVO','2026-11-01T12:00:00Z');
INSERT INTO item_borrador VALUES ('10000000-0000-4000-8000-000000000004',4,20,320000);
INSERT INTO cola_sync (solicitud_uuid,id_local) VALUES ('20000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000004');

-- R5: Precio sube (id 7, visto 300000, actual 350000)
INSERT INTO pedido_borrador VALUES ('10000000-0000-4000-8000-000000000005','vend1','EFECTIVO','2026-11-01T12:00:00Z');
INSERT INTO item_borrador VALUES ('10000000-0000-4000-8000-000000000005',7,1,300000);
INSERT INTO cola_sync (solicitud_uuid,id_local) VALUES ('20000000-0000-4000-8000-000000000005','10000000-0000-4000-8000-000000000005');

-- R6: Precio baja (id 8, visto 450000, actual 400000)
INSERT INTO pedido_borrador VALUES ('10000000-0000-4000-8000-000000000006','vend1','EFECTIVO','2026-11-01T12:00:00Z');
INSERT INTO item_borrador VALUES ('10000000-0000-4000-8000-000000000006',8,1,450000);
INSERT INTO cola_sync (solicitud_uuid,id_local) VALUES ('20000000-0000-4000-8000-000000000006','10000000-0000-4000-8000-000000000006');

-- R7: Todo coincide (id 1, visto 275000, pide 2, stock 48, disponible 1, eliminado 0)
INSERT INTO pedido_borrador VALUES ('10000000-0000-4000-8000-000000000007','vend1','EFECTIVO','2026-11-01T12:00:00Z');
INSERT INTO item_borrador VALUES ('10000000-0000-4000-8000-000000000007',1,2,275000);
INSERT INTO cola_sync (solicitud_uuid,id_local) VALUES ('20000000-0000-4000-8000-000000000007','10000000-0000-4000-8000-000000000007');

-- R8: Baja + precio cambiado (id 9, eliminado=1 y precio visto 220000 vs actual 250000: rojo gana)
INSERT INTO pedido_borrador VALUES ('10000000-0000-4000-8000-000000000008','vend1','EFECTIVO','2026-11-01T12:00:00Z');
INSERT INTO item_borrador VALUES ('10000000-0000-4000-8000-000000000008',9,1,220000);
INSERT INTO cola_sync (solicitud_uuid,id_local) VALUES ('20000000-0000-4000-8000-000000000008','10000000-0000-4000-8000-000000000008');

-- R9: Borrador vacio (sin items en item_borrador)
INSERT INTO pedido_borrador VALUES ('10000000-0000-4000-8000-000000000009','vend1','EFECTIVO','2026-11-01T12:00:00Z');
INSERT INTO cola_sync (solicitud_uuid,id_local) VALUES ('20000000-0000-4000-8000-000000000009','10000000-0000-4000-8000-000000000009');
EOF
) || falla "no se pudieron cargar los datos de prueba"

# 1. Primera ejecucion del semaforo
salida="$(cd "$D" && sqlite3 "$DB" < "$RAIZ/movil/semaforo.sql" | tr -d '\r')"
[ "$(echo "$salida" | tail -n 1)" = "9" ] || falla "el semaforo debio actualizar 9 filas y reportar 9 en changes() (reporto $(echo "$salida" | tail -n 1))"

# 2. Verificacion de cada estado y motivo
res_inexistente="$(q "SELECT estado||'|'||motivo FROM cola_sync WHERE solicitud_uuid='20000000-0000-4000-8000-000000000001'")"
[ "$(echo "$res_inexistente" | cut -d'|' -f1)" = "RECHAZADO" ] || falla "R1 inexistente: se esperaba RECHAZADO, es $(echo "$res_inexistente" | cut -d'|' -f1)"
echo "$res_inexistente" | grep -q "6" || falla "R1: el motivo no nombra el producto 6"

res_eliminado="$(q "SELECT estado||'|'||motivo FROM cola_sync WHERE solicitud_uuid='20000000-0000-4000-8000-000000000002'")"
[ "$(echo "$res_eliminado" | cut -d'|' -f1)" = "RECHAZADO" ] || falla "R2 baja: se esperaba RECHAZADO, es $(echo "$res_eliminado" | cut -d'|' -f1)"
echo "$res_eliminado" | grep -q "5" || falla "R2: el motivo no nombra el producto 5"
echo "$res_eliminado" | grep -i -q "baja" || falla "R2: el motivo no menciona baja"

res_nodisp="$(q "SELECT estado||'|'||motivo FROM cola_sync WHERE solicitud_uuid='20000000-0000-4000-8000-000000000003'")"
[ "$(echo "$res_nodisp" | cut -d'|' -f1)" = "RECHAZADO" ] || falla "R3 no disponible: se esperaba RECHAZADO, es $(echo "$res_nodisp" | cut -d'|' -f1)"
echo "$res_nodisp" | grep -q "2" || falla "R3: el motivo no nombra el producto 2"

res_stock="$(q "SELECT estado||'|'||motivo FROM cola_sync WHERE solicitud_uuid='20000000-0000-4000-8000-000000000004'")"
[ "$(echo "$res_stock" | cut -d'|' -f1)" = "RECHAZADO" ] || falla "R4 stock: se esperaba RECHAZADO, es $(echo "$res_stock" | cut -d'|' -f1)"
echo "$res_stock" | grep -q "4" || falla "R4: el motivo no nombra el producto 4"
echo "$res_stock" | grep -i -q "stock" || falla "R4: el motivo no menciona stock"

res_sube="$(q "SELECT estado||'|'||motivo FROM cola_sync WHERE solicitud_uuid='20000000-0000-4000-8000-000000000005'")"
[ "$(echo "$res_sube" | cut -d'|' -f1)" = "CONFLICTO" ] || falla "R5 precio sube: se esperaba CONFLICTO, es $(echo "$res_sube" | cut -d'|' -f1)"
echo "$res_sube" | grep -q "7" || falla "R5: el motivo no nombra el producto 7"
echo "$res_sube" | grep -q "300000" && echo "$res_sube" | grep -q "350000" || falla "R5: el motivo no nombra ambos precios (300000 y 350000)"

res_baja_precio="$(q "SELECT estado||'|'||motivo FROM cola_sync WHERE solicitud_uuid='20000000-0000-4000-8000-000000000006'")"
[ "$(echo "$res_baja_precio" | cut -d'|' -f1)" = "CONFLICTO" ] || falla "R6 precio baja: se esperaba CONFLICTO, es $(echo "$res_baja_precio" | cut -d'|' -f1)"
echo "$res_baja_precio" | grep -q "8" || falla "R6: el motivo no nombra el producto 8"

res_verde="$(q "SELECT estado||'|'||COALESCE(motivo,'NULL') FROM cola_sync WHERE solicitud_uuid='20000000-0000-4000-8000-000000000007'")"
[ "$(echo "$res_verde" | cut -d'|' -f1)" = "SIMULADO_APROBADO" ] || falla "R7 verde: se esperaba SIMULADO_APROBADO, es $(echo "$res_verde" | cut -d'|' -f1)"
[ "$(echo "$res_verde" | cut -d'|' -f2)" = "NULL" ] || falla "R7 verde: el motivo debia ser NULL, es $(echo "$res_verde" | cut -d'|' -f2)"

res_rojo_gana="$(q "SELECT estado||'|'||motivo FROM cola_sync WHERE solicitud_uuid='20000000-0000-4000-8000-000000000008'")"
[ "$(echo "$res_rojo_gana" | cut -d'|' -f1)" = "RECHAZADO" ] || falla "R8 baja+precio: se esperaba RECHAZADO (rojo gana), es $(echo "$res_rojo_gana" | cut -d'|' -f1)"
echo "$res_rojo_gana" | grep -i -q "baja" || falla "R8: el motivo debia priorizar la baja"

res_vacio="$(q "SELECT estado||'|'||motivo FROM cola_sync WHERE solicitud_uuid='20000000-0000-4000-8000-000000000009'")"
[ "$(echo "$res_vacio" | cut -d'|' -f1)" = "RECHAZADO" ] || falla "R9 vacio: se esperaba RECHAZADO, es $(echo "$res_vacio" | cut -d'|' -f1)"
echo "$res_vacio" | grep -i -q "vacio" || falla "R9: el motivo no menciona borrador vacio"

# 3. Campos de trazabilidad (evaluada_en y snapshot_copiado_en)
n_sin_trazabilidad="$(q "SELECT count(*) FROM cola_sync WHERE evaluada_en IS NULL OR snapshot_copiado_en IS NULL OR snapshot_copiado_en <> '2026-11-01T12:00:00Z'")"
[ "$n_sin_trazabilidad" = "0" ] || falla "$n_sin_trazabilidad solicitudes no tienen evaluada_en o snapshot_copiado_en correcto"

# 4. Idempotencia: segunda corrida reporta changes() = 0 y no cambia nada
salida2="$(cd "$D" && sqlite3 "$DB" < "$RAIZ/movil/semaforo.sql" | tr -d '\r')"
[ "$(echo "$salida2" | tail -n 1)" = "0" ] || falla "la segunda corrida debio reportar changes() = 0 (reporto $(echo "$salida2" | tail -n 1))"

# 5. Estados finales estables: si el precio vuelve al visto, la solicitud CONFLICTO NO cambia
(cd "$D" && sqlite3 "$DB" "UPDATE snapshot_servidor SET precio_centavos = 300000 WHERE id = 7;")
(cd "$D" && sqlite3 "$DB" < "$RAIZ/movil/semaforo.sql" > /dev/null 2>&1)
[ "$(q "SELECT estado FROM cola_sync WHERE solicitud_uuid='20000000-0000-4000-8000-000000000005'")" = "CONFLICTO" ] || falla "una solicitud CONFLICTO cambio de estado tras una instantanea nueva"

# 6. Guarda de instantanea vacia: si snapshot_servidor esta vacia, nada sale de PENDIENTE
(cd "$D" && sqlite3 "$DB" << 'EOF'
DELETE FROM snapshot_servidor;
INSERT INTO pedido_borrador VALUES ('10000000-0000-4000-8000-000000000099','vend1','EFECTIVO','2026-11-01T12:00:00Z');
INSERT INTO item_borrador VALUES ('10000000-0000-4000-8000-000000000099',1,1,275000);
INSERT INTO cola_sync (solicitud_uuid,id_local) VALUES ('20000000-0000-4000-8000-000000000099','10000000-0000-4000-8000-000000000099');
EOF
)
(cd "$D" && sqlite3 "$DB" < "$RAIZ/movil/semaforo.sql" > /dev/null 2>&1)
[ "$(q "SELECT estado FROM cola_sync WHERE solicitud_uuid='20000000-0000-4000-8000-000000000099'")" = "PENDIENTE" ] || falla "con snapshot_servidor vacia una solicitud salio de PENDIENTE"

echo "test_semaforo: OK"
