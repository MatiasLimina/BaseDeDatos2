-- =============================================================================
-- TP4 - Parte 2: Desnormalizacion controlada - top 5 de categorias del dia
-- Proyecto : Food Store - Base de Datos II
-- Motor    : PostgreSQL 18
-- Base     : tp4_foodstore (NUNCA food_store ni food_store_copia)
-- Ejecucion: psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f TP4/tp_desnormalizacion_top_categorias.sql
-- El script es idempotente: puede ejecutarse varias veces sobre la misma base.
-- Contenido:
--   Seccion 1: baja logica `eliminado` y funcion de dia de negocio
--   Seccion 2: datos de prueba (SOLO EN COPIA; ver advertencia)
--   Seccion 3: consulta original (baseline, normalizada)
--   Seccion 4: tabla ventas_diarias_categoria + disparadores + carga inicial
--   Seccion 5: consulta desnormalizada + vista del reporte
--   Seccion 6: auditoria de desincronizacion
--   Seccion 7: reversion (comentada)
-- Adaptaciones al schema real respecto de la consigna: ver TP4/informe_tp4.md (Parte 2).
-- =============================================================================

-- =============================================================================
-- SECCION 1: BAJA LOGICA Y DIA DE NEGOCIO
-- =============================================================================

-- Baja logica con flag booleano (regla R7 del proyecto). En PostgreSQL >= 11 agregar una columna
-- NOT NULL con DEFAULT constante es un cambio de catalogo: no reescribe la tabla y todas las
-- filas existentes quedan en FALSE. NOT NULL porque un tercer estado (NULL) no tiene significado:
-- una fila esta vigente o esta dada de baja.
ALTER TABLE pedido         ADD COLUMN IF NOT EXISTS eliminado BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE pedido_detalle ADD COLUMN IF NOT EXISTS eliminado BOOLEAN NOT NULL DEFAULT FALSE;

-- "El dia" de un pedido = fecha calendario de pedido.fecha (TIMESTAMPTZ) en la zona de negocio.
-- Es la UNICA definicion de dia: la usan los disparadores, el reporte y la auditoria, de modo que
-- no dependen de la zona horaria de la sesion. timezone(text, timestamptz) es IMMUTABLE, por lo
-- que la funcion tambien lo es. Si cambiara la zona de negocio habria que recalcular los totales
-- (TRUNCATE + carga inicial de la seccion 4).
CREATE OR REPLACE FUNCTION fn_dia_negocio(p_ts TIMESTAMPTZ)
RETURNS DATE
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$ SELECT (p_ts AT TIME ZONE 'America/Argentina/Buenos_Aires')::date $$;

-- =============================================================================
-- SECCION 2: DATOS DE PRUEBA  *** SOLO EN COPIA (tp4_foodstore) ***
-- NO ejecutar sobre food_store ni sobre datos reales: genera ~50 000 pedidos y ~150 000 detalles
-- con fecha del dia de negocio actual y recategoriza productos. Se ejecuta ANTES de crear la
-- estructura desnormalizada (seccion 4), de modo que la carga masiva no paga el costo de los
-- disparadores y la carga inicial ya la recoge.
-- =============================================================================

-- 7 categorias nuevas (total 10). `nombre` es UNIQUE: re-ejecutar no duplica.
INSERT INTO categoria (nombre) VALUES
    ('Panadería'), ('Carnes'), ('Verduras'), ('Limpieza'), ('Congelados'), ('Golosinas'), ('Perfumería')
ON CONFLICT (nombre) DO NOTHING;

-- Redistribucion de productos entre las 10 categorias (id % 10 -> n-esima categoria por id).
-- Idempotente: solo toca productos cuya categoria difiere de la asignada.
UPDATE producto p
SET    categoria_id = c.id
FROM  (SELECT id, (row_number() OVER (ORDER BY id) - 1) AS rn FROM categoria) c
WHERE  c.rn = p.id % 10
  AND  p.categoria_id IS DISTINCT FROM c.id
  AND (SELECT count(*) FROM categoria) = 10;

-- Pedidos y detalles del dia de negocio actual. Guarda anti-duplicado: si ya hay >= 100 000
-- detalles vigentes hoy, no inserta nada. Cada pedido tiene 3 productos distintos (la PK de
-- pedido_detalle es (pedido_id, producto_id)); subtotal = cantidad * precio_unitario;
-- 1 de cada 20 pedidos y ~1 de cada 25 detalles quedan con eliminado = TRUE para que el filtro
-- de baja logica tenga efecto. Los datos dependen del dia de ejecucion (ver informe).
DO $$
DECLARE
    v_ini      TIMESTAMPTZ := (fn_dia_negocio(now())::timestamp) AT TIME ZONE 'America/Argentina/Buenos_Aires';
    v_ya       BIGINT;
    v_base     BIGINT;
    v_formas   forma_pago_enum[] := ARRAY['EFECTIVO','TARJETA','TRANSFERENCIA','OTRO']::forma_pago_enum[];
    v_clientes BIGINT[];
BEGIN
    SELECT count(*) INTO v_ya
    FROM   pedido_detalle d JOIN pedido p ON p.id = d.pedido_id
    WHERE  p.fecha >= v_ini AND p.fecha < v_ini + INTERVAL '1 day' AND NOT p.eliminado AND NOT d.eliminado;
    IF v_ya >= 100000 THEN
        RAISE NOTICE 'datos de prueba ya cargados (% detalles vigentes hoy): no se inserta nada', v_ya;
        RETURN;
    END IF;
    SELECT coalesce(max(id), 0) INTO v_base FROM pedido;
    SELECT array_agg(id ORDER BY id) INTO v_clientes FROM cliente;
    INSERT INTO pedido (fecha, forma_pago, cliente_id, eliminado)
    SELECT v_ini + ((g * 17) % 86400) * INTERVAL '1 second',
           v_formas[1 + g % 4],
           v_clientes[1 + g % cardinality(v_clientes)],
           (g % 20 = 0)
    FROM   generate_series(1, 50000) g;
    INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal, eliminado)
    SELECT p.id, pr.id, q.cantidad, pr.precio, q.cantidad * pr.precio, ((p.id + k) % 25 = 0)
    FROM   pedido p
    CROSS  JOIN generate_series(1, 3) k
    JOIN   producto pr ON pr.id = 1 + ((p.id * 7919 + k * 4719) % 50005)
    CROSS  JOIN LATERAL (SELECT (1 + ((p.id + k) % 5))::int AS cantidad) q
    WHERE  p.id > v_base;
END $$;

-- Estadisticas actualizadas para que el planificador vea el volumen real.
ANALYZE categoria;
ANALYZE producto;
ANALYZE pedido;
ANALYZE pedido_detalle;
