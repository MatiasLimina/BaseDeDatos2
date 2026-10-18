-- Test (Parte 2, grupo 8): la desnormalizacion se retira sin perder ni modificar la fuente.
-- Ejecutar: psql -v ON_ERROR_STOP=1 -d <base> -f Proyecto_Integrador/database/tests_tp4/test_reversibilidad.sql
-- Requiere la seccion 4 (y 5/6 si ya existen) de Proyecto_Integrador/database/tp4_desnormalizacion_top_categorias.sql.
-- El bloque de reversion es una COPIA del que figura (comentado) en la seccion 7 del script (no se puede
-- leer el archivo desde SQL sin privilegios de superusuario; si cambia uno hay que cambiar el otro). Aqui se
-- ejecuta dentro de un subbloque que termina con una excepcion centinela (T4RB1): al final todo
-- vuelve a existir, sin cambios.
DO $$
DECLARE
    v_top_antes   TEXT;
    v_top_despues TEXT;
    v_fuente_antes   TEXT;
    v_fuente_despues TEXT;
    v_n BIGINT;
    v_p BIGINT;
BEGIN
    ASSERT to_regclass('ventas_diarias_categoria') IS NOT NULL, 'precondicion: debe existir ventas_diarias_categoria';

    SELECT string_agg(categoria || '=' || total_vendido, ',' ORDER BY total_vendido DESC, categoria) INTO v_top_antes FROM (
        SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido
        FROM   pedido_detalle dp
        JOIN   pedido ped ON ped.id = dp.pedido_id JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id
        WHERE  fn_dia_negocio(ped.fecha) = fn_dia_negocio(now()) AND NOT ped.eliminado AND NOT dp.eliminado
        GROUP  BY c.nombre ORDER BY total_vendido DESC, c.nombre LIMIT 5) t;
    SELECT (SELECT count(*) FROM pedido) || '/' || (SELECT count(*) FROM pedido_detalle) || '/' || (SELECT count(*) FROM producto) || '/' || (SELECT count(*) FROM categoria)
           || '/' || (SELECT sum(subtotal) FROM pedido_detalle) || '/' || (SELECT sum(categoria_id) FROM producto) INTO v_fuente_antes;

    BEGIN
        -- ===== bloque de reversion (identico al de la seccion 7 del script) =====
        DROP VIEW IF EXISTS v_top5_categorias_dia;
        DROP VIEW IF EXISTS v_auditoria_ventas_diarias;
        DROP TRIGGER IF EXISTS trg_vdc_pedido_detalle ON pedido_detalle;
        DROP TRIGGER IF EXISTS trg_vdc_pedido         ON pedido;
        DROP TRIGGER IF EXISTS trg_vdc_producto       ON producto;
        DROP TRIGGER IF EXISTS trg_vdc_truncate_pedido  ON pedido;
        DROP TRIGGER IF EXISTS trg_vdc_truncate_detalle ON pedido_detalle;
        DROP FUNCTION IF EXISTS fn_vdc_trg_detalle();
        DROP FUNCTION IF EXISTS fn_vdc_trg_pedido();
        DROP FUNCTION IF EXISTS fn_vdc_trg_producto();
        DROP FUNCTION IF EXISTS fn_vdc_bloquear_truncate();
        DROP FUNCTION IF EXISTS fn_vdc_linea(BIGINT, BIGINT, NUMERIC, INTEGER);
        DROP FUNCTION IF EXISTS fn_vdc_pedido_aplicar(BIGINT, TIMESTAMPTZ, INTEGER);
        DROP FUNCTION IF EXISTS fn_vdc_aplicar(DATE, BIGINT, NUMERIC, INTEGER);
        DROP TABLE    IF EXISTS ventas_diarias_categoria;
        -- ===== fin del bloque =====

        -- no queda ningun objeto de sincronizacion
        SELECT count(*) INTO v_n FROM pg_trigger WHERE tgname LIKE 'trg\_vdc\_%' AND NOT tgisinternal;
        ASSERT v_n = 0, 'quedan disparadores trg_vdc_%: ' || v_n;
        SELECT count(*) INTO v_n FROM pg_proc WHERE proname LIKE 'fn\_vdc\_%';
        ASSERT v_n = 0, 'quedan funciones fn_vdc_%: ' || v_n;
        ASSERT to_regclass('ventas_diarias_categoria') IS NULL, 'la tabla no fue eliminada';

        -- la consulta normalizada da el mismo resultado y la fuente esta intacta
        SELECT string_agg(categoria || '=' || total_vendido, ',' ORDER BY total_vendido DESC, categoria) INTO v_top_despues FROM (
            SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido
            FROM   pedido_detalle dp
            JOIN   pedido ped ON ped.id = dp.pedido_id JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id
            WHERE  fn_dia_negocio(ped.fecha) = fn_dia_negocio(now()) AND NOT ped.eliminado AND NOT dp.eliminado
            GROUP  BY c.nombre ORDER BY total_vendido DESC, c.nombre LIMIT 5) t;
        ASSERT v_top_despues = v_top_antes, 'el top 5 normalizado cambio: ' || v_top_antes || ' vs ' || v_top_despues;
        SELECT (SELECT count(*) FROM pedido) || '/' || (SELECT count(*) FROM pedido_detalle) || '/' || (SELECT count(*) FROM producto) || '/' || (SELECT count(*) FROM categoria)
               || '/' || (SELECT sum(subtotal) FROM pedido_detalle) || '/' || (SELECT sum(categoria_id) FROM producto) INTO v_fuente_despues;
        ASSERT v_fuente_despues = v_fuente_antes, 'la fuente cambio: ' || v_fuente_antes || ' vs ' || v_fuente_despues;

        -- triangulacion: sin disparadores se puede escribir en la fuente sin error (y la escritura no deja efectos colaterales)
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now(), 'EFECTIVO', 1) RETURNING id INTO v_p;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (v_p, 10, 1, 10.00, 10.00);
        UPDATE pedido SET eliminado = TRUE WHERE id = v_p;
        UPDATE producto SET categoria_id = categoria_id WHERE id = 10;

        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;

    -- tras el rollback del subbloque todo vuelve a existir
    ASSERT to_regclass('ventas_diarias_categoria') IS NOT NULL, 'el rollback no restauro la tabla';
    SELECT count(*) INTO v_n FROM pg_trigger WHERE tgname LIKE 'trg\_vdc\_%' AND NOT tgisinternal;
    ASSERT v_n = 5, 'tras el rollback debian existir 5 disparadores, hay ' || v_n;
END $$;
