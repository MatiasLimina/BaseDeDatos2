-- Test (Parte 2, grupo 10): v_auditoria_ventas_diarias detecta toda desincronizacion.
-- Ejecutar: psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f TP4/tests/test_auditoria.sql
-- Requiere la seccion 6 de TP4/tp_desnormalizacion_top_categorias.sql. Las alteraciones manuales se
-- hacen dentro de subbloques que terminan con una excepcion centinela (SQLSTATE T4RB1).
DO $$
DECLARE
    v_n     BIGINT;
    v_hoy   DATE := fn_dia_negocio(now());
    v_fecha DATE;
    v_cat   BIGINT;
    r       RECORD;
BEGIN
    ASSERT to_regclass('v_auditoria_ventas_diarias') IS NOT NULL, 'no existe v_auditoria_ventas_diarias';

    -- 1) Base sincronizada: 0 filas
    SELECT count(*) INTO v_n FROM v_auditoria_ventas_diarias;
    ASSERT v_n = 0, 'la auditoria devolvio ' || v_n || ' filas en una base sincronizada';

    -- 2) Total alterado a mano: la auditoria devuelve exactamente esa fila
    BEGIN
        UPDATE ventas_diarias_categoria SET total_vendido = total_vendido + 1.00 WHERE fecha = v_hoy AND categoria_id = 3;
        SELECT count(*) INTO v_n FROM v_auditoria_ventas_diarias;
        ASSERT v_n = 1, '2a: se esperaba 1 fila y hay ' || v_n;
        SELECT * INTO r FROM v_auditoria_ventas_diarias;
        ASSERT r.fecha = v_hoy AND r.categoria_id = 3, '2b: fila equivocada: ' || r.fecha || ' / ' || r.categoria_id;
        ASSERT r.total_tabla = r.total_fuente + 1.00, '2c: la diferencia debia ser 1.00';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- 3) Cantidad de lineas alterada (el total coincide): tambien se detecta
    BEGIN
        UPDATE ventas_diarias_categoria SET cantidad_lineas = cantidad_lineas + 1 WHERE fecha = v_hoy AND categoria_id = 4;
        SELECT count(*) INTO v_n FROM v_auditoria_ventas_diarias;
        ASSERT v_n = 1, '3: se esperaba 1 fila y hay ' || v_n;
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- 4) Fila borrada a mano (falta en la tabla redundante)
    BEGIN
        DELETE FROM ventas_diarias_categoria WHERE fecha = v_hoy AND categoria_id = 5;
        SELECT count(*) INTO v_n FROM v_auditoria_ventas_diarias;
        ASSERT v_n = 1, '4a: se esperaba 1 fila y hay ' || v_n;
        SELECT * INTO r FROM v_auditoria_ventas_diarias;
        ASSERT r.fecha = v_hoy AND r.categoria_id = 5 AND r.total_tabla IS NULL AND r.total_fuente IS NOT NULL, '4b: debia faltar en la tabla';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- 5) Fila de mas (sobra en la tabla redundante, sin respaldo en la fuente)
    BEGIN
        INSERT INTO ventas_diarias_categoria (fecha, categoria_id, total_vendido, cantidad_lineas) VALUES (DATE '2031-02-02', 1, 10.00, 1);
        SELECT count(*) INTO v_n FROM v_auditoria_ventas_diarias;
        ASSERT v_n = 1, '5a: se esperaba 1 fila y hay ' || v_n;
        SELECT * INTO r FROM v_auditoria_ventas_diarias;
        ASSERT r.fecha = DATE '2031-02-02' AND r.total_fuente IS NULL AND r.total_tabla = 10.00, '5b: debia sobrar en la tabla';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- 6) Desincronizacion real de la fuente: con el disparador deshabilitado, un cambio queda sin reflejar
    BEGIN
        ALTER TABLE pedido_detalle DISABLE TRIGGER trg_vdc_pedido_detalle;
        UPDATE pedido_detalle SET subtotal = subtotal + 5.00
        WHERE  (pedido_id, producto_id) = (SELECT d.pedido_id, d.producto_id FROM pedido_detalle d JOIN pedido p ON p.id = d.pedido_id
                                           WHERE NOT d.eliminado AND NOT p.eliminado AND p.id > 250000 LIMIT 1);
        SELECT count(*) INTO v_n FROM v_auditoria_ventas_diarias;
        ASSERT v_n = 1, '6: la desincronizacion de la fuente debia detectarse (filas: ' || v_n || ')';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;
    ASSERT (SELECT tgenabled FROM pg_trigger WHERE tgname = 'trg_vdc_pedido_detalle') = 'O', '6: el rollback debia dejar el disparador habilitado';

    -- 7) Tras todas las alteraciones revertidas, vuelve a dar 0
    SELECT count(*) INTO v_n FROM v_auditoria_ventas_diarias;
    ASSERT v_n = 0, '7: la auditoria debia volver a 0 filas, devolvio ' || v_n;
END $$;
