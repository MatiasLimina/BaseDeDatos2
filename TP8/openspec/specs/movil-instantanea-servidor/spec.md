# movil-instantanea-servidor Specification

## Purpose
Llevar a la tablet una instantánea del catálogo del servidor PostgreSQL (incluidas las bajas como lápidas) en un formato que SQLite acepte sin conversiones, y recargar con ella el caché de productos sin perder historia.

## Requirements

### Requirement: Vista de instantánea derivada sin alterar el servidor
La base de pruebas de PostgreSQL SHALL exponer la vista `v_snapshot_movil` con, por producto: id, nombre, precio en centavos (entero), stock, `disponible` (1 si `activo` y `stock > 0`, si no 0), `eliminado` (1 si no está activo, si no 0) y la fecha de la copia. La vista SHALL derivar esas columnas sin agregar ni modificar tablas o columnas del servidor y SHALL no exponer datos de clientes.

#### Scenario: Banderas como enteros
- **WHEN** se consulta la vista
- **THEN** `disponible` y `eliminado` valen solo 0 o 1 (nunca `t`/`f`) y ninguna columna es nula

#### Scenario: Precio en centavos exacto
- **WHEN** un producto tiene `precio = 1234.56`
- **THEN** la vista devuelve `precio_centavos = 123456`

#### Scenario: Lápidas incluidas
- **WHEN** un producto tiene `activo = false`
- **THEN** aparece en la vista con `eliminado = 1` y `disponible = 0`

#### Scenario: Sin stock no es baja
- **WHEN** un producto activo tiene `stock = 0`
- **THEN** aparece con `disponible = 0` y `eliminado = 0`

#### Scenario: Esquema del servidor intacto
- **WHEN** se compara el catálogo de tablas y columnas de la base antes y después de crear la vista
- **THEN** la única diferencia es la vista nueva

### Requirement: Exportación a CSV con una única fecha de copia
La instantánea SHALL exportarse con `\copy` a `TP8/movil/servidor_snapshot.csv` en formato CSV con encabezado y codificación UTF-8, con una fila por producto de la vista y la misma fecha de copia en todas las filas.

#### Scenario: Una fila por producto
- **WHEN** se exporta la instantánea
- **THEN** el CSV tiene una línea de encabezado más tantas líneas como filas devuelve `SELECT count(*) FROM v_snapshot_movil`

#### Scenario: Fecha de copia única
- **WHEN** se lee la columna de fecha de copia del CSV
- **THEN** todas las filas tienen el mismo valor

### Requirement: Importación tipada en snapshot_servidor
La importación SHALL reemplazar por completo el contenido de `snapshot_servidor` (tabla STRICT con tipos enteros para precio, stock y banderas) con las filas del CSV. Si alguna fila no puede guardarse con su tipo, la importación SHALL considerarse fallida y no se SHALL cargar el caché.

#### Scenario: Importación completa
- **WHEN** se importa el CSV con `.import --csv --skip 1`
- **THEN** `snapshot_servidor` tiene la misma cantidad de filas que el CSV sin el encabezado y sus columnas numéricas son de tipo `integer`

#### Scenario: Instantánea anterior reemplazada
- **WHEN** se importa una instantánea nueva después de otra
- **THEN** `snapshot_servidor` contiene solo las filas de la nueva

#### Scenario: CSV con booleanos t/f
- **WHEN** se intenta importar un CSV cuyas banderas vienen como `t`/`f`
- **THEN** las filas son rechazadas por el tipo STRICT, el conteo no coincide y el caché no se recarga

#### Scenario: Sin retorno de carro residual
- **WHEN** se importa un CSV generado en Windows
- **THEN** ningún valor de la última columna termina en un carácter de retorno de carro

### Requirement: Recarga del caché sin borrar filas
Cargar `producto_cache` desde `snapshot_servidor` SHALL insertar los productos nuevos y actualizar los existentes (nombre, precio, stock, banderas y fecha de copia) sin borrar ninguna fila. Un producto del caché que ya no viene en la instantánea SHALL quedar con `eliminado = 1` y `disponible = 0`.

#### Scenario: Carga inicial
- **WHEN** se carga el caché vacío desde una instantánea de N productos
- **THEN** `producto_cache` tiene N filas con los mismos valores que `snapshot_servidor`

#### Scenario: Baja conservada como lápida (C4)
- **WHEN** se recarga el caché con una instantánea en la que un producto tiene `eliminado = 1`
- **THEN** la fila del producto sigue en `producto_cache` con `eliminado = 1`, sigue referenciada por los ítems que la usaban y no aparece en el catálogo disponible

#### Scenario: Producto ausente de la instantánea
- **WHEN** un producto del caché no está en la instantánea nueva
- **THEN** su fila queda con `eliminado = 1` y `disponible = 0` y no se borra

#### Scenario: Fecha de la copia registrada
- **WHEN** termina la recarga
- **THEN** todas las filas actualizadas tienen la fecha de copia de la instantánea cargada
