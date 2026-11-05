#!/usr/bin/env bash
# Prueba de la migración de pedidos de PostgreSQL (foodstore) a MongoDB (foodstore.pedidos).
#
# Comprueba que:
#   1. la colección tiene exactamente los pedidos de sql/01_seleccion_pedidos.sql;
#   2. cada pedido y cada línea tienen los mismos valores que en PostgreSQL:
#      estado, fecha, forma de pago, cliente, producto, cantidad, precio
#      unitario histórico y subtotal. El total es la suma de los subtotales;
#   3. los importes se guardan como Decimal128 y no como double;
#   4. el validador de la colección rechaza documentos que rompen las reglas de
#      integridad, y ninguno de esos documentos queda guardado.
#
# Uso, desde la raíz del repo:  bash tests/test_migracion.sh   (imprime "test_migracion: OK")
# Requiere pgpass.conf para PostgreSQL y MongoDB en localhost:27017.
set -euo pipefail

export PGHOST="${PGHOST:-localhost}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}"
export PGCLIENTENCODING=UTF8
MONGOSH="${MONGOSH:-$(command -v mongosh || echo /c/Users/Nico/AppData/Local/Programs/mongosh/mongosh.exe)}"
URI="${MONGO_URI:-mongodb://localhost:27017/foodstore}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

falla() { echo "test_migracion: FALLA - $1" >&2; exit 1; }
mongo() { "$MONGOSH" "$URI" --quiet --eval "$1" | tr -d '\r'; }

# 1. Mismos pedidos.
# psql en Windows termina las líneas con \r\n: se quita el \r antes de comparar.
ids_pg=$(psql -X -w -d foodstore -At -f "$DIR/sql/01_seleccion_pedidos.sql" | tr -d '\r' | paste -sd' ')
ids_mongo=$(mongo 'db.pedidos.find({}, {_id: 1}).sort({_id: 1}).toArray().map(d => d._id).join(" ")')
[ -n "$ids_mongo" ] || falla "la colección pedidos está vacía o no existe"
[ "$ids_pg" = "$ids_mongo" ] || falla "ids distintos: PostgreSQL [$ids_pg] vs MongoDB [$ids_mongo]"
ids_csv=$(echo "$ids_mongo" | tr ' ' ',')

# 2. Mismos valores, línea por línea, en un formato canónico:
#    pedido|estado|fecha UTC|forma_pago|cliente: id, nombre, apellido, email|
#    producto: id, nombre, categoría|cantidad|precio|subtotal|total
psql -X -w -d foodstore -At -F'|' -c "
    SELECT p.id, p.estado, to_char(p.fecha AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"'),
           p.forma_pago, c.id, c.nombre, c.apellido, c.email, d.producto_id, pr.nombre, ca.nombre,
           d.cantidad, d.precio_unitario, d.subtotal, sum(d.subtotal) OVER (PARTITION BY p.id)
    FROM pedido p
    JOIN cliente c ON c.id = p.cliente_id
    JOIN pedido_detalle d ON d.pedido_id = p.id
    JOIN producto pr ON pr.id = d.producto_id
    JOIN categoria ca ON ca.id = pr.categoria_id
    WHERE p.id IN ($ids_csv)
    ORDER BY p.id, d.producto_id" | tr -d '\r' > "$TMP/pg.txt"
mongo 'db.pedidos.aggregate([{$unwind: "$lineas"}, {$sort: {_id: 1, "lineas.producto.id": 1}}]).toArray()
       .map(d => [d._id, d.estado, d.fecha.toISOString(), d.forma_pago,
                  d.cliente.id, d.cliente.nombre, d.cliente.apellido, d.cliente.email,
                  d.lineas.producto.id, d.lineas.producto.nombre, d.lineas.producto.categoria,
                  d.lineas.cantidad, d.lineas.precio_unitario.toString(), d.lineas.subtotal.toString(),
                  d.total.toString()]
                 .join("|")).join("\n")' > "$TMP/mongo.txt"
diff "$TMP/pg.txt" "$TMP/mongo.txt" > "$TMP/diff.txt" \
    || { cat "$TMP/diff.txt" >&2; falla "los valores migrados no coinciden con PostgreSQL"; }

# 3. Importes en Decimal128. $elemMatch revisa cada línea: con "lineas.precio_unitario"
#    a secas, $not solo encontraría documentos sin NINGUNA línea decimal.
no_decimal=$(mongo 'db.pedidos.countDocuments({$or: [{total: {$not: {$type: "decimal"}}},
                     {lineas: {$elemMatch: {precio_unitario: {$not: {$type: "decimal"}}}}},
                     {lineas: {$elemMatch: {subtotal: {$not: {$type: "decimal"}}}}}]})')
[ "$no_decimal" = "0" ] || falla "$no_decimal documentos guardan importes que no son Decimal128"

# 4. El validador rechaza cada documento inválido POR LA REGLA QUE CORRESPONDE.
#    Cada caso parte de un pedido válido (el primero, con _id -1) y altera lo mínimo
#    para romper una sola regla: recalcula subtotal y total cuando hace falta, para no
#    romper también las reglas aritméticas. Se comparan las cláusulas del validador
#    que fallaron (errInfo.details; índices en mongodb/01_crear_coleccion.js) y, en la
#    cláusula 0 ($jsonSchema), el campo y el operador que la rompieron.
rechazos=$(mongo '
const base = db.pedidos.findOne({}, {}, {sort: {_id: 1}});
base._id = -1;
const dec = (n, decimales = 2) => NumberDecimal(n.toFixed(decimales));
const num = x => Number(x.toString());
const recalcularTotal = (d, decimales = 2) =>
  { d.total = dec(d.lineas.reduce((s, l) => s + num(l.subtotal), 0), decimales); };
// nombre: [alteración, cláusulas que deben fallar, campo y operador esperados en la cláusula 0]
const casos = {
  cantidad_cero:      [d => { const l = d.lineas[0]; l.cantidad = 0; l.subtotal = dec(0); recalcularTotal(d); },
                       [0], ["cantidad", "minimum"]],
  precio_negativo:    [d => { const l = d.lineas[0]; l.precio_unitario = dec(-1); l.subtotal = dec(-l.cantidad);
                              recalcularTotal(d); },
                       [0], ["precio_unitario", "minimum"]],
  precio_infinito:    [d => { const l = d.lineas[0]; l.precio_unitario = NumberDecimal("Infinity");
                              l.subtotal = NumberDecimal("Infinity"); d.total = NumberDecimal("Infinity"); },
                       [0], ["precio_unitario", "maximum"]],
  // Un double rompe también la cláusula 1: 24782.73 en binario no es igual a la suma exacta
  // en Decimal128. Es la razón para guardar los importes en Decimal128.
  importe_double:     [d => { d.total = num(d.total); }, [0, 1], ["total", "bsonType"]],
  estado_inexistente: [d => { d.estado = "PERDIDO"; }, [0], ["estado", "enum"]],
  sin_lineas:         [d => { d.lineas = []; d.total = dec(0); }, [0], ["lineas", "minItems"]],
  total_erroneo:      [d => { d.total = dec(1); }, [1]],
  subtotal_erroneo:   [d => { d.lineas[0].subtotal = dec(1); recalcularTotal(d); }, [2]],
  producto_repetido:  [d => { d.lineas.push(d.lineas[0]); recalcularTotal(d); }, [3]],
  tres_decimales:     [d => { const l = d.lineas[0]; l.precio_unitario = dec(num(l.precio_unitario) + 0.001, 3);
                              l.subtotal = dec(l.cantidad * num(l.precio_unitario), 3); recalcularTotal(d, 3); },
                       [4]],
};
const errores = [];
for (const [nombre, [alterar, clausulas, esperado]] of Object.entries(casos)) {
  const d = EJSON.parse(EJSON.stringify(base, {relaxed: false}), {relaxed: false});  // copia profunda
  alterar(d);
  try { db.pedidos.insertOne(d); errores.push(nombre + ": aceptado"); db.pedidos.deleteOne({_id: -1}); continue; }
  catch (e) {
    if (e.code !== 121) { errores.push(nombre + ": error " + e.code); continue; }
    const fallaron = e.errInfo.details.clausesNotSatisfied;
    const indices = fallaron.map(c => c.index);
    if (JSON.stringify(indices) !== JSON.stringify(clausulas)) {
      errores.push(nombre + ": fallaron las cláusulas " + indices + " y se esperaban " + clausulas); continue;
    }
    if (esperado) {
      const detalle = JSON.stringify(fallaron[0].details);
      const [campo, operador] = esperado;
      if (!detalle.includes("\"propertyName\":\"" + campo + "\"") || !detalle.includes("\"operatorName\":\"" + operador + "\""))
        errores.push(nombre + ": no lo rechazó " + operador + " sobre " + campo);
    }
  }
}
print(errores.length === 0 ? "todos rechazados por su regla" : errores.join("; "));
')
[ "$rechazos" = "todos rechazados por su regla" ] || falla "validador: $rechazos"
[ "$(mongo 'db.pedidos.countDocuments({_id: -1})')" = "0" ] || falla "quedó un documento de prueba"

echo "test_migracion: OK"
