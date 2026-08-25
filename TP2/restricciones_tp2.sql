-- =====================================================================
-- Proyecto Integrador: Food Store (TP2 - Parte 1)
-- Archivo: restricciones_tp2.sql
-- Motor: PostgreSQL
-- Descripción: Implementación de restricciones de negocio mediante Triggers
--              y validaciones declarativas (CHECK).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Regla 1: Un cliente inactivo (activo = FALSE) no puede realizar pedidos nuevos.
-- Mecanismo: Trigger BEFORE INSERT en la tabla 'pedido'.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_verificar_cliente_activo()
RETURNS TRIGGER AS $$
DECLARE
    v_activo BOOLEAN;
BEGIN
    SELECT activo INTO v_activo
    FROM cliente
    WHERE id = NEW.cliente_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El cliente con ID % no existe.', NEW.cliente_id;
    END IF;

    IF v_activo IS FALSE THEN
        RAISE EXCEPTION 'No se puede crear el pedido: El cliente (ID: %) se encuentra inactivo.', NEW.cliente_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_verificar_cliente_activo ON pedido;

CREATE TRIGGER trg_verificar_cliente_activo
    BEFORE INSERT ON pedido
    FOR EACH ROW
    EXECUTE FUNCTION fn_verificar_cliente_activo();


-- ---------------------------------------------------------------------
-- Regla 2: Un pedido no puede contener cantidades iguales o menores a 0.
-- Mecanismo: Restricción declarativa CHECK (ya definida en DDL, documentada y reforzada aquí).
-- ---------------------------------------------------------------------

-- Nota: Si la restricción ya existe en el DDL base, aseguramos su presencia o la documentamos formalmente.
-- ALTER TABLE pedido_detalle DROP CONSTRAINT IF EXISTS chk_detalle_cantidad_positiva;
-- ALTER TABLE pedido_detalle ADD CONSTRAINT chk_detalle_cantidad_positiva CHECK (cantidad > 0);


-- ---------------------------------------------------------------------
-- Regla 3: Un producto inactivo (activo = FALSE) no puede ser utilizado en nuevos pedidos.
-- Mecanismo: Trigger BEFORE INSERT en la tabla 'pedido_detalle'.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_verificar_producto_activo()
RETURNS TRIGGER AS $$
DECLARE
    v_activo BOOLEAN;
    v_nombre VARCHAR(100);
BEGIN
    SELECT activo, nombre INTO v_activo, v_nombre
    FROM producto
    WHERE id = NEW.producto_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El producto con ID % no existe.', NEW.producto_id;
    END IF;

    IF v_activo IS FALSE THEN
        RAISE EXCEPTION 'No se puede agregar el producto "%" (ID: %) al pedido porque se encuentra inactivo.', v_nombre, NEW.producto_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_verificar_producto_activo ON pedido_detalle;

CREATE TRIGGER trg_verificar_producto_activo
    BEFORE INSERT ON pedido_detalle
    FOR EACH ROW
    EXECUTE FUNCTION fn_verificar_producto_activo();
