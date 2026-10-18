-- Test (Parte 2, grupo 6): fn_dia_negocio(timestamptz) -> date en zona America/Argentina/Buenos_Aires.
-- Ejecutar: psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f TP4/tests/test_dia_negocio.sql
DO $$
DECLARE
    v_d    DATE;
    v_prov CHAR;
BEGIN
    ASSERT to_regprocedure('fn_dia_negocio(timestamptz)') IS NOT NULL, 'no existe fn_dia_negocio(timestamptz)';

    SELECT provolatile INTO v_prov FROM pg_proc WHERE oid = 'fn_dia_negocio(timestamptz)'::regprocedure;
    ASSERT v_prov = 'i', 'fn_dia_negocio debe ser IMMUTABLE (provolatile=' || v_prov || ')';

    -- 23:30 en Buenos Aires = 02:30 UTC del dia siguiente: debe seguir siendo el dia 18 de BA
    SET LOCAL TimeZone = 'UTC';
    v_d := fn_dia_negocio('2026-10-18 23:30-03');
    ASSERT v_d = DATE '2026-10-18', 'con TimeZone=UTC devolvio ' || v_d;

    SET LOCAL TimeZone = 'America/Argentina/Buenos_Aires';
    v_d := fn_dia_negocio('2026-10-18 23:30-03');
    ASSERT v_d = DATE '2026-10-18', 'con TimeZone=BA devolvio ' || v_d;

    -- Triangulacion: un instante a las 00:30 de BA (03:30 UTC) cae en el dia 19, y 23:59:59 aun en el 18
    SET LOCAL TimeZone = 'UTC';
    ASSERT fn_dia_negocio('2026-10-19 00:30-03') = DATE '2026-10-19', 'medianoche BA mal asignada';
    ASSERT fn_dia_negocio('2026-10-18 23:59:59-03') = DATE '2026-10-18', 'ultimo segundo BA mal asignado';
    -- Un instante UTC de la tarde de BA (14:00 UTC = 11:00 BA) sigue el mismo dia
    ASSERT fn_dia_negocio('2026-10-18 02:30+00') = DATE '2026-10-17', '02:30 UTC es 23:30 del 17 en BA';
END $$;
