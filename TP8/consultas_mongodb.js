// =====================================================================
// consultas_mongodb.js — Parte 2, Consigna 4: consultas sobre foodstore.pedidos
// Uso: mongosh mongodb://localhost:27017/foodstore --file consultas_mongodb.js
//
// Después de cada consulta se imprime "RESULTADO <x>: <ids>", con los _id que
// devuelve ESA MISMA consulta. tests/test_consultas.sh compara esas líneas con
// las de consultas_postgresql.sql.
// =====================================================================

db = db.getSiblingDB("foodstore");

const ESTADO = "ENTREGADO";                  // b) estado presente en los datos migrados
const PRODUCTO_ID = 13896;                   // c) "Producto 13891" (producto.id conservado)
const UMBRAL = NumberDecimal("20000.00");    // d) ver justificación abajo

// Cada filtro se define una sola vez y lo usan tanto la consulta que se muestra como
// resultado(): si se cambia, cambian las dos.
const FILTRO = {
  a: {},
  b: { estado: ESTADO },
  c: { "lineas.producto.id": PRODUCTO_ID },
  d: { total: { $gt: UMBRAL } },
};

function resultado(letra) {
  const ids = db.pedidos.find(FILTRO[letra], { _id: 1 }).sort({ _id: 1 }).toArray().map(d => d._id);
  print("RESULTADO " + letra + ": " + ids.join(","));
  print(ids.length + " pedidos\n");
}
function mostrar(cursor) {
  cursor.forEach(d => print(JSON.stringify(EJSON.serialize(d, { relaxed: true }))));
}

// ---------------------------------------------------------------------
// a) Todos los pedidos, con su identificador y estado.
// ---------------------------------------------------------------------
print("== a) Todos los pedidos (id y estado)");
mostrar(db.pedidos.find(FILTRO.a, { _id: 1, estado: 1 }).sort({ _id: 1 }));
resultado("a");

// ---------------------------------------------------------------------
// b) Pedidos en un estado determinado. Usa el índice idx_estado.
// ---------------------------------------------------------------------
print("== b) Pedidos con estado " + ESTADO);
mostrar(db.pedidos.find(FILTRO.b, { estado: 1, fecha: 1, total: 1 }).sort({ _id: 1 }));
resultado("b");

// ---------------------------------------------------------------------
// c) Pedidos que contienen un producto dentro del arreglo de líneas.
//    "lineas.producto.id" recorre todos los elementos del arreglo; la proyección
//    posicional "lineas.$" muestra solo la línea que coincidió. Usa el índice
//    multikey idx_lineas_producto (se verifica con explain).
// ---------------------------------------------------------------------
print("== c) Pedidos que contienen el producto " + PRODUCTO_ID);
mostrar(db.pedidos.find(FILTRO.c, { estado: 1, "lineas.$": 1 }).sort({ _id: 1 }));
const plan = db.pedidos.find(FILTRO.c).explain("executionStats");
const etapas = [];
for (let s = plan.queryPlanner.winningPlan.queryPlan || plan.queryPlanner.winningPlan; s; s = s.inputStage) {
  etapas.push(s.stage + (s.indexName ? "(" + s.indexName + ", multikey=" + s.isMultiKey + ")" : ""));
}
print("plan: " + etapas.join(" <- ") + " | documentos examinados: " + plan.executionStats.totalDocsExamined);
resultado("c");

// ---------------------------------------------------------------------
// d) Pedidos con total mayor que un umbral.
//    Umbral 20 000: está apenas por encima del tercer cuartil de los totales de los
//    200 001 pedidos de foodstore (p75 = 19 731,93; mediana = 15 653,28), así que
//    marca los pedidos grandes (cerca del 24 % del total). Es una cifra redonda,
//    fácil de comunicar. La comparación es en Decimal128 y estricta (>): un pedido
//    de 19 782,73 queda afuera.
// ---------------------------------------------------------------------
print("== d) Pedidos con total > " + UMBRAL);
mostrar(db.pedidos.find(FILTRO.d, { estado: 1, total: 1 }).sort({ total: -1 }));
resultado("d");
