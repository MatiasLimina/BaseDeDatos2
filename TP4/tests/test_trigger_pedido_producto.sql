-- Test (Parte 2, grupo 8): disparadores trg_vdc_pedido (eliminado / fecha) y trg_vdc_producto (categoria_id).
-- Ejecutar: psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f TP4/tests/test_trigger_pedido_producto.sql
-- Requiere la seccion 4 de TP4/tp_desnormalizacion_top_categorias.sql (con disparadores instalados).
-- Cada escenario va en un subbloque que termina con una excepcion centinela (SQLSTATE T4RB1) que
-- revierte sus datos. Productos de apoyo: 10 -> categoria 1, 11 -> categoria 2, 13 -> 4, 14 -> 5.
-- Dias de prueba: hoy, ayer (hoy - 1) y el dia lejano 2030-01-15.

CREATE OR REPLACE FUNCTION t4_vdc_total(p_f DATE, p_c BIGINT) RETURNS NUMERIC LANGUAGE sql AS
$$ SELECT coalesce((SELECT total_vendido FROM ventas_diarias_categoria WHERE fecha = p_f AND categoria_id = p_c), 0) $$;
CREATE OR REPLACE FUNCTION t4_vdc_lineas(p_f DATE, p_c BIGINT) RETURNS INTEGER LANGUAGE sql AS
$$ SELECT coalesce((SELECT cantidad_lineas FROM ventas_diarias_categoria WHERE fecha = p_f AND categoria_id = p_c), 0) $$;

DO $$
DECLARE
    v_hoy   DATE := fn_dia_negocio(now());
    v_ayer  DATE := fn_dia_negocio(now()) - 1;
    v_d2    DATE := DATE '2030-01-15';
    v_ts2   TIMESTAMPTZ := TIMESTAMPTZ '2030-01-15 12:00:00-03';
    v_p     BIGINT;
    v_q     BIGINT;
    v_cat13 BIGINT;
    v_cat14 BIGINT;
    b1 NUMERIC; b2 NUMERIC; l1 INTEGER; l2 INTEGER;
    c13 NUMERIC; c14 NUMERIC; s13_hoy NUMERIC; n13_hoy INTEGER;
    v_n BIGINT;
BEGIN
    ASSERT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_vdc_pedido' AND NOT tgisinternal),
           'no existe el disparador trg_vdc_pedido';
    ASSERT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_vdc_producto' AND NOT tgisinternal),
           'no existe el disparador trg_vdc_producto';

    -- P) Baja logica de un pedido con detalles en dos categorias (y un detalle ya eliminado), y reactivacion
    BEGIN
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now(), 'EFECTIVO', 1) RETURNING id INTO v_p;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 10, 1, 100.00, 100.00), (v_p, 11, 1, 40.50, 40.50);
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal, eliminado) VALUES (v_p, 20, 1, 9.99, 9.99, TRUE);
        b1 := t4_vdc_total(v_hoy, 1); b2 := t4_vdc_total(v_hoy, 2); l1 := t4_vdc_lineas(v_hoy, 1); l2 := t4_vdc_lineas(v_hoy, 2);
        UPDATE pedido SET eliminado = TRUE WHERE id = v_p;
        ASSERT t4_vdc_total(v_hoy, 1) = b1 - 100.00 AND t4_vdc_lineas(v_hoy, 1) = l1 - 1, 'P1: cat 1 = ' || t4_vdc_total(v_hoy, 1) || ' esperado ' || (b1 - 100.00);
        ASSERT t4_vdc_total(v_hoy, 2) = b2 - 40.50  AND t4_vdc_lineas(v_hoy, 2) = l2 - 1, 'P2: cat 2 = ' || t4_vdc_total(v_hoy, 2);
        UPDATE pedido SET eliminado = FALSE WHERE id = v_p;
        ASSERT t4_vdc_total(v_hoy, 1) = b1 AND t4_vdc_total(v_hoy, 2) = b2 AND t4_vdc_lineas(v_hoy, 1) = l1 AND t4_vdc_lineas(v_hoy, 2) = l2,
               'P3: la reactivacion debia restituir ambas categorias (el detalle eliminado no vuelve)';
        -- triangulacion: dar de baja un pedido que ya esta dado de baja (TRUE -> TRUE) no hace nada
        UPDATE pedido SET eliminado = TRUE WHERE id = v_p;
        UPDATE pedido SET eliminado = TRUE, fecha = now() WHERE id = v_p;
        ASSERT t4_vdc_total(v_hoy, 1) = b1 - 100.00, 'P4: TRUE -> TRUE no debe restar dos veces';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- Q) Cambio de fecha hoy -> ayer y vuelta; y a un dia lejano; y dentro del mismo dia (sin efecto neto)
    BEGIN
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now(), 'EFECTIVO', 1) RETURNING id INTO v_p;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 10, 1, 100.00, 100.00), (v_p, 11, 1, 40.50, 40.50);
        b1 := t4_vdc_total(v_hoy, 1); b2 := t4_vdc_total(v_hoy, 2);
        c13 := t4_vdc_total(v_ayer, 1); c14 := t4_vdc_total(v_ayer, 2);
        UPDATE pedido SET fecha = fecha - INTERVAL '1 day' WHERE id = v_p;
        ASSERT t4_vdc_total(v_hoy, 1) = b1 - 100.00 AND t4_vdc_total(v_hoy, 2) = b2 - 40.50, 'Q1: hoy debia perder los subtotales';
        ASSERT t4_vdc_total(v_ayer, 1) = c13 + 100.00 AND t4_vdc_total(v_ayer, 2) = c14 + 40.50, 'Q2: ayer debia ganar los mismos subtotales en las mismas categorias';
        UPDATE pedido SET fecha = fecha + INTERVAL '1 day' WHERE id = v_p;
        ASSERT t4_vdc_total(v_hoy, 1) = b1 AND t4_vdc_total(v_hoy, 2) = b2 AND t4_vdc_total(v_ayer, 1) = c13 AND t4_vdc_total(v_ayer, 2) = c14, 'Q3: vuelta atras';
        UPDATE pedido SET fecha = v_ts2 WHERE id = v_p;
        ASSERT t4_vdc_total(v_d2, 1) = 100.00 AND t4_vdc_total(v_d2, 2) = 40.50 AND t4_vdc_lineas(v_d2, 1) = 1, 'Q4: dia lejano';
        UPDATE pedido SET fecha = v_ts2 + INTERVAL '1 hour' WHERE id = v_p;   -- mismo dia de negocio
        ASSERT t4_vdc_total(v_d2, 1) = 100.00 AND t4_vdc_total(v_d2, 2) = 40.50 AND t4_vdc_lineas(v_d2, 1) = 1, 'Q5: mismo dia, sin efecto neto';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- Q2) Un pedido vigente cerca de medianoche: 23:30 de Buenos Aires cuenta en su dia, aun con sesion en UTC
    BEGIN
        SET LOCAL TimeZone = 'UTC';
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (TIMESTAMPTZ '2030-01-15 23:30:00-03', 'EFECTIVO', 1) RETURNING id INTO v_p;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 10, 1, 100.00, 100.00);
        ASSERT t4_vdc_total(v_d2, 1) = 100.00, 'Q6: el pedido de las 23:30 BA debia contarse el 2030-01-15';
        ASSERT t4_vdc_total(v_d2 + 1, 1) = 0, 'Q6: no debia contarse el dia siguiente (UTC)';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- R) Recategorizacion de un producto con ventas en varios dias: 13 (cat 4) pasa a la categoria de 14
    SELECT categoria_id INTO v_cat13 FROM producto WHERE id = 13;
    SELECT categoria_id INTO v_cat14 FROM producto WHERE id = 14;
    ASSERT v_cat13 <> v_cat14, 'R0: los productos de apoyo 13 y 14 deben ser de categorias distintas';
    BEGIN
        -- ventas del producto 13 en tres dias: hoy (hay historia generada), ayer y el dia lejano; mas un detalle eliminado y uno de pedido eliminado
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now() - INTERVAL '1 day', 'EFECTIVO', 1) RETURNING id INTO v_p;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 13, 1, 70.00, 70.00);
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (v_ts2, 'EFECTIVO', 1) RETURNING id INTO v_p;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 13, 1, 30.00, 30.00);
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal, eliminado) VALUES (v_p, 14, 1, 999.00, 999.00, TRUE);
        INSERT INTO pedido (fecha, forma_pago, cliente_id, eliminado) VALUES (v_ts2, 'EFECTIVO', 1, TRUE) RETURNING id INTO v_p;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 13, 1, 555.00, 555.00);

        SELECT coalesce(sum(d.subtotal), 0), count(*) INTO s13_hoy, n13_hoy
        FROM   pedido_detalle d JOIN pedido p ON p.id = d.pedido_id
        WHERE  d.producto_id = 13 AND NOT d.eliminado AND NOT p.eliminado AND fn_dia_negocio(p.fecha) = v_hoy;
        ASSERT s13_hoy > 0, 'R0: el producto 13 debia tener ventas hoy';
        b1 := t4_vdc_total(v_hoy, v_cat13); b2 := t4_vdc_total(v_hoy, v_cat14);
        c13 := t4_vdc_total(v_ayer, v_cat13); c14 := t4_vdc_total(v_ayer, v_cat14);

        UPDATE producto SET categoria_id = v_cat14 WHERE id = 13;
        ASSERT t4_vdc_total(v_hoy, v_cat13) = b1 - s13_hoy AND t4_vdc_total(v_hoy, v_cat14) = b2 + s13_hoy, 'R1: hoy = ' || t4_vdc_total(v_hoy, v_cat14) || ' esperado ' || (b2 + s13_hoy);
        ASSERT t4_vdc_lineas(v_hoy, v_cat13) = (SELECT count(*) FROM pedido_detalle d JOIN pedido p ON p.id = d.pedido_id JOIN producto pr ON pr.id = d.producto_id WHERE pr.categoria_id = v_cat13 AND NOT d.eliminado AND NOT p.eliminado AND fn_dia_negocio(p.fecha) = v_hoy), 'R1b: lineas';
        ASSERT t4_vdc_total(v_ayer, v_cat13) = c13 - 70.00 AND t4_vdc_total(v_ayer, v_cat14) = c14 + 70.00, 'R2: ayer';
        ASSERT t4_vdc_total(v_d2, v_cat13) = 0 AND t4_vdc_total(v_d2, v_cat14) = 30.00, 'R3: dia lejano (el detalle eliminado y el pedido eliminado no cuentan)';

        -- fuente vs tabla completa: 0 diferencias
        SELECT count(*) INTO v_n FROM (
            SELECT fn_dia_negocio(p.fecha) AS fecha, pr.categoria_id, SUM(d.subtotal) AS total, COUNT(*) AS lineas
            FROM   pedido_detalle d JOIN pedido p ON p.id = d.pedido_id JOIN producto pr ON pr.id = d.producto_id
            WHERE  NOT p.eliminado AND NOT d.eliminado GROUP BY 1, 2) f
        FULL OUTER JOIN ventas_diarias_categoria v ON v.fecha = f.fecha AND v.categoria_id = f.categoria_id
        WHERE f.total IS DISTINCT FROM v.total_vendido OR f.lineas IS DISTINCT FROM v.cantidad_lineas;
        ASSERT v_n = 0, 'R4: diferencias contra la fuente tras recategorizar: ' || v_n;

        -- vuelta atras (14 no cambia de categoria): todo vuelve a los valores iniciales
        UPDATE producto SET categoria_id = v_cat13 WHERE id = 13;
        ASSERT t4_vdc_total(v_hoy, v_cat13) = b1 AND t4_vdc_total(v_hoy, v_cat14) = b2 AND t4_vdc_total(v_ayer, v_cat13) = c13 AND t4_vdc_total(v_d2, v_cat13) = 30.00,
               'R5: vuelta atras';
        -- cambios que NO son de categoria no tocan la tabla
        UPDATE producto SET nombre = nombre || ' ' WHERE id = 13;
        UPDATE producto SET categoria_id = v_cat13 WHERE id = 13;
        ASSERT t4_vdc_total(v_hoy, v_cat13) = b1, 'R6: un UPDATE sin cambio de categoria no altera los totales';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- S) Triangulacion de recategorizacion: producto sin ventas (no altera nada) y con ventas solo en un dia
    BEGIN
        INSERT INTO producto (nombre, precio, stock, categoria_id) VALUES ('t4 producto sin ventas', 1.00, 0, 1) RETURNING id INTO v_p;
        SELECT count(*), coalesce(sum(total_vendido), 0) INTO v_n, b1 FROM ventas_diarias_categoria;
        UPDATE producto SET categoria_id = 2 WHERE id = v_p;
        SELECT count(*), coalesce(sum(total_vendido), 0) INTO v_n, b2 FROM ventas_diarias_categoria;
        ASSERT b1 = b2, 'S1: recategorizar un producto sin ventas no debe alterar la tabla';
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (v_ts2, 'EFECTIVO', 1) RETURNING id INTO v_q;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_q, v_p, 1, 25.00, 25.00);
        ASSERT t4_vdc_total(v_d2, 2) = 25.00, 'S2: venta en la categoria 2';
        UPDATE producto SET categoria_id = 3 WHERE id = v_p;
        ASSERT t4_vdc_total(v_d2, 2) = 0 AND t4_vdc_total(v_d2, 3) = 25.00 AND t4_vdc_lineas(v_d2, 3) = 1, 'S3: la unica venta pasa a la categoria 3 y la fila de la 2 desaparece';
        ASSERT NOT EXISTS (SELECT 1 FROM ventas_diarias_categoria WHERE fecha = v_d2 AND categoria_id = 2), 'S3b: la fila vacia debia borrarse';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;
END $$;

DROP FUNCTION t4_vdc_total(DATE, BIGINT);
DROP FUNCTION t4_vdc_lineas(DATE, BIGINT);
