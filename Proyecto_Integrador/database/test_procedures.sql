-- =====================================================================
-- Archivo de Pruebas: test_procedures.sql
-- Motor: PostgreSQL
-- Descripción: Suite integral de pruebas para validar el correcto
--              funcionamiento de los Procedimientos Almacenados.
--              (Sintaxis 100% ANSI SQL / PLpgSQL compatible con pgAdmin,
--               DBeaver, DataGrip y psql).
-- =====================================================================

DO $$
DECLARE
    -- Variables para Test 1
    v_pedido_id       BIGINT;
    v_stock_coca_ant  INTEGER;
    v_stock_papas_ant INTEGER;
    v_stock_coca_act  INTEGER;
    v_stock_papas_act INTEGER;
    v_cant_detalles   INTEGER;

    -- Variables para Test 2
    v_pedidos_antes   INTEGER;
    v_pedidos_desp    INTEGER;
    v_error_t2        BOOLEAN := FALSE;

    -- Variables para Test 3
    v_stock_antes_t3   INTEGER;
    v_stock_despues_t3 INTEGER;
    v_error_t3         BOOLEAN := FALSE;

    -- Variables para Test 4
    v_activo_antes_t4   BOOLEAN;
    v_activo_despues_t4 BOOLEAN;
    v_error_t4          BOOLEAN := FALSE;

    -- Variables para Test 5
    v_precio_antes_t5   NUMERIC(10,2);
    v_precio_despues_t5 NUMERIC(10,2);
    v_precio_esperado   NUMERIC(10,2);
BEGIN
    RAISE NOTICE '======================================================';
    RAISE NOTICE 'INICIANDO SUITE DE PRUEBAS DE PROCEDIMIENTOS';
    RAISE NOTICE '======================================================';

    -- -----------------------------------------------------------------
    -- TEST 1: Registro Exitoso de Pedido y Descuento de Stock (Happy Path)
    -- -----------------------------------------------------------------
    RAISE NOTICE '--- [TEST 1/5] Registro de pedido multi-ítem y stock ---';
    
    SELECT stock INTO v_stock_coca_ant FROM producto WHERE id = 1;  -- Coca Cola (Stock inicial)
    SELECT stock INTO v_stock_papas_ant FROM producto WHERE id = 3; -- Papas Fritas (Stock inicial)

    -- Compra: 2 Coca Colas (ID 1) y 1 Papas Fritas (ID 3)
    CALL sp_registrar_pedido(
        p_cliente_id := 1,
        p_forma_pago := 'TARJETA'::forma_pago_enum,
        p_items      := '[{"producto_id": 1, "cantidad": 2}, {"producto_id": 3, "cantidad": 1}]'::jsonb,
        p_pedido_id  := v_pedido_id
    );

    IF v_pedido_id IS NULL THEN
        RAISE EXCEPTION 'TEST 1 FALLO: No se retorno el ID del nuevo pedido.';
    END IF;

    SELECT stock INTO v_stock_coca_act FROM producto WHERE id = 1;
    SELECT stock INTO v_stock_papas_act FROM producto WHERE id = 3;

    IF v_stock_coca_act <> (v_stock_coca_ant - 2) THEN
        RAISE EXCEPTION 'TEST 1 FALLO: El stock de Coca Cola no disminuyo en 2 unidades.';
    END IF;

    IF v_stock_papas_act <> (v_stock_papas_ant - 1) THEN
        RAISE EXCEPTION 'TEST 1 FALLO: El stock de Papas Fritas no disminuyo en 1 unidad.';
    END IF;

    SELECT COUNT(*) INTO v_cant_detalles FROM pedido_detalle WHERE pedido_id = v_pedido_id;
    IF v_cant_detalles <> 2 THEN
        RAISE EXCEPTION 'TEST 1 FALLO: Se esperaban 2 lineas de detalle, encontradas %.', v_cant_detalles;
    END IF;

    RAISE NOTICE 'OK: TEST 1 PASO CON EXITO (Pedido #% creado y stock descontado).', v_pedido_id;


    -- -----------------------------------------------------------------
    -- TEST 2: Validación de Cliente Inactivo (Debe fallar sin efectos)
    -- -----------------------------------------------------------------
    RAISE NOTICE '--- [TEST 2/5] Validacion con Cliente Inactivo ---';
    
    SELECT COUNT(*) INTO v_pedidos_antes FROM pedido;

    BEGIN
        -- Cliente ID 3 (Carlos Inactivo) tiene activo = FALSE
        CALL sp_registrar_pedido(
            p_cliente_id := 3,
            p_forma_pago := 'EFECTIVO'::forma_pago_enum,
            p_items      := '[{"producto_id": 1, "cantidad": 1}]'::jsonb
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_error_t2 := TRUE;
    END;

    SELECT COUNT(*) INTO v_pedidos_desp FROM pedido;

    IF NOT v_error_t2 THEN
        RAISE EXCEPTION 'TEST 2 FALLO: Se permitio crear un pedido con cliente inactivo.';
    END IF;

    IF v_pedidos_antes <> v_pedidos_desp THEN
        RAISE EXCEPTION 'TEST 2 FALLO: Se creo un registro huérfano en pedido a pesar del error.';
    END IF;

    RAISE NOTICE 'OK: TEST 2 PASO CON EXITO (Cliente inactivo bloqueado correctamente).';


    -- -----------------------------------------------------------------
    -- TEST 3: Validación de Stock Insuficiente y Rollback Atómico
    -- -----------------------------------------------------------------
    RAISE NOTICE '--- [TEST 3/5] Validacion de Stock Insuficiente y Rollback ---';
    
    SELECT stock INTO v_stock_antes_t3 FROM producto WHERE id = 1;

    BEGIN
        -- Solicitar 99999 unidades (excede stock)
        CALL sp_registrar_pedido(
            p_cliente_id := 1,
            p_forma_pago := 'EFECTIVO'::forma_pago_enum,
            p_items      := '[{"producto_id": 1, "cantidad": 99999}]'::jsonb
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_error_t3 := TRUE;
    END;

    SELECT stock INTO v_stock_despues_t3 FROM producto WHERE id = 1;

    IF NOT v_error_t3 THEN
        RAISE EXCEPTION 'TEST 3 FALLO: No se disparo el error de stock insuficiente.';
    END IF;

    IF v_stock_antes_t3 <> v_stock_despues_t3 THEN
        RAISE EXCEPTION 'TEST 3 FALLO: El stock fue alterado a pesar del error transaccional.';
    END IF;

    RAISE NOTICE 'OK: TEST 3 PASO CON EXITO (Rollback atomico verificado).';


    -- -----------------------------------------------------------------
    -- TEST 4: Baja Lógica Segura con sp_desactivar_producto_seguro
    -- -----------------------------------------------------------------
    RAISE NOTICE '--- [TEST 4/5] Desactivacion Segura de Producto (Baja Logica) ---';
    
    SELECT activo INTO v_activo_antes_t4 FROM producto WHERE id = 2; -- Agua Mineral (activo = TRUE)

    IF v_activo_antes_t4 IS FALSE THEN
        RAISE EXCEPTION 'TEST 4 PRECONDICION: El producto ID 2 ya estaba inactivo.';
    END IF;

    -- Ejecutar baja lógica
    CALL sp_desactivar_producto_seguro(p_producto_id := 2);

    SELECT activo INTO v_activo_despues_t4 FROM producto WHERE id = 2;
    IF v_activo_despues_t4 IS NOT FALSE THEN
        RAISE EXCEPTION 'TEST 4 FALLO: El producto no quedo con activo = FALSE.';
    END IF;

    -- Intentar comprar el producto recién desactivado
    BEGIN
        CALL sp_registrar_pedido(
            p_cliente_id := 1,
            p_forma_pago := 'EFECTIVO'::forma_pago_enum,
            p_items      := '[{"producto_id": 2, "cantidad": 1}]'::jsonb
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_error_t4 := TRUE;
    END;

    IF NOT v_error_t4 THEN
        RAISE EXCEPTION 'TEST 4 FALLO: Se permitio vender un producto desactivado.';
    END IF;

    RAISE NOTICE 'OK: TEST 4 PASO CON EXITO (Baja logica aplicada y validada en ventas).';


    -- -----------------------------------------------------------------
    -- TEST 5: Actualización Masiva de Precios por Categoría
    -- -----------------------------------------------------------------
    RAISE NOTICE '--- [TEST 5/5] Actualizacion Porcentual de Precios ---';
    
    SELECT precio INTO v_precio_antes_t5 FROM producto WHERE id = 1; -- Coca Cola
    v_precio_esperado := ROUND(v_precio_antes_t5 * 1.10, 2);

    -- Incrementar 10% a categoría Bebidas (ID 1)
    CALL sp_actualizar_precios_categoria(p_categoria_id := 1, p_porcentaje := 10.00);

    SELECT precio INTO v_precio_despues_t5 FROM producto WHERE id = 1;

    IF v_precio_despues_t5 <> v_precio_esperado THEN
        RAISE EXCEPTION 'TEST 5 FALLO: Precio actual ($ %) no coincide con el esperado ($ %).',
            v_precio_despues_t5, v_precio_esperado;
    END IF;

    RAISE NOTICE 'OK: TEST 5 PASO CON EXITO (Ajuste +10%% aplicado: $ % -> $ %).',
        v_precio_antes_t5, v_precio_despues_t5;

    -- -----------------------------------------------------------------
    -- Resumen Final
    -- -----------------------------------------------------------------
    RAISE NOTICE '======================================================';
    RAISE NOTICE 'TODOS LOS TESTS COMPLETADOS SATISFACTORIAMENTE (5/5)';
    RAISE NOTICE '======================================================';
END;
$$ LANGUAGE plpgsql;
