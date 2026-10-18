-- Test (Parte 2, grupo 8 - hallazgos del advisor): endurecimiento de concurrencia.
-- Ejecutar: psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f TP4/tests/test_concurrencia.sql
-- Un test de concurrencia real exige DOS sesiones simultaneas; el MCP `postgres` ejecuta una sentencia
-- por llamada y no puede mantener dos transacciones abiertas, por eso este test es ESTRUCTURAL
-- (verifica que los bloqueos estan declarados) y el escenario T1/T2 paso a paso se documenta en
-- el script (seccion 4), en design.md (decision 14) y en el informe (c). La prueba manual con dos
-- sesiones psql queda descrita en el informe.
DO $$
DECLARE
    v_def TEXT;
    v_n   BIGINT;
BEGIN
    -- 1) fn_vdc_linea toma bloqueos FOR SHARE sobre las filas de pedido y producto que lee,
    --    para que un UPDATE concurrente de pedido.eliminado/fecha o producto.categoria_id (FOR NO KEY UPDATE)
    --    espere hasta el commit de la transaccion que modifica el detalle.
    v_def := pg_get_functiondef('fn_vdc_linea(bigint,bigint,numeric,integer)'::regprocedure);
    ASSERT v_def ~* 'FOR SHARE OF p, pr', 'fn_vdc_linea no declara FOR SHARE OF p, pr';

    -- 2) TRUNCATE de pedido y pedido_detalle (no sincronizable por disparadores de fila) queda bloqueado
    SELECT count(*) INTO v_n FROM pg_trigger
    WHERE  tgname IN ('trg_vdc_truncate_pedido', 'trg_vdc_truncate_detalle') AND NOT tgisinternal AND (tgtype & 32) = 32;  -- TRUNCATE
    ASSERT v_n = 2, 'faltan los disparadores BEFORE TRUNCATE (hay ' || v_n || ')';

    BEGIN
        TRUNCATE pedido_detalle;
        RAISE EXCEPTION 'TRUNCATE pedido_detalle no fue bloqueado' USING ERRCODE = 'T4BAD';
    EXCEPTION WHEN feature_not_supported THEN NULL;
    END;
    BEGIN
        TRUNCATE pedido CASCADE;
        RAISE EXCEPTION 'TRUNCATE pedido no fue bloqueado' USING ERRCODE = 'T4BAD';
    EXCEPTION WHEN feature_not_supported THEN NULL;
    END;

    -- 3) la propia tabla de totales SI se puede truncar (lo hace la reconstruccion documentada)
    BEGIN
        TRUNCATE ventas_diarias_categoria;
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;
    SELECT count(*) INTO v_n FROM ventas_diarias_categoria;
    ASSERT v_n > 0, 'el rollback debia restaurar los totales';
END $$;
