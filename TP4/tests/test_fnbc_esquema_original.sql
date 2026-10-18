-- Test (Parte 1, tarea 2.x): esquema original control_lote_almacen con la instancia de la consigna.
-- Ejecutar: psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f TP4/tests/test_fnbc_esquema_original.sql
-- Un unico bloque DO; los intentos de violacion se aislan con subtransacciones (EXCEPTION).
DO $$
DECLARE
    v_filas   TEXT;
    v_rechazo BOOLEAN;
BEGIN
    -- 1) Instancia exacta
    SELECT string_agg(lote_id || ',' || deposito_id || ',' || responsable_control_id, ' | '
                      ORDER BY lote_id)
      INTO v_filas FROM control_lote_almacen;
    ASSERT v_filas = '501,30,801 | 502,30,801 | 503,31,802',
           'instancia inesperada: ' || coalesce(v_filas, 'NULL');

    -- 2) La PK (lote_id, deposito_id) rechaza (501,30,802)
    v_rechazo := FALSE;
    BEGIN
        INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id)
        VALUES (501, 30, 802);
    EXCEPTION WHEN unique_violation THEN v_rechazo := TRUE;
    END;
    ASSERT v_rechazo, 'la PK no rechazo (501,30,802)';

    -- 3) Triangulacion PK: otra combinacion duplicada (503,31) tambien se rechaza
    v_rechazo := FALSE;
    BEGIN
        INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id)
        VALUES (503, 31, 801);
    EXCEPTION WHEN unique_violation THEN v_rechazo := TRUE;
    END;
    ASSERT v_rechazo, 'la PK no rechazo (503,31,801)';

    -- 4) FK: lote inexistente
    v_rechazo := FALSE;
    BEGIN
        INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id)
        VALUES (999999, 30, 801);
    EXCEPTION WHEN foreign_key_violation THEN v_rechazo := TRUE;
    END;
    ASSERT v_rechazo, 'la FK no rechazo un lote inexistente';

    -- 5) Triangulacion FK: deposito y responsable inexistentes
    v_rechazo := FALSE;
    BEGIN
        INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id)
        VALUES (501, 999999, 801);
    EXCEPTION WHEN foreign_key_violation THEN v_rechazo := TRUE;
    END;
    ASSERT v_rechazo, 'la FK no rechazo un deposito inexistente';

    v_rechazo := FALSE;
    BEGIN
        INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id)
        VALUES (501, 31, 999999);
    EXCEPTION WHEN foreign_key_violation THEN v_rechazo := TRUE;
    END;
    ASSERT v_rechazo, 'la FK no rechazo un responsable inexistente';

    RAISE NOTICE 'OK test_fnbc_esquema_original';
END
$$
