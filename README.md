# BaseDeDatos2-TP7-NoSQL

TP Unidad 7 — NoSQL y nuevas formas de almacenamiento: Food Store en MongoDB frente a PostgreSQL. Bases de Datos II.

Integrantes: Matias Limina - Nicolas Monjelardi - Lautaro Aguero

La base relacional es la `foodstore` del proyecto integrador. Ver el repositorio [MatiasLimina/BaseDeDatos2](https://github.com/MatiasLimina/BaseDeDatos2) y su `TP6/README.md` para cargarla. Todo el TP se hizo con Claude Code.

## Contenido

| Parte | Qué | Archivos |
|---|---|---|
| Previo | Estado del pedido agregado a `foodstore` (la consigna lo pide y el modelo no lo tenía) | [`sql/00_estado_pedido.sql`](sql/00_estado_pedido.sql), [`sql/test_estado_pedido.sql`](sql/test_estado_pedido.sql) |
| 1 | Modelo documental, migración y reglas de integridad | [`docs/modelo_documental.md`](docs/modelo_documental.md), [`sql/01_seleccion_pedidos.sql`](sql/01_seleccion_pedidos.sql), [`migracion/generar_insert_pedidos.sql`](migracion/generar_insert_pedidos.sql), [`mongodb/01_crear_coleccion.js`](mongodb/01_crear_coleccion.js), [`mongodb/02_insert_pedidos.js`](mongodb/02_insert_pedidos.js), [`tests/test_migracion.sh`](tests/test_migracion.sh) |

Evidencias en [`evidencias/`](evidencias/).

## Orden de ejecución

Requiere:
- PostgreSQL 16 o superior con `foodstore` cargada, y `pgpass.conf` para el usuario `postgres`;
- MongoDB en `localhost:27017` y `mongosh`;
- Git Bash para el test.

Se ejecuta desde la raíz del repo:

```bash
# Previo: estado del pedido (idempotente)
psql -X -w -h localhost -U postgres -d foodstore -v ON_ERROR_STOP=1 -f sql/00_estado_pedido.sql
psql -X -w -h localhost -U postgres -d foodstore -v ON_ERROR_STOP=1 -f sql/test_estado_pedido.sql   # -> test_estado_pedido: OK

# Parte 1: generar el insertMany desde PostgreSQL, crear la colección y migrar
psql -X -w -h localhost -U postgres -d foodstore -At -v ON_ERROR_STOP=1 -f migracion/generar_insert_pedidos.sql -o mongodb/02_insert_pedidos.js
mongosh mongodb://localhost:27017/foodstore --file mongodb/01_crear_coleccion.js
mongosh mongodb://localhost:27017/foodstore --file mongodb/02_insert_pedidos.js       # -> pedidos insertados: 9
bash tests/test_migracion.sh                                                          # -> test_migracion: OK
```
