-- =====================================================================
-- Proyecto Integrador: Food Store (TP - Base de Datos II)
-- Archivo: procedures.sql
-- Motor: PostgreSQL 11+
-- Descripción: Implementación de procedimientos almacenados (Stored Procedures)
--              con lógica de negocio transaccional y control de errores.
-- =====================================================================

-- =====================================================================
-- PROCEDIMIENTO 1: sp_registrar_pedido
-- =====================================================================
-- Descripción:
--   Crea un nuevo pedido de manera atómica con sus líneas de detalle a
--   partir de un payload JSONB. Verifica la existencia y estado activo del
--   cliente, la vigencia y stock de cada producto solicitado (con bloqueo
--   pesimista FOR UPDATE), registra el pedido y sus detalles con precios
--   históricos, y descuenta las existencias de inventario.
--
-- Parámetros:
--   p_cliente_id   (IN)    : ID del cliente que realiza la compra.
--   p_forma_pago   (IN)    : Método de pago (tipo ENUM: forma_pago_enum).
--   p_items        (IN)    : Arreglo JSONB con los productos y cantidades.
--                            Formato: '[{"producto_id": 1, "cantidad": 2}, ...]'
--   p_pedido_id    (INOUT) : Retorna el ID generado para el nuevo pedido.
--
-- Reglas de negocio cubiertas:
--   - R1 / R2: Integridad referencial de cliente.
--   - R4: Registro de precio unitario histórico y subtotal en detalle.
--   - R5: Validación y control de no negatividad de stock.
--   - R7: Respeto a bajas lógicas (cliente y productos activos).
-- =====================================================================

CREATE OR REPLACE PROCEDURE sp_registrar_pedido(
    p_cliente_id   BIGINT,
    p_forma_pago   forma_pago_enum,
    p_items        JSONB,
    INOUT p_pedido_id BIGINT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_cliente_activo   BOOLEAN;
    v_item             JSONB;
    v_producto_id      BIGINT;
    v_cantidad         INTEGER;
    v_precio_actual    NUMERIC(10,2);
    v_stock_actual     INTEGER;
    v_producto_activo  BOOLEAN;
    v_producto_nombre  VARCHAR(100);
    v_subtotal         NUMERIC(10,2);
    v_total_pedido     NUMERIC(10,2) := 0.00;
    v_total_articulos  INTEGER := 0;
BEGIN
    -- -----------------------------------------------------------------
    -- 1. Validaciones iniciales de entrada
    -- -----------------------------------------------------------------
    IF p_cliente_id IS NULL THEN
        RAISE EXCEPTION 'El identificador del cliente (p_cliente_id) no puede ser nulo.';
    END IF;

    IF p_forma_pago IS NULL THEN
        RAISE EXCEPTION 'La forma de pago (p_forma_pago) no puede ser nula.';
    END IF;

    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'El parámetro p_items debe ser un arreglo JSONB no vacío con el formato [{"producto_id": 1, "cantidad": 2}, ...].';
    END IF;

    -- -----------------------------------------------------------------
    -- 2. Validar estado del cliente (Existencia y Regla 1: cliente activo)
    -- -----------------------------------------------------------------
    SELECT activo INTO v_cliente_activo
    FROM cliente
    WHERE id = p_cliente_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se puede registrar el pedido: El cliente con ID % no existe.', p_cliente_id;
    END IF;

    IF v_cliente_activo IS FALSE THEN
        RAISE EXCEPTION 'No se puede registrar el pedido: El cliente con ID % se encuentra inactivo.', p_cliente_id;
    END IF;

    -- -----------------------------------------------------------------
    -- 3. Crear cabecera del pedido
    -- -----------------------------------------------------------------
    INSERT INTO pedido (fecha, forma_pago, cliente_id, created_at)
    VALUES (now(), p_forma_pago, p_cliente_id, now())
    RETURNING id INTO p_pedido_id;

    -- -----------------------------------------------------------------
    -- 4. Procesar y validar cada producto del arreglo JSONB
    -- -----------------------------------------------------------------
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        -- Extraer y validar tipos de datos de cada elemento
        v_producto_id := (v_item->>'producto_id')::BIGINT;
        v_cantidad    := (v_item->>'cantidad')::INTEGER;

        IF v_producto_id IS NULL THEN
            RAISE EXCEPTION 'Cada elemento del pedido debe especificar un "producto_id" válido. Payload: %', v_item;
        END IF;

        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RAISE EXCEPTION 'La cantidad para el producto ID % debe ser un entero estrictamente mayor a 0 (recibido: %).',
                v_producto_id, v_item->>'cantidad';
        END IF;

        -- Bloqueo pesimista (FOR UPDATE) para control de concurrencia y lectura fresca
        SELECT nombre, precio, stock, activo
        INTO v_producto_nombre, v_precio_actual, v_stock_actual, v_producto_activo
        FROM producto
        WHERE id = v_producto_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'No se puede procesar el pedido: El producto con ID % no existe.', v_producto_id;
        END IF;

        -- Regla 3: Producto activo
        IF v_producto_activo IS FALSE THEN
            RAISE EXCEPTION 'No se puede procesar el pedido: El producto "%" (ID: %) está inactivo.',
                v_producto_nombre, v_producto_id;
        END IF;

        -- Regla 5: Stock suficiente
        IF v_stock_actual < v_cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente para el producto "%" (ID: %). Stock disponible: %, Cantidad solicitada: %.',
                v_producto_nombre, v_producto_id, v_stock_actual, v_cantidad;
        END IF;

        -- Cálculo de importes históricos (R4)
        v_subtotal := ROUND(v_precio_actual * v_cantidad, 2);
        v_total_pedido := v_total_pedido + v_subtotal;
        v_total_articulos := v_total_articulos + v_cantidad;

        -- Insertar línea de detalle
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
        VALUES (p_pedido_id, v_producto_id, v_cantidad, v_precio_actual, v_subtotal);

        -- Descontar stock
        UPDATE producto
        SET stock = stock - v_cantidad
        WHERE id = v_producto_id;

    END LOOP;

    RAISE NOTICE 'Pedido #% registrado exitosamente. Cliente ID: %, Artículos: %, Total: $ %.',
        p_pedido_id, p_cliente_id, v_total_articulos, v_total_pedido;

EXCEPTION
    WHEN OTHERS THEN
        -- PostgreSQL revierte automáticamente todas las operaciones realizadas dentro
        -- del bloque transaccional cuando se propaga una excepción.
        RAISE EXCEPTION 'Transacción cancelada al registrar pedido: %', SQLERRM;
END;
$$;


-- =====================================================================
-- PROCEDIMIENTO 2: sp_desactivar_producto_seguro
-- =====================================================================
-- Descripción:
--   Implementa la baja lógica controlada (R7) de un producto, asegurando
--   que no se efectúe borrado físico y verificando su estado actual
--   mediante bloqueo FOR UPDATE.
--
-- Parámetros:
--   p_producto_id (IN) : Identificador del producto a desactivar.
-- =====================================================================

CREATE OR REPLACE PROCEDURE sp_desactivar_producto_seguro(
    p_producto_id BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_nombre VARCHAR(100);
    v_activo BOOLEAN;
    v_stock  INTEGER;
BEGIN
    IF p_producto_id IS NULL THEN
        RAISE EXCEPTION 'El identificador del producto (p_producto_id) no puede ser nulo.';
    END IF;

    -- Bloqueo pesimista para evitar carreras al actualizar el estado
    SELECT nombre, activo, stock
    INTO v_nombre, v_activo, v_stock
    FROM producto
    WHERE id = p_producto_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se puede desactivar: El producto con ID % no existe.', p_producto_id;
    END IF;

    IF v_activo IS FALSE THEN
        RAISE NOTICE 'El producto "%" (ID: %) ya se encontraba inactivo. No se realizaron cambios.', v_nombre, p_producto_id;
        RETURN;
    END IF;

    -- Aplicación de baja lógica (R7)
    UPDATE producto
    SET activo = FALSE
    WHERE id = p_producto_id;

    RAISE NOTICE 'Producto "%" (ID: %) desactivado exitosamente (baja lógica). Stock residual conservado: % unidades.',
        v_nombre, p_producto_id, v_stock;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error al desactivar el producto ID %: %', p_producto_id, SQLERRM;
END;
$$;


-- =====================================================================
-- PROCEDIMIENTO 3: sp_actualizar_precios_categoria
-- =====================================================================
-- Descripción:
--   Ajusta masiva y porcentualmente los precios de todos los productos
--   vigentes pertenecientes a una categoría específica, redondeando a 2
--   decimales y validando que no se generen precios negativos (R5).
--
-- Parámetros:
--   p_categoria_id (IN) : ID de la categoría a actualizar.
--   p_porcentaje   (IN) : Porcentaje de ajuste (ej: 10.00 para +10%, -5.00 para -5%).
-- =====================================================================

CREATE OR REPLACE PROCEDURE sp_actualizar_precios_categoria(
    p_categoria_id BIGINT,
    p_porcentaje   NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_categoria_nombre VARCHAR(80);
    v_categoria_activa BOOLEAN;
    v_filas_afectadas  INTEGER;
BEGIN
    -- Validaciones de parámetros
    IF p_categoria_id IS NULL THEN
        RAISE EXCEPTION 'El identificador de categoría (p_categoria_id) no puede ser nulo.';
    END IF;

    IF p_porcentaje IS NULL THEN
        RAISE EXCEPTION 'El porcentaje de ajuste (p_porcentaje) no puede ser nulo.';
    END IF;

    IF p_porcentaje < -100.00 THEN
        RAISE EXCEPTION 'El porcentaje no puede ser inferior a -100.00 (resultaria en precios negativos).';
    END IF;

    -- Verificar existencia y vigencia de la categoría
    SELECT nombre, activo
    INTO v_categoria_nombre, v_categoria_activa
    FROM categoria
    WHERE id = p_categoria_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La categoría con ID % no existe.', p_categoria_id;
    END IF;

    IF v_categoria_activa IS FALSE THEN
        RAISE EXCEPTION 'No se pueden actualizar precios: La categoría "%" (ID: %) está inactiva.',
            v_categoria_nombre, p_categoria_id;
    END IF;

    -- Actualización atómica de precios
    UPDATE producto
    SET precio = ROUND(precio * (1.0 + (p_porcentaje / 100.0)), 2)
    WHERE categoria_id = p_categoria_id
      AND activo = TRUE;

    GET DIAGNOSTICS v_filas_afectadas = ROW_COUNT;

    RAISE NOTICE 'Precios actualizados en la categoría "%" (ID: %): % producto(s) modificado(s) con ajuste de % por ciento.',
        v_categoria_nombre, p_categoria_id, v_filas_afectadas, p_porcentaje;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error al actualizar precios de la categoría ID %: %', p_categoria_id, SQLERRM;
END;
$$;


-- =====================================================================
-- EJEMPLOS DE INVOCACIÓN (CALL) Y PRUEBAS DE VALIDACIÓN
-- =====================================================================

/*
-- ---------------------------------------------------------------------
-- Caso 1: Registro Exitoso de Pedido con Múltiples Productos
-- ---------------------------------------------------------------------
-- Registra una compra para el cliente Juan Pérez (ID 1), abonando con TARJETA,
-- adquiriendo 2 unidades de Coca Cola (ID 1) y 1 unidad de Papas Fritas (ID 3).
DO $$
DECLARE
    v_nuevo_pedido_id BIGINT;
BEGIN
    CALL sp_registrar_pedido(
        p_cliente_id := 1,
        p_forma_pago := 'TARJETA'::forma_pago_enum,
        p_items      := '[
            {"producto_id": 1, "cantidad": 2},
            {"producto_id": 3, "cantidad": 1}
        ]'::jsonb,
        p_pedido_id  := v_nuevo_pedido_id
    );

    RAISE NOTICE 'ID del pedido generado: %', v_nuevo_pedido_id;
END;
$$;

-- Verificar la inserción del pedido y detalle:
-- SELECT * FROM pedido ORDER BY id DESC LIMIT 1;
-- SELECT * FROM pedido_detalle WHERE pedido_id = (SELECT MAX(id) FROM pedido);
-- SELECT id, nombre, stock FROM producto WHERE id IN (1, 3);


-- ---------------------------------------------------------------------
-- Caso 2: Intento de Pedido con Cliente Inactivo (Error y Rollback)
-- ---------------------------------------------------------------------
-- El cliente ID 3 (Carlos Inactivo) tiene activo = FALSE.
-- Debe abortar con excepción y no registrar pedido ni descontar stock.
CALL sp_registrar_pedido(
    p_cliente_id := 3,
    p_forma_pago := 'EFECTIVO'::forma_pago_enum,
    p_items      := '[{"producto_id": 1, "cantidad": 1}]'::jsonb
);


-- ---------------------------------------------------------------------
-- Caso 3: Intento de Pedido con Stock Insuficiente (Error y Rollback)
-- ---------------------------------------------------------------------
-- Solicita 9999 unidades de un producto con stock menor.
-- Debe arrojar excepción por stock insuficiente y revertir toda la transacción.
CALL sp_registrar_pedido(
    p_cliente_id := 1,
    p_forma_pago := 'TRANSFERENCIA'::forma_pago_enum,
    p_items      := '[{"producto_id": 1, "cantidad": 9999}]'::jsonb
);


-- ---------------------------------------------------------------------
-- Caso 4: Intento de Pedido con Producto Inactivo (Error y Rollback)
-- ---------------------------------------------------------------------
-- El producto ID 5 ("Producto Descatalogado") tiene activo = FALSE.
CALL sp_registrar_pedido(
    p_cliente_id := 1,
    p_forma_pago := 'EFECTIVO'::forma_pago_enum,
    p_items      := '[{"producto_id": 5, "cantidad": 1}]'::jsonb
);


-- ---------------------------------------------------------------------
-- Caso 5: Desactivación Segura de Producto (Baja Lógica)
-- ---------------------------------------------------------------------
-- Desactiva el producto ID 2 ("Agua Mineral 500ml") preservando stock e historial.
CALL sp_desactivar_producto_seguro(p_producto_id := 2);

-- Verificar baja lógica:
-- SELECT id, nombre, activo, stock FROM producto WHERE id = 2;


-- ---------------------------------------------------------------------
-- Caso 6: Actualización Masiva de Precios por Categoría
-- ---------------------------------------------------------------------
-- Aplica un aumento del 15% a todos los productos activos de la categoría "Bebidas" (ID 1).
CALL sp_actualizar_precios_categoria(
    p_categoria_id := 1,
    p_porcentaje   := 15.00
);

-- Verificar nuevos precios:
-- SELECT id, nombre, precio, activo FROM producto WHERE categoria_id = 1;
*/
