// =====================================================================
// 01_crear_coleccion.js — Base foodstore y colección pedidos (TP Unidad 7, Consigna 2)
// Uso: mongosh mongodb://localhost:27017/foodstore --file mongodb/01_crear_coleccion.js
//
// Borra y recrea la colección: es un laboratorio y la fuente de verdad es
// PostgreSQL. Los datos se cargan después con 02_insert_pedidos.js.
//
// El validador traslada a MongoDB las reglas de integridad de foodstore que
// afectan a los pedidos (Consigna 3, ver docs/modelo_documental.md):
// Cláusulas del $and (el índice aparece en errInfo.details.clausesNotSatisfied):
//   0 $jsonSchema: estructura, tipos (importes en Decimal128, nunca double),
//     estados y formas de pago válidos (los enums de PostgreSQL), cantidad > 0,
//     importes entre 0 y 99 999 999,99 (los CHECK de pedido_detalle y el rango
//     de NUMERIC(10,2)) y al menos una línea por pedido;
//   1 total = suma de subtotales;
//   2 subtotal = cantidad * precio_unitario;
//   3 producto sin repetir dentro del pedido (la PK pedido_id, producto_id);
//   4 precio unitario con 2 decimales como máximo (de ahí, también subtotal y total).
// validationLevel strict + validationAction error: un documento inválido no se
// guarda (error 121, DocumentValidationFailure).
// =====================================================================

db = db.getSiblingDB("foodstore");
db.pedidos.drop();

// Rango de NUMERIC(10,2): de 0 a 99 999 999,99. El máximo también excluye Infinity,
// que Decimal128 admite y PostgreSQL no. La escala de 2 decimales se controla en el
// último $expr del validador.
const decimalNoNegativo = {
  bsonType: "decimal", minimum: NumberDecimal("0"), maximum: NumberDecimal("99999999.99"),
};

db.createCollection("pedidos", {
  validationLevel: "strict",
  validationAction: "error",
  validator: {
    $and: [
      {
        $jsonSchema: {
          bsonType: "object",
          required: ["_id", "fecha", "estado", "forma_pago", "cliente", "lineas", "total"],
          additionalProperties: false,
          properties: {
            _id: { bsonType: ["int", "long"], description: "pedido.id de PostgreSQL" },
            fecha: { bsonType: "date" },
            estado: { enum: ["PENDIENTE", "EN_PREPARACION", "ENVIADO", "ENTREGADO", "CANCELADO"] },
            forma_pago: { enum: ["EFECTIVO", "TARJETA", "TRANSFERENCIA", "OTRO"] },
            cliente: {
              bsonType: "object",
              required: ["id", "nombre", "apellido", "email"],
              additionalProperties: false,
              properties: {
                id: { bsonType: ["int", "long"] },
                nombre: { bsonType: "string" },
                apellido: { bsonType: "string" },
                email: { bsonType: "string" },
              },
            },
            lineas: {
              bsonType: "array",
              minItems: 1,
              items: {
                bsonType: "object",
                required: ["producto", "cantidad", "precio_unitario", "subtotal"],
                additionalProperties: false,
                properties: {
                  producto: {
                    bsonType: "object",
                    required: ["id", "nombre", "categoria"],
                    additionalProperties: false,
                    properties: {
                      id: { bsonType: ["int", "long"] },
                      nombre: { bsonType: "string" },
                      categoria: { bsonType: "string" },
                    },
                  },
                  cantidad: { bsonType: ["int", "long"], minimum: 1 },
                  precio_unitario: decimalNoNegativo,
                  subtotal: decimalNoNegativo,
                },
              },
            },
            total: decimalNoNegativo,
          },
        },
      },
      // total = suma de los subtotales.
      { $expr: { $eq: ["$total", { $sum: "$lineas.subtotal" }] } },
      // subtotal = cantidad * precio_unitario en cada línea.
      {
        $expr: {
          $allElementsTrue: [{
            $map: {
              input: "$lineas",
              in: { $eq: ["$$this.subtotal", { $multiply: ["$$this.cantidad", "$$this.precio_unitario"] }] },
            },
          }],
        },
      },
      // Un producto aparece una sola vez por pedido (PK pedido_id, producto_id).
      {
        $expr: {
          $eq: [{ $size: "$lineas.producto.id" }, { $size: { $setUnion: ["$lineas.producto.id", []] } }],
        },
      },
      // Precio unitario con 2 decimales como máximo (escala de NUMERIC(10,2)). Alcanza
      // con el precio: como cantidad es entera, las cláusulas 2 y 1 hacen que subtotal
      // y total también tengan 2 decimales.
      {
        $expr: {
          $allElementsTrue: [{
            $map: {
              input: "$lineas",
              in: { $eq: ["$$this.precio_unitario", { $round: ["$$this.precio_unitario", 2] }] },
            },
          }],
        },
      },
    ],
  },
});

// Índices para las consultas de la Parte 2. Con 9 documentos no cambian el plan,
// pero son los que el modelo necesita con volumen real.
db.pedidos.createIndex({ estado: 1 }, { name: "idx_estado" });                            // consulta b
db.pedidos.createIndex({ "lineas.producto.id": 1 }, { name: "idx_lineas_producto" });     // consulta c (multikey)
db.pedidos.createIndex({ total: 1 }, { name: "idx_total" });                              // consulta d

print("colección foodstore.pedidos creada con validador e índices");
