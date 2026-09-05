# Declaración de Uso de IA (DUIA) — Parte 1 (TP2)

| Campo | Completar |
|---|---|
| **Herramienta** | OpenCode (modelo `google/gemini-3.5-flash-lite`) |
| **Spec o prompt utilizado** | 1. Dentro de la tabla “cliente”, en la columna “activo”, un cliente con estado `false` no debe ser capaz de realizar pedidos nuevos.<br>2. Dentro de la tabla “pedido_detalle”, en la columna “cantidad”, si un detalle intenta ser creado con cantidad `<= 0` no debe ser permitido.<br>3. Dentro de la tabla “producto”, en la columna “activo”, si el estado es `false` no se debe permitir que este producto sea usado en pedidos. |
| **Qué generó** | Un script SQL (`restricciones_tp2.sql`) conteniendo dos funciones PL/pgSQL con sus respectivos triggers (`trg_verificar_cliente_activo` y `trg_verificar_producto_activo`), además de la documentación/referencia para la restricción `CHECK` de cantidad en `pedido_detalle`. |
| **Qué se aceptó** | La lógica completa de validación mediante triggers para las reglas 1 y 3, incluyendo manejo de excepciones con mensajes claros (`RAISE EXCEPTION`), y la verificación de existencia (`IF NOT FOUND`). |
| **Qué se modificó o descartó, y por qué** | Se ajustaron los mensajes de error en los triggers para que devuelvan información detallada (IDs y nombres de productos/clientes) facilitando el diagnóstico operativo. |
| **Verificación realizada** | **Prueba 1 (Cliente inactivo):** Se intentó insertar un pedido para un cliente con `activo = FALSE`. Resultado: Rechazado por el trigger con el mensaje *"No se puede crear el pedido: El cliente (ID: ...) se encuentra inactivo."*<br>**Prueba 2 (Cantidad inválida):** Se intentó insertar un detalle con `cantidad = 0`. Resultado: Rechazado por la restricción `CHECK` (`chk_detalle_cantidad_positiva`).<br>**Prueba 3 (Producto inactivo):** Se intentó agregar un producto con `activo = FALSE` en un pedido. Resultado: Rechazado por el trigger con el mensaje *"No se puede agregar el producto ... porque se encuentra inactivo."* |
