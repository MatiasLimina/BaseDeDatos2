-- Test (Parte 1, grupo 5): vista de compatibilidad, migracion verificada y DF no preservada.
-- Ejecutar: psql -v ON_ERROR_STOP=1 -d <base> -f Proyecto_Integrador/database/tests_tp4/test_fnbc_vista_migracion.sql
-- Requiere haber ejecutado Proyecto_Integrador/database/tp4_fnbc_control_lote.sql. Las partes que modifican datos se
-- revierten con una excepcion centinela (SQLSTATE T4RB1).
DO $$
DECLARE
    v_n   INT;
    v_n2  INT;
    v_txt TEXT;
BEGIN
    -- 1) La vista existe
    ASSERT to_regclass('v_control_lote_almacen') IS NOT NULL, 'no existe v_control_lote_almacen';

    -- 2) Equivalencia con la tabla original: EXCEPT en ambos sentidos = 0 filas
    SELECT count(*) INTO v_n FROM (
        SELECT lote_id, deposito_id, responsable_control_id FROM control_lote_almacen
        EXCEPT
        SELECT lote_id, deposito_id, responsable_control_id FROM v_control_lote_almacen) x;
    ASSERT v_n = 0, 'tabla EXCEPT vista devuelve ' || v_n || ' filas';
    SELECT count(*) INTO v_n FROM (
        SELECT lote_id, deposito_id, responsable_control_id FROM v_control_lote_almacen
        EXCEPT
        SELECT lote_id, deposito_id, responsable_control_id FROM control_lote_almacen) x;
    ASSERT v_n = 0, 'vista EXCEPT tabla devuelve ' || v_n || ' filas';

    -- 3) Misma cantidad de filas (3) en ambas
    SELECT count(*) INTO v_n  FROM control_lote_almacen;
    SELECT count(*) INTO v_n2 FROM v_control_lote_almacen;
    ASSERT v_n = 3 AND v_n2 = 3, 'conteos: tabla=' || v_n || ' vista=' || v_n2;

    -- 4) Migracion sin duplicar el hecho: 2 responsables, 3 controles
    SELECT count(*) INTO v_n  FROM responsable_deposito;
    SELECT count(*) INTO v_n2 FROM control_lote;
    ASSERT v_n = 2 AND v_n2 = 3, 'migracion: rd=' || v_n || ' cl=' || v_n2;

    -- 5) Cambio de deposito de 801 en UN solo lugar; la vista lo refleja en 501 y 502
    BEGIN
        UPDATE responsable_deposito SET deposito_id = 31 WHERE responsable_control_id = 801;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        ASSERT v_n = 1, 'el traslado debia modificar 1 fila, modifico ' || v_n;
        SELECT string_agg(lote_id || ':' || deposito_id, ',' ORDER BY lote_id) INTO v_txt
        FROM   v_control_lote_almacen WHERE responsable_control_id = 801;
        ASSERT v_txt = '501:31,502:31', 'la vista no refleja el traslado: ' || coalesce(v_txt, 'NULL');
        -- Triangulacion: el control del lote 503 (responsable 802) no cambia
        SELECT deposito_id INTO v_n FROM v_control_lote_almacen WHERE lote_id = 503;
        ASSERT v_n = 31, 'el lote 503 debia seguir en 31';
        RAISE EXCEPTION 'rollback del test' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;
    -- tras el rollback, el deposito de 801 vuelve a ser 30
    SELECT deposito_id INTO v_n FROM responsable_deposito WHERE responsable_control_id = 801;
    ASSERT v_n = 30, 'el rollback no restauro el deposito de 801';

    -- 6) DF {Lote, Deposito} -> Responsable NO preservada: el esquema descompuesto acepta un
    --    segundo responsable del deposito 30 para el lote 501 y la vista muestra dos filas.
    BEGIN
        INSERT INTO usuario (id, nombre, apellido) OVERRIDING SYSTEM VALUE
        VALUES (900803, 'Responsable', 'Ochocientos Tres');
        INSERT INTO responsable_deposito (responsable_control_id, deposito_id) VALUES (900803, 30);
        INSERT INTO control_lote (lote_id, responsable_control_id) VALUES (501, 900803);  -- aceptado
        SELECT count(*), count(DISTINCT responsable_control_id) INTO v_n, v_n2
        FROM   v_control_lote_almacen WHERE lote_id = 501 AND deposito_id = 30;
        ASSERT v_n = 2 AND v_n2 = 2,
               'la vista debia mostrar 2 responsables para (501,30): filas=' || v_n || ' distintos=' || v_n2;
        -- Triangulacion: la tabla ORIGINAL si lo rechaza (PK (lote, deposito))
        BEGIN
            INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id) VALUES (501, 30, 900803);
            ASSERT FALSE, 'la tabla original debia rechazar el duplicado (501,30)';
        EXCEPTION WHEN unique_violation THEN NULL;
        END;
        RAISE EXCEPTION 'rollback del test' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;
    SELECT count(*) INTO v_n FROM v_control_lote_almacen;
    ASSERT v_n = 3, 'el rollback no dejo la vista con 3 filas';

    RAISE NOTICE 'OK test_fnbc_vista_migracion';
END
$$;
