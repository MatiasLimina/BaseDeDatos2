# Requirements Document

## Introduction

Esta especificación cubre la creación de las **vistas de reportes del sistema Food Store** (TP3, punto 4.2). Las vistas encapsulan las consultas de lectura más frecuentes, simplifican el acceso para los consumidores de la base de datos (aplicaciones, analistas, roles con permisos restringidos) y permiten aplicar criterios de seguridad ocultando columnas sensibles sin modificar las tablas base.

El esquema subyacente es PostgreSQL y está compuesto por cinco tablas: `categoria`, `producto`, `cliente`, `pedido` y `pedido_detalle`. La baja lógica se implementa con el campo `activo BOOLEAN NOT NULL DEFAULT TRUE` en las tablas `categoria`, `producto` y `cliente`.

Los tres requisitos que siguen cubren:
- **Requisito 1** — Vista de productos vigentes con su categoría.
- **Requisito 2** — Vista de pedidos con datos del cliente, aplicando el patrón de seguridad de ocultación de columna sensible.
- **Requisito 3** — Vista del detalle de un pedido con el nombre del producto.

---

## Glossary

- **Sistema_Vistas**: El módulo de base de datos responsable de definir y mantener las vistas de reporte en PostgreSQL.
- **Vista**: Consulta nombrada y almacenada en el catálogo de PostgreSQL que se comporta como una tabla de solo lectura para los consumidores.
- **Producto_Vigente**: Producto cuyo campo `activo = TRUE` en la tabla `producto` y cuya `categoria.activo = TRUE`.
- **Columna_Sensible**: Columna que contiene información personal o de autenticación que no debe exponerse en una vista de acceso general. En la tabla `cliente` del esquema actual no existe columna contraseña; el patrón se demuestra ocultando `email` y `telefono`, que son datos de contacto personales. Si en el futuro se agregara una columna `contrasena VARCHAR` o similar, también quedaría excluida de la vista.
- **Equivalencia_de_Vista**: Propiedad que garantiza que la vista y la consulta SQL equivalente escrita manualmente producen exactamente el mismo conjunto de filas y columnas para el mismo estado de la base de datos.
- **Verificacion_de_Equivalencia**: Proceso de ejecutar la vista y la consulta manual de forma paralela y comparar los resultados mediante `EXCEPT` bidireccional.
- **Role_Reporte**: Rol o usuario de PostgreSQL con permiso `SELECT` sobre las vistas pero sin `SELECT` directo sobre las tablas base.

---

## Requirements

---

### Requisito 1 — Vista de productos vigentes con su categoría

**User Story:** Como analista de negocio, quiero consultar el catálogo de productos activos junto con el nombre de su categoría, para obtener un listado operativo sin necesidad de conocer las claves foráneas ni el esquema interno.

#### Criterios de Aceptación

1. THE `Sistema_Vistas` SHALL definir una vista denominada `vw_productos_vigentes` sobre las tablas `producto` y `categoria`.

2. WHEN un consumidor consulta `vw_productos_vigentes`, THE `Sistema_Vistas` SHALL retornar exactamente las columnas `producto.id`, `producto.nombre`, `producto.precio`, `producto.stock`, `categoria.nombre AS nombre_categoria` y `producto.created_at`.

3. WHILE `producto.activo = TRUE` AND `categoria.activo = TRUE`, THE `Sistema_Vistas` SHALL incluir el producto en el resultado de `vw_productos_vigentes`.

4. IF `producto.activo = FALSE` OR `categoria.activo = FALSE`, THEN THE `Sistema_Vistas` SHALL excluir ese producto del resultado de `vw_productos_vigentes`.

5. THE `Sistema_Vistas` SHALL implementar el filtro de vigencia mediante la cláusula `WHERE producto.activo = TRUE AND categoria.activo = TRUE` dentro de la definición de la vista, de modo que el filtro sea invariante para cualquier consulta sobre ella.

6. WHEN se ejecuta la consulta de equivalencia manual contra `vw_productos_vigentes`, THE `Sistema_Vistas` SHALL producir un resultado donde la operación `(SELECT … FROM vw_productos_vigentes) EXCEPT (SELECT … FROM producto JOIN categoria …)` retorna cero filas en ambas direcciones.

---

### Requisito 2 — Vista de pedidos con datos del cliente (criterio de seguridad)

**User Story:** Como desarrollador de la capa de aplicación, quiero consultar los pedidos junto con los datos identificativos del cliente sin acceder directamente a la tabla `cliente`, para que pueda otorgarse `SELECT` sobre la vista a roles con permisos restringidos sin exponer columnas de contacto personales.

#### Criterios de Aceptación

1. THE `Sistema_Vistas` SHALL definir una vista denominada `vw_pedidos_cliente` sobre las tablas `pedido` y `cliente`.

2. WHEN un consumidor consulta `vw_pedidos_cliente`, THE `Sistema_Vistas` SHALL retornar exactamente las columnas `pedido.id AS pedido_id`, `pedido.fecha`, `pedido.forma_pago`, `cliente.id AS cliente_id`, `cliente.nombre`, `cliente.apellido` y `cliente.activo`.

3. THE `Sistema_Vistas` SHALL omitir las columnas `cliente.email`, `cliente.telefono` y `cliente.created_at` de la definición de `vw_pedidos_cliente`, de modo que ningún consumidor con `SELECT` sobre la vista pueda acceder a esos datos de contacto.

4. WHERE la tabla `cliente` incorpore en el futuro una columna de autenticación (por ejemplo `contrasena VARCHAR`), THE `Sistema_Vistas` SHALL mantener esa columna fuera de la lista de columnas de `vw_pedidos_cliente` sin necesidad de modificar los permisos de los roles consumidores.

5. THE `Sistema_Vistas` SHALL documentar en un comentario inline de la definición SQL de `vw_pedidos_cliente` cuáles columnas están intencionalmente excluidas y el motivo de seguridad.

6. WHEN se ejecuta la consulta de equivalencia manual contra `vw_pedidos_cliente`, THE `Sistema_Vistas` SHALL producir un resultado donde la operación `(SELECT … FROM vw_pedidos_cliente) EXCEPT (SELECT … FROM pedido JOIN cliente …)` retorna cero filas en ambas direcciones.

---

### Requisito 3 — Vista del detalle de pedido con nombre de producto

**User Story:** Como operador de atención al cliente, quiero consultar el detalle de cualquier pedido con el nombre legible del producto, la cantidad, el precio unitario histórico y el subtotal, para generar comprobantes sin necesidad de hacer JOINs manuales.

#### Criterios de Aceptación

1. THE `Sistema_Vistas` SHALL definir una vista denominada `vw_detalle_pedido` sobre las tablas `pedido_detalle` y `producto`.

2. WHEN un consumidor consulta `vw_detalle_pedido`, THE `Sistema_Vistas` SHALL retornar exactamente las columnas `pedido_detalle.pedido_id`, `producto.nombre AS nombre_producto`, `pedido_detalle.cantidad`, `pedido_detalle.precio_unitario` y `pedido_detalle.subtotal`.

3. THE `Sistema_Vistas` SHALL implementar el `JOIN` entre `pedido_detalle` y `producto` mediante la condición `pedido_detalle.producto_id = producto.id`, garantizando que cada fila del resultado corresponda a exactamente un producto registrado.

4. WHEN un consumidor filtra `vw_detalle_pedido` con la condición `WHERE pedido_id = :id`, THE `Sistema_Vistas` SHALL retornar únicamente las líneas del pedido indicado, en el orden que el motor de base de datos determine por defecto.

5. WHEN se ejecuta la consulta de equivalencia manual contra `vw_detalle_pedido`, THE `Sistema_Vistas` SHALL producir un resultado donde la operación `(SELECT … FROM vw_detalle_pedido) EXCEPT (SELECT … FROM pedido_detalle JOIN producto …)` retorna cero filas en ambas direcciones.

---

### Requisito 4 — Verificación de equivalencia de vistas

**User Story:** Como responsable de calidad de la base de datos, quiero verificar que cada vista produce exactamente el mismo resultado que su consulta SQL equivalente escrita manualmente, para garantizar que la definición de la vista no introduce omisiones ni duplicados.

#### Criterios de Aceptación

1. THE `Sistema_Vistas` SHALL verificar la equivalencia de cada una de las tres vistas mediante la ejecución de dos operaciones `EXCEPT` simétricas:
   - `(consulta_via_vista) EXCEPT (consulta_manual)` → debe retornar 0 filas.
   - `(consulta_manual) EXCEPT (consulta_via_vista)` → debe retornar 0 filas.

2. WHEN ambos `EXCEPT` retornan 0 filas para una vista, THE `Sistema_Vistas` SHALL considerar esa vista como equivalente a su consulta manual.

3. IF alguno de los dos `EXCEPT` retorna una o más filas para cualquiera de las tres vistas, THEN THE `Sistema_Vistas` SHALL registrar las filas divergentes y el nombre de la vista afectada en el informe de mediciones.

4. THE `Sistema_Vistas` SHALL documentar los resultados de la verificación de equivalencia de las tres vistas en la sección correspondiente del archivo `TP3/informe_mediciones.md`.
