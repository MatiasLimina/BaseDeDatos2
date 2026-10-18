-- Test (Parte 1, correccion AGENTS.md): CHECK, indices y baja logica (R7) en las tablas de la Parte 1.
-- Ejecutar: psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f TP4/tests/test_fnbc_restricciones_indices.sql
DO $$
DECLARE
    v_n       INT;
    v_rechazo BOOLEAN;
BEGIN
    -- 1) Al menos 3 CHECK entre lote, deposito y usuario
    SELECT count(*) INTO v_n FROM pg_constraint
    WHERE  contype = 'c'
      AND  conrelid IN ('lote'::regclass, 'deposito'::regclass, 'usuario'::regclass);
    ASSERT v_n >= 3, 'se esperaban >= 3 CHECK, hay ' || v_n;

    -- 2) Cada maestra tiene al menos un CHECK
    SELECT count(DISTINCT conrelid) INTO v_n FROM pg_constraint
    WHERE  contype = 'c'
      AND  conrelid IN ('lote'::regclass, 'deposito'::regclass, 'usuario'::regclass);
    ASSERT v_n = 3, 'lote, deposito y usuario deben tener CHECK; tablas con CHECK: ' || v_n;

    -- 3) R7: lote.activo BOOLEAN NOT NULL DEFAULT TRUE
    SELECT count(*) INTO v_n FROM information_schema.columns
    WHERE  table_name = 'lote' AND column_name = 'activo' AND data_type = 'boolean'
      AND  is_nullable = 'NO' AND column_default = 'true';
    ASSERT v_n = 1, 'lote.activo debe ser BOOLEAN NOT NULL DEFAULT TRUE';

    -- 4) Indices (>= 2): control_lote(responsable_control_id) y responsable_deposito(deposito_id)
    SELECT count(*) INTO v_n FROM pg_indexes
    WHERE  tablename = 'control_lote' AND indexdef LIKE '%(responsable_control_id)%';
    ASSERT v_n = 1, 'falta indice sobre control_lote(responsable_control_id)';
    SELECT count(*) INTO v_n FROM pg_indexes
    WHERE  tablename = 'responsable_deposito' AND indexdef LIKE '%(deposito_id)%';
    ASSERT v_n = 1, 'falta indice sobre responsable_deposito(deposito_id)';

    -- 5) Comportamiento de los CHECK (triangulacion en las tres maestras); se revierte todo
    BEGIN
        v_rechazo := FALSE;
        BEGIN INSERT INTO lote (codigo) VALUES ('   ');
        EXCEPTION WHEN check_violation THEN v_rechazo := TRUE; END;
        ASSERT v_rechazo, 'lote.codigo en blanco deberia violar el CHECK';
        v_rechazo := FALSE;
        BEGIN INSERT INTO deposito (nombre) VALUES ('');
        EXCEPTION WHEN check_violation THEN v_rechazo := TRUE; END;
        ASSERT v_rechazo, 'deposito.nombre vacio deberia violar el CHECK';
        v_rechazo := FALSE;
        BEGIN INSERT INTO usuario (nombre, apellido) VALUES ('Ana', ' ');
        EXCEPTION WHEN check_violation THEN v_rechazo := TRUE; END;
        ASSERT v_rechazo, 'usuario.apellido en blanco deberia violar el CHECK';
        -- caso valido: lote nuevo queda activo por defecto
        INSERT INTO lote (codigo) VALUES ('LOTE-TEST-CHK');
        SELECT count(*) INTO v_n FROM lote WHERE codigo = 'LOTE-TEST-CHK' AND activo;
        ASSERT v_n = 1, 'un lote nuevo debe quedar activo';
        RAISE EXCEPTION 'rollback del test' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    RAISE NOTICE 'OK test_fnbc_restricciones_indices';
END
$$;
