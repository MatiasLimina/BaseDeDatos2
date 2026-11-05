-- =====================================================================
-- 00_estado_pedido.sql — Agrega el estado del pedido a Food Store (TP Unidad 7)
-- PostgreSQL 16 o superior. Uso:
--   psql -X -w -h localhost -U postgres -d foodstore -v ON_ERROR_STOP=1 -f sql/00_estado_pedido.sql
--
-- Por qué: la consigna del TP7 pide documentos con "fecha, estado, cliente..."
-- y una consulta por estado, pero la tabla pedido de este Food Store no tenía
-- estado (solo forma_pago). El equipo decidió agregarlo a la base relacional,
-- para que MongoDB y PostgreSQL trabajen sobre los mismos datos.
--
-- Procedencia de los datos: los 200 001 pedidos existentes son sintéticos
-- (generar_registros_adaptado.sql, TP3-TP4) y no tenían estado. Se les asigna
-- uno con una regla determinista, a partir de su fecha y de una fecha de corte
-- fija: la de la carga del lote. Usar now() haría que el resultado dependiera
-- del día en que se ejecuta.
--   fecha >= corte - 12 h            -> PENDIENTE
--   fecha >= corte - 1 día           -> EN_PREPARACION
--   fecha >= corte - 3 días          -> ENVIADO
--   más antiguos, id múltiplo de 20  -> CANCELADO  (5 %)
--   más antiguos, resto              -> ENTREGADO
-- Los pedidos nuevos nacen PENDIENTE (valor por defecto).
--
-- Idempotente: si la columna ya existe no hace nada, así una segunda corrida
-- no reclasifica los pedidos cargados después.
-- Antes de aplicarlo se tomó el respaldo foodstore_20261101_113633.dump (TP6).
-- =====================================================================

BEGIN;

DO $$
BEGIN
    IF to_regtype('estado_pedido_enum') IS NULL THEN
        CREATE TYPE estado_pedido_enum AS ENUM
            ('PENDIENTE', 'EN_PREPARACION', 'ENVIADO', 'ENTREGADO', 'CANCELADO');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'pedido'
                     AND column_name = 'estado') THEN
        -- Con un DEFAULT constante PostgreSQL no reescribe la tabla al agregar la columna.
        ALTER TABLE pedido
            ADD COLUMN estado estado_pedido_enum NOT NULL DEFAULT 'PENDIENTE';

        -- EXECUTE: la columna recién creada no existía cuando se compiló el bloque.
        EXECUTE $upd$
            UPDATE pedido
               SET estado = CASE
                   WHEN fecha >= '2026-10-29 00:00:00-03'::timestamptz - interval '12 hours'
                        THEN 'PENDIENTE'
                   WHEN fecha >= '2026-10-29 00:00:00-03'::timestamptz - interval '1 day'
                        THEN 'EN_PREPARACION'
                   WHEN fecha >= '2026-10-29 00:00:00-03'::timestamptz - interval '3 days'
                        THEN 'ENVIADO'
                   WHEN id % 20 = 0 THEN 'CANCELADO'
                   ELSE 'ENTREGADO'
               END::estado_pedido_enum
        $upd$;

        COMMENT ON COLUMN pedido.estado IS
            'Ciclo de vida del pedido (TP7). Datos existentes: asignados con regla '
            'determinista por fecha (corte 2026-10-29 00:00 -03), ver 00_estado_pedido.sql';
    END IF;
END $$;

COMMIT;

-- El UPDATE deja 200 001 tuplas muertas y desactualiza las estadísticas.
ANALYZE pedido;

SELECT estado, count(*) AS pedidos FROM pedido GROUP BY estado ORDER BY estado;
