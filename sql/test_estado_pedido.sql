-- =====================================================================
-- test_estado_pedido.sql — Prueba de 00_estado_pedido.sql
-- Uso: psql -X -w -d foodstore -v ON_ERROR_STOP=1 -f sql/test_estado_pedido.sql
-- Imprime "test_estado_pedido: OK"; ante el primer fallo termina con ERROR.
-- No modifica datos: la prueba del valor por defecto se revierte.
-- =====================================================================

\set QUIET 1
\set ON_ERROR_STOP 1

DO $$
DECLARE
    corte CONSTANT timestamptz := '2026-10-29 00:00:00-03';
    n bigint;
BEGIN
    -- 1. Tipo enumerado con los estados del ciclo de vida, en orden.
    IF to_regtype('estado_pedido_enum') IS NULL THEN
        RAISE EXCEPTION 'falta el tipo estado_pedido_enum';
    END IF;
    IF enum_range(NULL::estado_pedido_enum)::text[]
       <> ARRAY['PENDIENTE', 'EN_PREPARACION', 'ENVIADO', 'ENTREGADO', 'CANCELADO'] THEN
        RAISE EXCEPTION 'valores de estado_pedido_enum inesperados: %',
            enum_range(NULL::estado_pedido_enum);
    END IF;

    -- 2. Columna obligatoria con valor por defecto PENDIENTE.
    PERFORM 1 FROM information_schema.columns
     WHERE table_name = 'pedido' AND column_name = 'estado'
       AND is_nullable = 'NO' AND column_default LIKE '''PENDIENTE''%';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'pedido.estado debe ser NOT NULL DEFAULT ''PENDIENTE''';
    END IF;

    -- 3. La carga inicial siguió la regla en todos los pedidos del lote original
    --    (id <= 200001). Verifica esa carga, no un invariante: si después un pedido
    --    cambia de estado legítimamente (por ejemplo, de ENVIADO a ENTREGADO), este
    --    control falla y hay que actualizarlo.
    SELECT count(*) INTO n FROM pedido
     WHERE id <= 200001
       AND estado <> CASE
             WHEN fecha >= corte - interval '12 hours' THEN 'PENDIENTE'
             WHEN fecha >= corte - interval '1 day'    THEN 'EN_PREPARACION'
             WHEN fecha >= corte - interval '3 days'   THEN 'ENVIADO'
             WHEN id % 20 = 0                          THEN 'CANCELADO'
             ELSE 'ENTREGADO'
           END::estado_pedido_enum;
    IF n > 0 THEN
        RAISE EXCEPTION '% pedidos no cumplen la regla de estados', n;
    END IF;

    -- 4. Todos los estados aparecen en los datos (las consultas por estado tienen con qué trabajar).
    SELECT count(DISTINCT estado) INTO n FROM pedido;
    IF n <> 5 THEN
        RAISE EXCEPTION 'aparecen % estados distintos y se esperaban 5', n;
    END IF;
END $$;

-- 5. Un pedido nuevo nace PENDIENTE (se revierte: no deja datos).
BEGIN;
DO $$
DECLARE
    nuevo pedido%ROWTYPE;
BEGIN
    INSERT INTO pedido (forma_pago, cliente_id)
    SELECT 'EFECTIVO', id FROM cliente WHERE activo ORDER BY id LIMIT 1
    RETURNING * INTO nuevo;
    IF nuevo.estado IS DISTINCT FROM 'PENDIENTE' THEN
        RAISE EXCEPTION 'un pedido nuevo nace con estado %', nuevo.estado;
    END IF;
END $$;
ROLLBACK;

\echo 'test_estado_pedido: OK'
