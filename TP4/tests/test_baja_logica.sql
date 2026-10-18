-- Test (Parte 2, grupo 6): baja logica `eliminado` en pedido y pedido_detalle.
-- Ejecutar: psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f TP4/tests/test_baja_logica.sql
-- Requiere TP4/tp_desnormalizacion_top_categorias.sql (seccion 1). Es re-ejecutable tras la carga de
-- datos de prueba: se verifica que el historico previo a hoy quedo intacto (todo FALSE).
DO $$
DECLARE
    v_n BIGINT;
    t   TEXT;
    r   RECORD;
BEGIN
    FOREACH t IN ARRAY ARRAY['pedido', 'pedido_detalle'] LOOP
        -- 1) La columna existe, es BOOLEAN NOT NULL con default false
        SELECT data_type, is_nullable, column_default INTO r
        FROM   information_schema.columns
        WHERE  table_schema = 'public' AND table_name = t AND column_name = 'eliminado';
        ASSERT r.data_type IS NOT NULL, t || '.eliminado no existe';
        ASSERT r.data_type = 'boolean', t || '.eliminado no es boolean: ' || r.data_type;
        ASSERT r.is_nullable = 'NO', t || '.eliminado admite NULL';
        ASSERT r.column_default = 'false', t || '.eliminado default=' || coalesce(r.column_default, 'NULL');
    END LOOP;

    -- 2) El historico previo al dia de negocio actual no fue alterado (todo FALSE)
    SELECT count(*) INTO v_n FROM pedido WHERE eliminado AND fecha < (CURRENT_DATE - 1);
    ASSERT v_n = 0, 'pedidos historicos con eliminado=TRUE: ' || v_n;
    SELECT count(*) INTO v_n FROM pedido_detalle d JOIN pedido p ON p.id = d.pedido_id
    WHERE  d.eliminado AND p.fecha < (CURRENT_DATE - 1);
    ASSERT v_n = 0, 'detalles historicos con eliminado=TRUE: ' || v_n;

    -- 3) NULL rechazado por NOT NULL (en ambas tablas), con rollback por excepcion centinela
    BEGIN
        UPDATE pedido SET eliminado = NULL WHERE id = (SELECT min(id) FROM pedido);
        RAISE EXCEPTION 'debio fallar por NOT NULL (pedido)';
    EXCEPTION WHEN not_null_violation THEN NULL;
    END;
    BEGIN
        UPDATE pedido_detalle SET eliminado = NULL
        WHERE  (pedido_id, producto_id) = (SELECT pedido_id, producto_id FROM pedido_detalle LIMIT 1);
        RAISE EXCEPTION 'debio fallar por NOT NULL (pedido_detalle)';
    EXCEPTION WHEN not_null_violation THEN NULL;
    END;
END $$;
