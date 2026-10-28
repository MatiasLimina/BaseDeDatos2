-- =====================================================================
-- Base de Datos II — Trabajo Práctico Unidad 5 (Food Store)
-- Archivo: sql/equivalencia_usuario_anon.sql
-- Propósito: Parte D.2/D.3 — la misma agregación (cuentas por rol y mes de
--            alta) sobre usuario_anon y sobre usuario, con la demostración
--            de que los resultados coinciden. Termina con
--            "equivalencia_usuario_anon: OK".
--
-- Ejecución (como DBA, después de sql/usuario_anon.sql):
--   psql -v ON_ERROR_STOP=1 -d <base> -f TP5/sql/equivalencia_usuario_anon.sql
--
-- Especificación de la agregación:
--   * una fila por mes de alta y rol con al menos una cuenta;
--   * mes de alta = created_at en 'America/Argentina/Buenos_Aires',
--     truncado al mes, como DATE (independiente de la zona de la sesión:
--     created_at es TIMESTAMPTZ y el borde de mes cambia con la zona);
--   * total_cuentas (activas y dadas de baja) y cuentas_activas;
--   * ordenado por mes_alta y rol.
-- =====================================================================

\set ON_ERROR_STOP 1

-- ---------------------------------------------------------------------
-- 1. Consulta sobre usuario_anon (la que puede compartirse)
-- ---------------------------------------------------------------------
\echo '=== 1. usuario_anon ==='
SELECT date_trunc('month', created_at AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS mes_alta,
       rol,
       count(*)                       AS total_cuentas,
       count(*) FILTER (WHERE activo) AS cuentas_activas
FROM usuario_anon
GROUP BY 1, 2
ORDER BY 1, 2;

-- ---------------------------------------------------------------------
-- 2. Consulta equivalente sobre usuario (la tabla real)
-- ---------------------------------------------------------------------
\echo '=== 2. usuario ==='
SELECT date_trunc('month', created_at AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS mes_alta,
       rol,
       count(*)                       AS total_cuentas,
       count(*) FILTER (WHERE activo) AS cuentas_activas
FROM usuario
GROUP BY 1, 2
ORDER BY 1, 2;

-- ---------------------------------------------------------------------
-- 3. Lado a lado: cada grupo con los conteos de ambas tablas
-- ---------------------------------------------------------------------
\echo '=== 3. Lado a lado ==='
WITH anon AS (
    SELECT date_trunc('month', created_at AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS mes_alta,
           rol, count(*) AS total, count(*) FILTER (WHERE activo) AS activas
    FROM usuario_anon GROUP BY 1, 2
), real AS (
    SELECT date_trunc('month', created_at AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS mes_alta,
           rol, count(*) AS total, count(*) FILTER (WHERE activo) AS activas
    FROM usuario GROUP BY 1, 2
)
SELECT coalesce(a.mes_alta, r.mes_alta) AS mes_alta,
       coalesce(a.rol, r.rol)           AS rol,
       a.total   AS anon_total,   r.total   AS real_total,
       a.activas AS anon_activas, r.activas AS real_activas,
       CASE WHEN a.total = r.total AND a.activas = r.activas
            THEN 'igual' ELSE 'DISTINTO' END AS comparacion
FROM anon a
FULL JOIN real r USING (mes_alta, rol)
ORDER BY 1, 2;

-- ---------------------------------------------------------------------
-- 4. Demostración: diferencia simétrica vacía, en varias zonas de sesión
-- ---------------------------------------------------------------------
-- Se repite con tres zonas horarias de sesión distintas: si la consulta
-- dependiera de TimeZone, una cuenta dada de alta cerca del borde de mes
-- podría cambiar de grupo.
CREATE TEMP TABLE resultado_equivalencia (zona TEXT, grupos INTEGER, solo_anon INTEGER, solo_real INTEGER);

DO $$
DECLARE
    z TEXT;
    v_grupos INTEGER;
    v_solo_anon INTEGER;
    v_solo_real INTEGER;
BEGIN
    FOREACH z IN ARRAY ARRAY['America/Argentina/Buenos_Aires', 'UTC', 'Asia/Tokyo'] LOOP
        PERFORM set_config('TimeZone', z, true);

        WITH anon AS (
            SELECT date_trunc('month', created_at AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS mes_alta,
                   rol, count(*) AS total, count(*) FILTER (WHERE activo) AS activas
            FROM usuario_anon GROUP BY 1, 2
        ), real AS (
            SELECT date_trunc('month', created_at AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS mes_alta,
                   rol, count(*) AS total, count(*) FILTER (WHERE activo) AS activas
            FROM usuario GROUP BY 1, 2
        )
        SELECT (SELECT count(*) FROM real),
               (SELECT count(*) FROM (SELECT * FROM anon EXCEPT SELECT * FROM real) x),
               (SELECT count(*) FROM (SELECT * FROM real EXCEPT SELECT * FROM anon) y)
        INTO v_grupos, v_solo_anon, v_solo_real;

        INSERT INTO resultado_equivalencia VALUES (z, v_grupos, v_solo_anon, v_solo_real);

        ASSERT v_solo_anon = 0 AND v_solo_real = 0,
            format('con TimeZone=%s los resultados difieren: %s grupos solo en usuario_anon, %s solo en usuario',
                   z, v_solo_anon, v_solo_real);
    END LOOP;

    ASSERT (SELECT count(DISTINCT grupos) FROM resultado_equivalencia) = 1,
        'la cantidad de grupos no debe depender de la zona horaria de la sesión';
END
$$;

\echo '=== 4. Diferencia simétrica por zona horaria de la sesión ==='
SELECT * FROM resultado_equivalencia;

\echo 'equivalencia_usuario_anon: OK'
