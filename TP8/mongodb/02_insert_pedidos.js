// Generado por migracion/generar_insert_pedidos.sql desde foodstore (PostgreSQL). No editar a mano.
// Uso: mongosh mongodb://localhost:27017/foodstore --file mongodb/02_insert_pedidos.js
db = db.getSiblingDB("foodstore");
const resultado = db.pedidos.insertMany([
  { _id: 1, fecha: ISODate("2026-10-28T21:03:06.994Z"), estado: "PENDIENTE", forma_pago: "EFECTIVO",
    cliente: { id: 1, nombre: "Juan", apellido: "Pérez", email: "juan.perez@email.com" },
    lineas: [
      { producto: { id: 1, nombre: "Coca Cola 1.5L", categoria: "Bebidas" }, cantidad: 2, precio_unitario: NumberDecimal("2500.00"), subtotal: NumberDecimal("5000.00") },
      { producto: { id: 9443, nombre: "Producto 9438", categoria: "Bebidas" }, cantidad: 3, precio_unitario: NumberDecimal("2218.29"), subtotal: NumberDecimal("6654.87") },
      { producto: { id: 13896, nombre: "Producto 13891", categoria: "Bebidas" }, cantidad: 1, precio_unitario: NumberDecimal("509.44"), subtotal: NumberDecimal("509.44") },
      { producto: { id: 25905, nombre: "Producto 25900", categoria: "Bebidas" }, cantidad: 3, precio_unitario: NumberDecimal("3287.97"), subtotal: NumberDecimal("9863.91") },
      { producto: { id: 33458, nombre: "Producto 33453", categoria: "Bebidas" }, cantidad: 3, precio_unitario: NumberDecimal("918.17"), subtotal: NumberDecimal("2754.51") }
    ],
    total: NumberDecimal("24782.73") },
  { _id: 2, fecha: ISODate("2026-04-10T03:00:00.000Z"), estado: "ENTREGADO", forma_pago: "TRANSFERENCIA",
    cliente: { id: 4812, nombre: "Usuario4809", apellido: "Apellido4809", email: "usuario4809@test.com" },
    lineas: [
      { producto: { id: 9443, nombre: "Producto 9438", categoria: "Bebidas" }, cantidad: 3, precio_unitario: NumberDecimal("2218.29"), subtotal: NumberDecimal("6654.87") },
      { producto: { id: 13896, nombre: "Producto 13891", categoria: "Bebidas" }, cantidad: 2, precio_unitario: NumberDecimal("509.44"), subtotal: NumberDecimal("1018.88") },
      { producto: { id: 25905, nombre: "Producto 25900", categoria: "Bebidas" }, cantidad: 2, precio_unitario: NumberDecimal("3287.97"), subtotal: NumberDecimal("6575.94") }
    ],
    total: NumberDecimal("14249.69") },
  { _id: 7, fecha: ISODate("2026-03-03T03:00:00.000Z"), estado: "ENTREGADO", forma_pago: "TARJETA",
    cliente: { id: 4812, nombre: "Usuario4809", apellido: "Apellido4809", email: "usuario4809@test.com" },
    lineas: [
      { producto: { id: 9443, nombre: "Producto 9438", categoria: "Bebidas" }, cantidad: 3, precio_unitario: NumberDecimal("2218.29"), subtotal: NumberDecimal("6654.87") },
      { producto: { id: 25905, nombre: "Producto 25900", categoria: "Bebidas" }, cantidad: 2, precio_unitario: NumberDecimal("3287.97"), subtotal: NumberDecimal("6575.94") },
      { producto: { id: 33458, nombre: "Producto 33453", categoria: "Bebidas" }, cantidad: 1, precio_unitario: NumberDecimal("918.17"), subtotal: NumberDecimal("918.17") }
    ],
    total: NumberDecimal("14148.98") },
  { _id: 20, fecha: ISODate("2025-12-20T03:00:00.000Z"), estado: "CANCELADO", forma_pago: "EFECTIVO",
    cliente: { id: 4812, nombre: "Usuario4809", apellido: "Apellido4809", email: "usuario4809@test.com" },
    lineas: [
      { producto: { id: 9443, nombre: "Producto 9438", categoria: "Bebidas" }, cantidad: 3, precio_unitario: NumberDecimal("2218.29"), subtotal: NumberDecimal("6654.87") },
      { producto: { id: 13896, nombre: "Producto 13891", categoria: "Bebidas" }, cantidad: 2, precio_unitario: NumberDecimal("509.44"), subtotal: NumberDecimal("1018.88") },
      { producto: { id: 25905, nombre: "Producto 25900", categoria: "Bebidas" }, cantidad: 3, precio_unitario: NumberDecimal("3287.97"), subtotal: NumberDecimal("9863.91") },
      { producto: { id: 33458, nombre: "Producto 33453", categoria: "Bebidas" }, cantidad: 4, precio_unitario: NumberDecimal("918.17"), subtotal: NumberDecimal("3672.68") }
    ],
    total: NumberDecimal("21210.34") },
  { _id: 26, fecha: ISODate("2026-10-27T03:00:00.000Z"), estado: "ENVIADO", forma_pago: "TRANSFERENCIA",
    cliente: { id: 4812, nombre: "Usuario4809", apellido: "Apellido4809", email: "usuario4809@test.com" },
    lineas: [
      { producto: { id: 9443, nombre: "Producto 9438", categoria: "Bebidas" }, cantidad: 4, precio_unitario: NumberDecimal("2218.29"), subtotal: NumberDecimal("8873.16") },
      { producto: { id: 13896, nombre: "Producto 13891", categoria: "Bebidas" }, cantidad: 4, precio_unitario: NumberDecimal("509.44"), subtotal: NumberDecimal("2037.76") },
      { producto: { id: 25905, nombre: "Producto 25900", categoria: "Bebidas" }, cantidad: 3, precio_unitario: NumberDecimal("3287.97"), subtotal: NumberDecimal("9863.91") },
      { producto: { id: 33458, nombre: "Producto 33453", categoria: "Bebidas" }, cantidad: 2, precio_unitario: NumberDecimal("918.17"), subtotal: NumberDecimal("1836.34") }
    ],
    total: NumberDecimal("22611.17") },
  { _id: 120, fecha: ISODate("2025-12-04T03:00:00.000Z"), estado: "CANCELADO", forma_pago: "TARJETA",
    cliente: { id: 4812, nombre: "Usuario4809", apellido: "Apellido4809", email: "usuario4809@test.com" },
    lineas: [
      { producto: { id: 9443, nombre: "Producto 9438", categoria: "Bebidas" }, cantidad: 2, precio_unitario: NumberDecimal("2218.29"), subtotal: NumberDecimal("4436.58") },
      { producto: { id: 25905, nombre: "Producto 25900", categoria: "Bebidas" }, cantidad: 3, precio_unitario: NumberDecimal("3287.97"), subtotal: NumberDecimal("9863.91") },
      { producto: { id: 33458, nombre: "Producto 33453", categoria: "Bebidas" }, cantidad: 2, precio_unitario: NumberDecimal("918.17"), subtotal: NumberDecimal("1836.34") }
    ],
    total: NumberDecimal("16136.83") },
  { _id: 217, fecha: ISODate("2026-10-27T03:00:00.000Z"), estado: "ENVIADO", forma_pago: "TRANSFERENCIA",
    cliente: { id: 4812, nombre: "Usuario4809", apellido: "Apellido4809", email: "usuario4809@test.com" },
    lineas: [
      { producto: { id: 9443, nombre: "Producto 9438", categoria: "Bebidas" }, cantidad: 3, precio_unitario: NumberDecimal("2218.29"), subtotal: NumberDecimal("6654.87") },
      { producto: { id: 33458, nombre: "Producto 33453", categoria: "Bebidas" }, cantidad: 2, precio_unitario: NumberDecimal("918.17"), subtotal: NumberDecimal("1836.34") }
    ],
    total: NumberDecimal("8491.21") },
  { _id: 240, fecha: ISODate("2026-10-28T03:00:00.000Z"), estado: "EN_PREPARACION", forma_pago: "TARJETA",
    cliente: { id: 4812, nombre: "Usuario4809", apellido: "Apellido4809", email: "usuario4809@test.com" },
    lineas: [
      { producto: { id: 9443, nombre: "Producto 9438", categoria: "Bebidas" }, cantidad: 3, precio_unitario: NumberDecimal("2218.29"), subtotal: NumberDecimal("6654.87") },
      { producto: { id: 13896, nombre: "Producto 13891", categoria: "Bebidas" }, cantidad: 1, precio_unitario: NumberDecimal("509.44"), subtotal: NumberDecimal("509.44") },
      { producto: { id: 25905, nombre: "Producto 25900", categoria: "Bebidas" }, cantidad: 3, precio_unitario: NumberDecimal("3287.97"), subtotal: NumberDecimal("9863.91") },
      { producto: { id: 33458, nombre: "Producto 33453", categoria: "Bebidas" }, cantidad: 3, precio_unitario: NumberDecimal("918.17"), subtotal: NumberDecimal("2754.51") }
    ],
    total: NumberDecimal("19782.73") },
  { _id: 10167, fecha: ISODate("2026-10-28T03:00:00.000Z"), estado: "EN_PREPARACION", forma_pago: "EFECTIVO",
    cliente: { id: 4812, nombre: "Usuario4809", apellido: "Apellido4809", email: "usuario4809@test.com" },
    lineas: [
      { producto: { id: 9443, nombre: "Producto 9438", categoria: "Bebidas" }, cantidad: 1, precio_unitario: NumberDecimal("2218.29"), subtotal: NumberDecimal("2218.29") },
      { producto: { id: 25905, nombre: "Producto 25900", categoria: "Bebidas" }, cantidad: 3, precio_unitario: NumberDecimal("3287.97"), subtotal: NumberDecimal("9863.91") },
      { producto: { id: 33458, nombre: "Producto 33453", categoria: "Bebidas" }, cantidad: 2, precio_unitario: NumberDecimal("918.17"), subtotal: NumberDecimal("1836.34") }
    ],
    total: NumberDecimal("13918.54") }
]);
print("pedidos insertados: " + Object.keys(resultado.insertedIds).length);
