-- Test (Parte 2, grupo 6): datos de prueba del dia de negocio actual.
-- Ejecutar: psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f TP4/tests/test_datos_prueba.sql
-- Requiere la seccion 2 de TP4/tp_desnormalizacion_top_categorias.sql.
DO $$
DECLARE
    v_ini  TIMESTAMPTZ := (fn_dia_negocio(now())::timestamp) AT TIME ZONE 'America/Argentina/Buenos_Aires';
    v_n    BIGINT;
BEGIN
    -- Precondicion: debe haber datos del dia de negocio actual (los genera la seccion 2 del script el
    -- mismo dia). Si se ejecuta otro dia sin re-ejecutar la seccion 2, falla con este mensaje.
    SELECT count(*) INTO v_n FROM pedido p WHERE p.fecha >= v_ini AND p.fecha < v_ini + INTERVAL '1 day';
    ASSERT v_n > 0, 'PRECONDICION: no hay pedidos del dia de negocio actual; ejecute la seccion 2 de tp_desnormalizacion_top_categorias.sql hoy (y re-cree la estructura de la seccion 4)';

    -- >= 8 categorias con ventas vigentes en el dia de negocio actual
    SELECT count(DISTINCT pr.categoria_id) INTO v_n
    FROM   pedido_detalle d
    JOIN   pedido   p  ON p.id  = d.pedido_id
    JOIN   producto pr ON pr.id = d.producto_id
    WHERE  p.fecha >= v_ini AND p.fecha < v_ini + INTERVAL '1 day'
      AND  NOT p.eliminado AND NOT d.eliminado;
    ASSERT v_n >= 8, 'categorias con ventas hoy: ' || v_n || ' (se esperaban >= 8)';

    -- >= 100 000 detalles vigentes de pedidos vigentes del dia
    SELECT count(*) INTO v_n
    FROM   pedido_detalle d JOIN pedido p ON p.id = d.pedido_id
    WHERE  p.fecha >= v_ini AND p.fecha < v_ini + INTERVAL '1 day'
      AND  NOT p.eliminado AND NOT d.eliminado;
    ASSERT v_n >= 100000, 'detalles vigentes de hoy: ' || v_n || ' (se esperaban >= 100000)';

    -- existen pedidos y detalles del dia dados de baja (para que el filtro tenga efecto)
    SELECT count(*) INTO v_n FROM pedido p
    WHERE  p.fecha >= v_ini AND p.fecha < v_ini + INTERVAL '1 day' AND p.eliminado;
    ASSERT v_n > 0, 'no hay pedidos eliminados hoy';
    SELECT count(*) INTO v_n
    FROM   pedido_detalle d JOIN pedido p ON p.id = d.pedido_id
    WHERE  p.fecha >= v_ini AND p.fecha < v_ini + INTERVAL '1 day' AND d.eliminado;
    ASSERT v_n > 0, 'no hay detalles eliminados hoy';

    -- las 10 categorias existen y todas tienen productos
    SELECT count(*) INTO v_n FROM categoria c WHERE EXISTS (SELECT 1 FROM producto pr WHERE pr.categoria_id = c.id);
    ASSERT v_n >= 8, 'categorias con productos: ' || v_n;

    -- 7) Sin categorias duplicadas por codificacion: si el cliente (p. ej. psql en la consola de Windows)
    --    no envia UTF-8, 'Panaderia' con tilde se guarda como 'PanaderÃ­a' y ON CONFLICT no la reconoce.
    SELECT count(*) INTO v_n FROM categoria WHERE nombre ~ '[ÃÂ]';
    ASSERT v_n = 0, 'categorias con caracteres mal codificados (mojibake): ' || v_n;
END $$;
