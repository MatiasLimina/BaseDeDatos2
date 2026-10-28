# TP Unidad 6 — Mantenimiento, respaldo y recuperación de Food Store

Integrantes: Matias Limina - Nicolas Monjelardi - Lautaro Aguero

La consigna está en `TPUnidad_6_Mantenimiento_FoodStore.pdf` y el plan, en [`SPEC_U6.md`](SPEC_U6.md).

## Preparación del entorno (28/10/2026)

- **Servidor:** PostgreSQL 17.11, `localhost:5432`, usuario `postgres`.
- **Contraseña:** sale de `%APPDATA%\postgresql\pgpass.conf`, un archivo personal que no se versiona. Una línea `localhost:5432:*:postgres:<clave>`, guardada sin BOM.
- **Base vieja:** ya existía una `foodstore` con un esquema anterior (`pedido_producto`, una fila por tabla). No se borró: se renombró con `ALTER DATABASE foodstore RENAME TO foodstore_legacy`.
- **Base nueva:** se cargó con el esquema del proyecto integrador, en el orden del paso 1 de [`TP5/README.md`](../TP5/README.md). Lo que se cargó:

| Tabla | Filas |
|---|---|
| categoria | 3 |
| cliente | 20 003 |
| producto | 50 005 |
| pedido | 200 001 |
| pedido_detalle | 621 853 |

  La base pesa 100 MB y los controles de productos y detalles inválidos devuelven 0.
