-- Test (Parte 2, grupo 8): disparador trg_vdc_pedido_detalle (INSERT / UPDATE / DELETE de detalles).
-- *** REQUIERE haber cargado Proyecto_Integrador/database/tp4_datos_prueba_top_categorias.sql (SOLO EN COPIA) ***
-- (supone ademas que la base se armo con generar_registros_adaptado.sql y SIN triggers.sql; ver el encabezado del archivo de datos de prueba)
-- Ejecutar: psql -v ON_ERROR_STOP=1 -d <base> -f Proyecto_Integrador/database/tests_tp4/test_trigger_detalle.sql
-- Requiere la seccion 4 de Proyecto_Integrador/database/tp4_desnormalizacion_top_categorias.sql (con disparadores instalados).
-- Cada escenario se ejecuta en un subbloque que termina con una excepcion centinela (SQLSTATE T4RB1)
-- para revertir sus datos: la base queda igual. Productos de apoyo: 10 y 20 (misma categoria c1),
-- 11 (c2) y 12 (c3); las categorias se leen de `producto` y se verifican al inicio.
-- Dia de pruebas "lejano" (sin ventas reales): 2030-01-15.

-- Funciones auxiliares de lectura (se eliminan al final)
CREATE OR REPLACE FUNCTION t4_vdc_total(p_f DATE, p_c BIGINT) RETURNS NUMERIC LANGUAGE sql AS
$$ SELECT coalesce((SELECT total_vendido FROM ventas_diarias_categoria WHERE fecha = p_f AND categoria_id = p_c), 0) $$;
CREATE OR REPLACE FUNCTION t4_vdc_lineas(p_f DATE, p_c BIGINT) RETURNS INTEGER LANGUAGE sql AS
$$ SELECT coalesce((SELECT cantidad_lineas FROM ventas_diarias_categoria WHERE fecha = p_f AND categoria_id = p_c), 0) $$;

DO $$
DECLARE
    v_hoy DATE := fn_dia_negocio(now());
    v_d2  DATE := DATE '2030-01-15';
    v_ts2 TIMESTAMPTZ := TIMESTAMPTZ '2030-01-15 12:00:00-03';
    v_p   BIGINT;
    v_q   BIGINT;
    b1    NUMERIC; b2 NUMERIC; l1 INTEGER; l2 INTEGER;
    s0    TEXT;
    s1    TEXT;
    c1 BIGINT; c2 BIGINT; c3 BIGINT;
BEGIN
    SELECT categoria_id INTO c1 FROM producto WHERE id = 10;
    SELECT categoria_id INTO c2 FROM producto WHERE id = 11;
    SELECT categoria_id INTO c3 FROM producto WHERE id = 12;
    ASSERT c1 IS NOT NULL AND c1 <> c2 AND c2 <> c3 AND c1 <> c3 AND c1 = (SELECT categoria_id FROM producto WHERE id = 20),
           'precondicion: los productos 10/20 (misma categoria), 11 y 12 deben existir y ser de 3 categorias distintas';
    ASSERT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_vdc_pedido_detalle' AND NOT tgisinternal),
           'no existe el disparador trg_vdc_pedido_detalle';

    -- A) Alta de detalle: +100.00 exactos en su categoria; triangulacion con otra categoria y con un detalle ya eliminado
    BEGIN
        b1 := t4_vdc_total(v_hoy, c1); b2 := t4_vdc_total(v_hoy, c2); l1 := t4_vdc_lineas(v_hoy, c1);
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now(), 'EFECTIVO', 1) RETURNING id INTO v_p;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 10, 1, 100.00, 100.00);
        ASSERT t4_vdc_total(v_hoy, c1) = b1 + 100.00, 'A1: total cat 1 = ' || t4_vdc_total(v_hoy, c1) || ' esperado ' || (b1 + 100.00);
        ASSERT t4_vdc_lineas(v_hoy, c1) = l1 + 1, 'A1: lineas cat 1';
        ASSERT t4_vdc_total(v_hoy, c2) = b2, 'A1: cat 2 no debia cambiar';
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 11, 3, 13.50, 40.50);
        ASSERT t4_vdc_total(v_hoy, c2) = b2 + 40.50, 'A2: total cat 2 = ' || t4_vdc_total(v_hoy, c2);
        ASSERT t4_vdc_total(v_hoy, c1) = b1 + 100.00, 'A2: cat 1 no debia cambiar';
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal, eliminado) VALUES (v_p, 20, 1, 77.00, 77.00, TRUE);
        ASSERT t4_vdc_total(v_hoy, c1) = b1 + 100.00 AND t4_vdc_lineas(v_hoy, c1) = l1 + 1, 'A3: un detalle eliminado no suma';
        ASSERT (SELECT count(*) FROM v_auditoria_ventas_diarias) = 0, 'auditoria != 0 filas tras el escenario';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- B) Cambio de subtotal: 100.00 -> 250.00 = +150.00; luego 250.00 -> 90.00
    BEGIN
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now(), 'EFECTIVO', 1) RETURNING id INTO v_p;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 10, 1, 100.00, 100.00);
        b1 := t4_vdc_total(v_hoy, c1); l1 := t4_vdc_lineas(v_hoy, c1);
        UPDATE pedido_detalle SET subtotal = 250.00 WHERE pedido_id = v_p AND producto_id = 10;
        ASSERT t4_vdc_total(v_hoy, c1) = b1 + 150.00, 'B1: delta = ' || (t4_vdc_total(v_hoy, c1) - b1);
        UPDATE pedido_detalle SET subtotal = 90.00 WHERE pedido_id = v_p AND producto_id = 10;
        ASSERT t4_vdc_total(v_hoy, c1) = b1 - 10.00, 'B2: delta = ' || (t4_vdc_total(v_hoy, c1) - b1);
        ASSERT t4_vdc_lineas(v_hoy, c1) = l1, 'B: las lineas no cambian al modificar el subtotal';
        ASSERT (SELECT count(*) FROM v_auditoria_ventas_diarias) = 0, 'auditoria != 0 filas tras el escenario';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- C) Cambio de producto: entre categorias (1 -> 2 -> 3 -> 1) y dentro de la misma categoria (10 -> 20)
    BEGIN
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now(), 'EFECTIVO', 1) RETURNING id INTO v_p;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 10, 1, 100.00, 100.00);
        b1 := t4_vdc_total(v_hoy, c1); b2 := t4_vdc_total(v_hoy, c2); l1 := t4_vdc_lineas(v_hoy, c1); l2 := t4_vdc_lineas(v_hoy, c2);
        UPDATE pedido_detalle SET producto_id = 11 WHERE pedido_id = v_p AND producto_id = 10;
        ASSERT t4_vdc_total(v_hoy, c1) = b1 - 100.00 AND t4_vdc_lineas(v_hoy, c1) = l1 - 1, 'C1: cat 1 debia perder 100.00 y 1 linea';
        ASSERT t4_vdc_total(v_hoy, c2) = b2 + 100.00 AND t4_vdc_lineas(v_hoy, c2) = l2 + 1, 'C1: cat 2 debia ganar 100.00 y 1 linea';
        UPDATE pedido_detalle SET producto_id = 12 WHERE pedido_id = v_p AND producto_id = 11;
        ASSERT t4_vdc_total(v_hoy, c2) = b2 AND t4_vdc_lineas(v_hoy, c2) = l2, 'C2: cat 2 debia volver al valor inicial';
        UPDATE pedido_detalle SET producto_id = 10 WHERE pedido_id = v_p AND producto_id = 12;
        ASSERT t4_vdc_total(v_hoy, c1) = b1 AND t4_vdc_lineas(v_hoy, c1) = l1, 'C3: cat 1 debia volver al valor inicial';
        UPDATE pedido_detalle SET producto_id = 20 WHERE pedido_id = v_p AND producto_id = 10;  -- misma categoria
        ASSERT t4_vdc_total(v_hoy, c1) = b1 AND t4_vdc_lineas(v_hoy, c1) = l1, 'C4: mismo total dentro de la misma categoria';
        ASSERT (SELECT count(*) FROM v_auditoria_ventas_diarias) = 0, 'auditoria != 0 filas tras el escenario';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- D) Baja logica y reactivacion de un detalle (dos ciclos)
    BEGIN
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now(), 'EFECTIVO', 1) RETURNING id INTO v_p;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 10, 1, 100.00, 100.00);
        b1 := t4_vdc_total(v_hoy, c1); l1 := t4_vdc_lineas(v_hoy, c1);
        FOR i IN 1..2 LOOP
            UPDATE pedido_detalle SET eliminado = TRUE WHERE pedido_id = v_p AND producto_id = 10;
            ASSERT t4_vdc_total(v_hoy, c1) = b1 - 100.00 AND t4_vdc_lineas(v_hoy, c1) = l1 - 1, 'D: baja ciclo ' || i;
            UPDATE pedido_detalle SET eliminado = FALSE WHERE pedido_id = v_p AND producto_id = 10;
            ASSERT t4_vdc_total(v_hoy, c1) = b1 AND t4_vdc_lineas(v_hoy, c1) = l1, 'D: reactivacion ciclo ' || i;
        END LOOP;
        ASSERT (SELECT count(*) FROM v_auditoria_ventas_diarias) = 0, 'auditoria != 0 filas tras el escenario';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- E) Borrado fisico de un detalle no eliminado y de uno ya eliminado (este ultimo no debe restar nada)
    BEGIN
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now(), 'EFECTIVO', 1) RETURNING id INTO v_p;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 10, 1, 100.00, 100.00);
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal, eliminado) VALUES (v_p, 20, 1, 55.00, 55.00, TRUE);
        b1 := t4_vdc_total(v_hoy, c1); l1 := t4_vdc_lineas(v_hoy, c1);
        DELETE FROM pedido_detalle WHERE pedido_id = v_p AND producto_id = 20;
        ASSERT t4_vdc_total(v_hoy, c1) = b1 AND t4_vdc_lineas(v_hoy, c1) = l1, 'E1: borrar un detalle ya eliminado no resta';
        DELETE FROM pedido_detalle WHERE pedido_id = v_p AND producto_id = 10;
        ASSERT t4_vdc_total(v_hoy, c1) = b1 - 100.00 AND t4_vdc_lineas(v_hoy, c1) = l1 - 1, 'E2: el borrado debia restar 100.00';
        ASSERT (SELECT count(*) FROM v_auditoria_ventas_diarias) = 0, 'auditoria != 0 filas tras el escenario';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- F) La fila desaparece al quitar la ultima linea (dia lejano, sin ventas reales)
    BEGIN
        ASSERT NOT EXISTS (SELECT 1 FROM ventas_diarias_categoria WHERE fecha = v_d2), 'F0: el dia de prueba ya tenia filas';
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (v_ts2, 'EFECTIVO', 1) RETURNING id INTO v_p;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 10, 1, 100.00, 100.00);
        ASSERT t4_vdc_total(v_d2, c1) = 100.00 AND t4_vdc_lineas(v_d2, c1) = 1, 'F1: la fila debia crearse con 100.00 / 1';
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 20, 1, 30.00, 30.00);
        ASSERT t4_vdc_total(v_d2, c1) = 130.00 AND t4_vdc_lineas(v_d2, c1) = 2, 'F2: 130.00 / 2';
        DELETE FROM pedido_detalle WHERE pedido_id = v_p AND producto_id = 20;
        ASSERT t4_vdc_total(v_d2, c1) = 100.00 AND t4_vdc_lineas(v_d2, c1) = 1, 'F3: con una linea restante la fila sigue';
        UPDATE pedido_detalle SET eliminado = TRUE WHERE pedido_id = v_p AND producto_id = 10;  -- baja logica de la ultima
        ASSERT NOT EXISTS (SELECT 1 FROM ventas_diarias_categoria WHERE fecha = v_d2), 'F4: la fila debia desaparecer (baja logica)';
        UPDATE pedido_detalle SET eliminado = FALSE WHERE pedido_id = v_p AND producto_id = 10;
        DELETE FROM pedido_detalle WHERE pedido_id = v_p AND producto_id = 10;  -- borrado fisico de la ultima
        ASSERT NOT EXISTS (SELECT 1 FROM ventas_diarias_categoria WHERE fecha = v_d2), 'F5: la fila debia desaparecer (borrado)';
        ASSERT (SELECT count(*) FROM v_auditoria_ventas_diarias) = 0, 'auditoria != 0 filas tras el escenario';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- G) Cambio de pedido del detalle: hoy -> dia lejano (resta de uno, suma en otro)
    BEGIN
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now(), 'EFECTIVO', 1) RETURNING id INTO v_p;
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (v_ts2, 'EFECTIVO', 1) RETURNING id INTO v_q;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 10, 1, 100.00, 100.00);
        b1 := t4_vdc_total(v_hoy, c1); l1 := t4_vdc_lineas(v_hoy, c1);
        UPDATE pedido_detalle SET pedido_id = v_q WHERE pedido_id = v_p AND producto_id = 10;
        ASSERT t4_vdc_total(v_hoy, c1) = b1 - 100.00 AND t4_vdc_lineas(v_hoy, c1) = l1 - 1, 'G1: hoy debia perder 100.00';
        ASSERT t4_vdc_total(v_d2, c1) = 100.00 AND t4_vdc_lineas(v_d2, c1) = 1, 'G2: el dia lejano debia ganar 100.00';
        UPDATE pedido_detalle SET pedido_id = v_p WHERE pedido_id = v_q AND producto_id = 10;
        ASSERT t4_vdc_total(v_hoy, c1) = b1 AND NOT EXISTS (SELECT 1 FROM ventas_diarias_categoria WHERE fecha = v_d2), 'G3: vuelta atras';
        ASSERT (SELECT count(*) FROM v_auditoria_ventas_diarias) = 0, 'auditoria != 0 filas tras el escenario';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- H) Detalle agregado a un pedido eliminado no suma; y tampoco al darlo de baja logica despues
    BEGIN
        INSERT INTO pedido (fecha, forma_pago, cliente_id, eliminado) VALUES (now(), 'EFECTIVO', 1, TRUE) RETURNING id INTO v_p;
        b1 := t4_vdc_total(v_hoy, c1); l1 := t4_vdc_lineas(v_hoy, c1);
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 10, 1, 100.00, 100.00);
        ASSERT t4_vdc_total(v_hoy, c1) = b1 AND t4_vdc_lineas(v_hoy, c1) = l1, 'H1: detalle de pedido eliminado no suma';
        UPDATE pedido_detalle SET subtotal = 500.00 WHERE pedido_id = v_p AND producto_id = 10;
        UPDATE pedido_detalle SET eliminado = TRUE WHERE pedido_id = v_p AND producto_id = 10;
        DELETE FROM pedido_detalle WHERE pedido_id = v_p AND producto_id = 10;
        ASSERT t4_vdc_total(v_hoy, c1) = b1 AND t4_vdc_lineas(v_hoy, c1) = l1, 'H2: modificar/borrar el detalle de un pedido eliminado no resta';
        ASSERT (SELECT count(*) FROM v_auditoria_ventas_diarias) = 0, 'auditoria != 0 filas tras el escenario';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- I) Un ROLLBACK (aqui, ROLLBACK de subtransaccion) no deja residuos en la tabla
    SELECT count(*) || '/' || coalesce(sum(total_vendido), 0) || '/' || coalesce(sum(cantidad_lineas), 0) INTO s0
    FROM   ventas_diarias_categoria;
    BEGIN
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now(), 'EFECTIVO', 1) RETURNING id INTO v_p;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
        VALUES (v_p, 10, 1, 100.00, 100.00), (v_p, 11, 1, 50.00, 50.00), (v_p, 12, 2, 25.00, 50.00);
        SELECT count(*) || '/' || coalesce(sum(total_vendido), 0) || '/' || coalesce(sum(cantidad_lineas), 0) INTO s1 FROM ventas_diarias_categoria;
        ASSERT s1 <> s0, 'I0: las inserciones debian alterar la tabla dentro de la transaccion';
        ASSERT (SELECT count(*) FROM v_auditoria_ventas_diarias) = 0, 'auditoria != 0 filas tras el escenario';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;
    SELECT count(*) || '/' || coalesce(sum(total_vendido), 0) || '/' || coalesce(sum(cantidad_lineas), 0) INTO s1 FROM ventas_diarias_categoria;
    ASSERT s1 = s0, 'I1: residuos tras el rollback: antes ' || s0 || ' despues ' || s1;
    ASSERT (SELECT count(*) FROM v_auditoria_ventas_diarias) = 0, 'auditoria != 0 filas al finalizar el test';
END $$;

DROP FUNCTION t4_vdc_total(DATE, BIGINT);
DROP FUNCTION t4_vdc_lineas(DATE, BIGINT);
