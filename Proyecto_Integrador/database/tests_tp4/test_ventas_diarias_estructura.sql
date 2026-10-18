-- Test (Parte 2, grupo 8): estructura de ventas_diarias_categoria y carga inicial.
-- *** REQUIERE haber cargado Proyecto_Integrador/database/tp4_datos_prueba_top_categorias.sql (SOLO EN COPIA) ***
-- Ejecutar: psql -v ON_ERROR_STOP=1 -d <base> -f Proyecto_Integrador/database/tests_tp4/test_ventas_diarias_estructura.sql
-- Requiere la seccion 4 de Proyecto_Integrador/database/tp4_desnormalizacion_top_categorias.sql.
DO $$
DECLARE
    v_n    BIGINT;
    v_n2   BIGINT;
    v_cols TEXT;
    v_hoy  DATE := fn_dia_negocio(now());
BEGIN
    ASSERT to_regclass('ventas_diarias_categoria') IS NOT NULL, 'no existe ventas_diarias_categoria';

    -- PK (fecha, categoria_id)
    SELECT string_agg(a.attname, ',' ORDER BY k.ord) INTO v_cols
    FROM   pg_constraint c
    CROSS  JOIN LATERAL unnest(c.conkey) WITH ORDINALITY k(attnum, ord)
    JOIN   pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
    WHERE  c.conrelid = 'ventas_diarias_categoria'::regclass AND c.contype = 'p';
    ASSERT v_cols = 'fecha,categoria_id', 'PK = ' || coalesce(v_cols, 'NULL');

    -- FK a categoria con RESTRICT
    SELECT count(*) INTO v_n FROM pg_constraint
    WHERE  conrelid = 'ventas_diarias_categoria'::regclass AND contype = 'f'
      AND  confrelid = 'categoria'::regclass AND confdeltype = 'r';
    ASSERT v_n = 1, 'falta la FK RESTRICT hacia categoria';

    -- Dos CHECK (total_vendido >= 0, cantidad_lineas >= 0)
    SELECT count(*) INTO v_n FROM pg_constraint
    WHERE  conrelid = 'ventas_diarias_categoria'::regclass AND contype = 'c'
      AND (pg_get_constraintdef(oid) ILIKE '%total_vendido >= %' OR pg_get_constraintdef(oid) ILIKE '%cantidad_lineas >= %');
    ASSERT v_n = 2, 'CHECKs encontrados: ' || v_n;

    -- Los CHECK y la FK rechazan datos invalidos (cada intento se revierte)
    BEGIN
        INSERT INTO ventas_diarias_categoria (fecha, categoria_id, total_vendido, cantidad_lineas)
        VALUES (DATE '2031-01-01', 1, -1, 1);
        RAISE EXCEPTION 'debio rechazar total negativo';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO ventas_diarias_categoria (fecha, categoria_id, total_vendido, cantidad_lineas)
        VALUES (DATE '2031-01-01', 1, 1, -1);
        RAISE EXCEPTION 'debio rechazar lineas negativas';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO ventas_diarias_categoria (fecha, categoria_id, total_vendido, cantidad_lineas)
        VALUES (DATE '2031-01-01', 999999, 1, 1);
        RAISE EXCEPTION 'debio rechazar categoria inexistente';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    -- Carga inicial: diferencias contra la fuente (FULL OUTER JOIN) = 0, y hay filas para hoy
    SELECT count(*) INTO v_n FROM (
        SELECT fn_dia_negocio(p.fecha) AS fecha, pr.categoria_id, SUM(d.subtotal) AS total, COUNT(*) AS lineas
        FROM   pedido_detalle d
        JOIN   pedido p ON p.id = d.pedido_id JOIN producto pr ON pr.id = d.producto_id
        WHERE  NOT p.eliminado AND NOT d.eliminado
        GROUP  BY 1, 2) f
    FULL OUTER JOIN ventas_diarias_categoria v ON v.fecha = f.fecha AND v.categoria_id = f.categoria_id
    WHERE  f.total IS DISTINCT FROM v.total_vendido OR f.lineas IS DISTINCT FROM v.cantidad_lineas;
    ASSERT v_n = 0, 'diferencias entre fuente y tabla tras la carga inicial: ' || v_n;

    -- Las filas de hoy deben coincidir con las categorias con ventas vigentes hoy en la fuente (>= 1: si no hay
    -- datos del dia, ejecute tp4_datos_prueba_top_categorias.sql hoy y re-cree la estructura de la seccion 4).
    SELECT count(DISTINCT pr.categoria_id) INTO v_n2
    FROM   pedido_detalle d JOIN pedido p ON p.id = d.pedido_id JOIN producto pr ON pr.id = d.producto_id
    WHERE  NOT p.eliminado AND NOT d.eliminado AND fn_dia_negocio(p.fecha) = v_hoy;
    ASSERT v_n2 > 0, 'PRECONDICION: no hay ventas del dia de negocio actual; ejecute tp4_datos_prueba_top_categorias.sql hoy y re-cree la estructura (seccion 4)';
    SELECT count(*) INTO v_n FROM ventas_diarias_categoria WHERE fecha = v_hoy;
    ASSERT v_n = v_n2, 'filas de hoy: ' || v_n || ' (la fuente tiene ' || v_n2 || ' categorias con ventas)';
    -- la tabla no guarda filas vacias
    SELECT count(*) INTO v_n FROM ventas_diarias_categoria WHERE cantidad_lineas = 0;
    ASSERT v_n = 0, 'hay filas con 0 lineas: ' || v_n;
END $$;
