-- Test (Parte 1, grupo 4): descomposicion en FNBC.
-- Ejecutar: psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f TP4/tests/test_fnbc_descomposicion.sql
-- Funciona antes y despues de la migracion (seccion 3): los datos de apoyo se insertan con
-- ON CONFLICT DO NOTHING y todo el bloque se revierte con una excepcion centinela (SQLSTATE T4RB1).
DO $$
DECLARE
    v_rechazo BOOLEAN;
    v_n       INT;
BEGIN
    -- 1) Estructura: PK de responsable_deposito = (responsable_control_id)
    SELECT count(*) INTO v_n
    FROM   pg_constraint c
    WHERE  c.conrelid = 'responsable_deposito'::regclass AND c.contype = 'p'
      AND  (SELECT array_agg(a.attname::text ORDER BY a.attname)
            FROM pg_attribute a WHERE a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey))
           = ARRAY['responsable_control_id'];
    ASSERT v_n = 1, 'PK de responsable_deposito debe ser (responsable_control_id)';

    -- 2) PK de control_lote = (lote_id, responsable_control_id)
    SELECT count(*) INTO v_n
    FROM   pg_constraint c
    WHERE  c.conrelid = 'control_lote'::regclass AND c.contype = 'p'
      AND  (SELECT array_agg(a.attname::text ORDER BY a.attname)
            FROM pg_attribute a WHERE a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey))
           = ARRAY['lote_id', 'responsable_control_id'];
    ASSERT v_n = 1, 'PK de control_lote debe ser (lote_id, responsable_control_id)';

    -- 3) Exactamente 2 FKs por tabla, todas ON DELETE RESTRICT (confdeltype = 'r')
    SELECT count(*) INTO v_n FROM pg_constraint
    WHERE  conrelid = 'responsable_deposito'::regclass AND contype = 'f' AND confdeltype = 'r';
    ASSERT v_n = 2, 'responsable_deposito debe tener 2 FK RESTRICT, hay ' || v_n;
    SELECT count(*) INTO v_n FROM pg_constraint
    WHERE  conrelid = 'control_lote'::regclass AND contype = 'f' AND confdeltype = 'r';
    ASSERT v_n = 2, 'control_lote debe tener 2 FK RESTRICT, hay ' || v_n;
    SELECT count(*) INTO v_n FROM pg_constraint
    WHERE  conrelid IN ('responsable_deposito'::regclass, 'control_lote'::regclass)
      AND  contype = 'f' AND confdeltype <> 'r';
    ASSERT v_n = 0, 'hay FKs que no son RESTRICT';

    -- 4) FK de control_lote -> responsable_deposito (no a usuario)
    SELECT count(*) INTO v_n FROM pg_constraint
    WHERE  conrelid = 'control_lote'::regclass AND contype = 'f'
      AND  confrelid = 'responsable_deposito'::regclass;
    ASSERT v_n = 1, 'control_lote debe referenciar a responsable_deposito';

    BEGIN
        -- Datos de apoyo (idempotentes frente a la migracion)
        INSERT INTO responsable_deposito (responsable_control_id, deposito_id)
        VALUES (801, 30), (802, 31) ON CONFLICT DO NOTHING;
        INSERT INTO control_lote (lote_id, responsable_control_id)
        VALUES (501, 801), (502, 801), (503, 802) ON CONFLICT DO NOTHING;
        INSERT INTO usuario (id, nombre, apellido) OVERRIDING SYSTEM VALUE
        VALUES (803, 'Responsable', 'Ochocientos Tres');

        -- 5) Un responsable pertenece a un unico deposito: 801 -> 31 rechazado por PK
        v_rechazo := FALSE;
        BEGIN
            INSERT INTO responsable_deposito (responsable_control_id, deposito_id) VALUES (801, 31);
        EXCEPTION WHEN unique_violation THEN v_rechazo := TRUE;
        END;
        ASSERT v_rechazo, '801 en deposito 31 deberia violar la PK';
        -- Triangulacion: 802 -> 30 tambien
        v_rechazo := FALSE;
        BEGIN
            INSERT INTO responsable_deposito (responsable_control_id, deposito_id) VALUES (802, 30);
        EXCEPTION WHEN unique_violation THEN v_rechazo := TRUE;
        END;
        ASSERT v_rechazo, '802 en deposito 30 deberia violar la PK';

        -- 6) control_lote exige responsable con deposito asignado (FK a responsable_deposito)
        v_rechazo := FALSE;
        BEGIN  -- 803 existe en usuario pero NO en responsable_deposito
            INSERT INTO control_lote (lote_id, responsable_control_id) VALUES (501, 803);
        EXCEPTION WHEN foreign_key_violation THEN v_rechazo := TRUE;
        END;
        ASSERT v_rechazo, 'control_lote con responsable sin deposito deberia violar la FK';
        v_rechazo := FALSE;
        BEGIN
            INSERT INTO control_lote (lote_id, responsable_control_id) VALUES (501, 999999);
        EXCEPTION WHEN foreign_key_violation THEN v_rechazo := TRUE;
        END;
        ASSERT v_rechazo, 'control_lote con responsable inexistente deberia violar la FK';

        -- 7) RESTRICT (PostgreSQL lo informa como restrict_violation 23001, no 23503): no se puede borrar un deposito, lote ni usuario referenciados
        v_rechazo := FALSE;
        BEGIN
            DELETE FROM deposito WHERE id = 30;
        EXCEPTION WHEN restrict_violation OR foreign_key_violation THEN v_rechazo := TRUE;
        END;
        ASSERT v_rechazo, 'borrar un deposito referenciado deberia ser rechazado (RESTRICT)';
        v_rechazo := FALSE;
        BEGIN
            DELETE FROM lote WHERE id = 501;
        EXCEPTION WHEN restrict_violation OR foreign_key_violation THEN v_rechazo := TRUE;
        END;
        ASSERT v_rechazo, 'borrar un lote con controles deberia ser rechazado (RESTRICT)';
        v_rechazo := FALSE;
        BEGIN
            DELETE FROM usuario WHERE id = 801;
        EXCEPTION WHEN restrict_violation OR foreign_key_violation THEN v_rechazo := TRUE;
        END;
        ASSERT v_rechazo, 'borrar un usuario referenciado deberia ser rechazado (RESTRICT)';
        v_rechazo := FALSE;
        BEGIN  -- tambien el responsable_deposito referenciado por control_lote
            DELETE FROM responsable_deposito WHERE responsable_control_id = 801;
        EXCEPTION WHEN restrict_violation OR foreign_key_violation THEN v_rechazo := TRUE;
        END;
        ASSERT v_rechazo, 'borrar un responsable_deposito con controles deberia ser rechazado (RESTRICT)';

        RAISE EXCEPTION 'rollback del test' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN
        NULL;  -- se revierte todo lo insertado por el test
    END;

    RAISE NOTICE 'OK test_fnbc_descomposicion';
END
$$;
