-- Test (Parte 2, grupo 9): v_top5_categorias_dia equivale a la consulta normalizada (filas, orden y montos).
-- *** REQUIERE haber cargado Proyecto_Integrador/database/tp4_datos_prueba_top_categorias.sql (SOLO EN COPIA) ***
-- (supone ademas que la base se armo con generar_registros_adaptado.sql y SIN triggers.sql; ver el encabezado del archivo de datos de prueba)
-- Ejecutar: psql -v ON_ERROR_STOP=1 -d <base> -f Proyecto_Integrador/database/tests_tp4/test_reporte_top5.sql
-- Requiere la seccion 5 de Proyecto_Integrador/database/tp4_desnormalizacion_top_categorias.sql.
-- La parte que modifica datos se revierte con una excepcion centinela (SQLSTATE T4RB1).
DO $$
DECLARE
    v_n      BIGINT;
    v_p      BIGINT;
    v_sexta  TEXT;
    v_antes  TEXT;
BEGIN
    ASSERT to_regclass('v_top5_categorias_dia') IS NOT NULL, 'no existe v_top5_categorias_dia';

    -- 1) Mismo contenido y mismo orden (row_number) que la consulta normalizada embebida
    SELECT count(*) INTO v_n FROM (
        WITH normalizada AS (
            SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido
            FROM   pedido_detalle dp
            JOIN   pedido ped ON ped.id = dp.pedido_id JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id
            WHERE  fn_dia_negocio(ped.fecha) = fn_dia_negocio(now()) AND NOT ped.eliminado AND NOT dp.eliminado
            GROUP  BY c.nombre ORDER BY total_vendido DESC, c.nombre LIMIT 5),
        a AS (SELECT categoria, total_vendido, row_number() OVER (ORDER BY total_vendido DESC, categoria) AS pos FROM normalizada),
        b AS (SELECT categoria, total_vendido, row_number() OVER (ORDER BY total_vendido DESC, categoria) AS pos FROM v_top5_categorias_dia)
        SELECT * FROM (SELECT * FROM a EXCEPT SELECT * FROM b) x
        UNION ALL
        SELECT * FROM (SELECT * FROM b EXCEPT SELECT * FROM a) y) d;
    ASSERT v_n = 0, 'la vista difiere de la consulta normalizada en ' || v_n || ' filas';
    SELECT count(*) INTO v_n FROM v_top5_categorias_dia;
    ASSERT v_n = 5, 'la vista debe devolver 5 filas, devolvio ' || v_n;

    -- 2) Orden estrictamente descendente por monto
    SELECT count(*) INTO v_n FROM (
        SELECT total_vendido, lag(total_vendido) OVER (ORDER BY total_vendido DESC, categoria) AS prev FROM v_top5_categorias_dia) t
    WHERE  prev IS NOT NULL AND prev < total_vendido;
    ASSERT v_n = 0, 'el orden no es descendente';

    -- 3) Triangulacion: la categoria en 6.o puesto recibe una venta de ~1e8 (maximo de subtotal NUMERIC(10,2)) y entra al top 5; ambas consultas vuelven a coincidir
    SELECT c.nombre INTO v_sexta
    FROM   ventas_diarias_categoria v JOIN categoria c ON c.id = v.categoria_id
    WHERE  v.fecha = fn_dia_negocio(now())
    ORDER  BY v.total_vendido DESC, c.nombre OFFSET 5 LIMIT 1;
    ASSERT v_sexta IS NOT NULL, 'no hay categoria en 6.o puesto';
    SELECT string_agg(categoria, ',' ORDER BY total_vendido DESC, categoria) INTO v_antes FROM v_top5_categorias_dia;
    ASSERT position(v_sexta IN v_antes) = 0, 'la 6.a ya estaba en el top 5';
    BEGIN
        INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now(), 'EFECTIVO', 1) RETURNING id INTO v_p;
        INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
        SELECT v_p, pr.id, 1, 1, 99999999.99 FROM producto pr JOIN categoria c ON c.id = pr.categoria_id WHERE c.nombre = v_sexta ORDER BY pr.id LIMIT 1;
        SELECT string_agg(categoria, ',' ORDER BY total_vendido DESC, categoria) INTO v_antes FROM v_top5_categorias_dia;
        ASSERT position(v_sexta IN v_antes) > 0, 'la categoria ' || v_sexta || ' debia entrar al top 5: ' || v_antes;
        SELECT count(*) INTO v_n FROM (
            WITH normalizada AS (
                SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido
                FROM   pedido_detalle dp
                JOIN   pedido ped ON ped.id = dp.pedido_id JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id
                WHERE  fn_dia_negocio(ped.fecha) = fn_dia_negocio(now()) AND NOT ped.eliminado AND NOT dp.eliminado
                GROUP  BY c.nombre ORDER BY total_vendido DESC, c.nombre LIMIT 5),
            a AS (SELECT categoria, total_vendido, row_number() OVER (ORDER BY total_vendido DESC, categoria) AS pos FROM normalizada),
            b AS (SELECT categoria, total_vendido, row_number() OVER (ORDER BY total_vendido DESC, categoria) AS pos FROM v_top5_categorias_dia)
            SELECT * FROM (SELECT * FROM a EXCEPT SELECT * FROM b) x
            UNION ALL
            SELECT * FROM (SELECT * FROM b EXCEPT SELECT * FROM a) y) d;
        ASSERT v_n = 0, 'tras la venta enorme la vista difiere de la normalizada en ' || v_n || ' filas';
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'T4RB1';
    EXCEPTION WHEN SQLSTATE 'T4RB1' THEN NULL;
    END;
END $$;
