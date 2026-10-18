-- =====================================================================
-- Proyecto Integrador: Food Store (TP4 - Parte 2)
-- Archivo: tp4_datos_prueba_top_categorias.sql
-- Motor: PostgreSQL 16+ (probado en PostgreSQL 18)
-- Descripción: Datos de prueba masivos del reporte «top 5 de categorías del día».
--
-- *** SOLO EN COPIA / ENTORNOS DE PRUEBA ***
-- NO ejecutar sobre la base real ni sobre datos de producción: inserta 7 categorías nuevas
-- (total 10), RECATEGORIZA productos (id % 10) y genera ~50 000 pedidos con ~150 000 detalles
-- con fecha del día de negocio actual (parte de ellos con eliminado = TRUE). Antes de ejecutarlo
-- haga una copia de trabajo (ver documentos/protocolo_seguridad.md).
--
-- Orden recomendado (más rápido): ejecutar ESTE archivo ANTES de
-- tp4_desnormalizacion_top_categorias.sql, así la carga masiva no paga el costo de los
-- disparadores y la carga inicial (backfill) del script principal ya la recoge.
-- Si la desnormalización ya está instalada también funciona (los disparadores mantienen los
-- totales sincronizados, pero es más lento); si se prefiere, re-ejecutar luego el script
-- principal reconstruye los totales.
-- Ejecución: psql -v ON_ERROR_STOP=1 -d <base_de_prueba> -f Proyecto_Integrador/database/tp4_datos_prueba_top_categorias.sql
-- Idempotente: guarda anti-duplicado por día de negocio (ver ATENCION en el bloque DO).
-- Los tests test_datos_prueba, test_reporte_top5, test_auditoria, test_ventas_diarias_estructura,
-- test_trigger_detalle y test_trigger_pedido_producto (tests_tp4/) necesitan haber cargado
-- este archivo.
-- =====================================================================

SET client_encoding = 'UTF8';

-- Prerrequisitos (idénticos a la sección 1 de tp4_desnormalizacion_top_categorias.sql;
-- idempotentes): baja lógica `eliminado` y función de día de negocio.
ALTER TABLE pedido         ADD COLUMN IF NOT EXISTS eliminado BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE pedido_detalle ADD COLUMN IF NOT EXISTS eliminado BOOLEAN NOT NULL DEFAULT FALSE;

CREATE OR REPLACE FUNCTION fn_dia_negocio(p_ts TIMESTAMPTZ)
RETURNS DATE
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$ SELECT (p_ts AT TIME ZONE 'America/Argentina/Buenos_Aires')::date $$;

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
-- ATENCION: la guarda cuenta los detalles vigentes del dia de negocio ACTUAL. Si el script se
-- re-ejecuta al dia siguiente (otro dia de negocio) la guarda no encuentra datos "de hoy" y
-- AGREGA otros ~50 000 pedidos / ~150 000 detalles; el volumen acumulado crece una vez por dia.
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

