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

-- =============================================================================
-- SECCION 3: CONSULTA ORIGINAL (BASELINE, NORMALIZADA)
-- Consigna: top 5 de categorias por monto vendido "hoy". Adaptada al schema real:
--   * detalle_pedido -> pedido_detalle
--   * ped.fecha = CURRENT_DATE -> rango [inicio del dia de negocio, +1 dia): pedido.fecha es
--     TIMESTAMPTZ; el rango es sargable sobre idx_pedido_fecha.
--   * baja logica en pedido y detalle; desempate por nombre para que el top 5 sea determinista.
-- Medicion: ejecutar con EXPLAIN (ANALYZE, BUFFERS) 3 veces (ver TP4/evidencias/explain_antes.txt).
-- =============================================================================
SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido
FROM   pedido_detalle dp
JOIN   pedido    ped ON ped.id = dp.pedido_id
JOIN   producto  pr  ON pr.id  = dp.producto_id
JOIN   categoria c   ON c.id   = pr.categoria_id
WHERE  ped.fecha >= (fn_dia_negocio(now())::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires')
  AND  ped.fecha <  (fn_dia_negocio(now())::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires') + INTERVAL '1 day'
  AND  ped.eliminado = FALSE
  AND  dp.eliminado  = FALSE
GROUP  BY c.nombre
ORDER  BY total_vendido DESC, c.nombre
LIMIT  5;

-- =============================================================================
-- SECCION 4: ventas_diarias_categoria (DESNORMALIZACION CONTROLADA)
-- Dato redundante: total vendido por (dia de negocio, categoria), mantenido por disparadores en
-- la MISMA transaccion que modifica la fuente. Es reversible (seccion 7) y auditable (seccion 6).
-- Se prefiere a una vista materializada porque el panel necesita el dato exacto en cada consulta:
-- REFRESH recalcularia todo el historico (el mismo costo que se quiere evitar) y deja una ventana
-- de datos viejos; con disparadores el costo se reparte en cada escritura y no hay ventana.
-- =============================================================================

-- Limpieza previa (idempotencia). Los disparadores se recrean dentro del bloque de instalacion atomica.
DROP VIEW     IF EXISTS v_top5_categorias_dia;
DROP VIEW     IF EXISTS v_auditoria_ventas_diarias;

CREATE TABLE IF NOT EXISTS ventas_diarias_categoria (
    fecha           DATE          NOT NULL,   -- dia de negocio (fn_dia_negocio) de pedido.fecha
    -- Se guarda categoria_id y no el nombre: el nombre puede cambiar (y es UNIQUE, por lo que
    -- agrupar por id equivale a agrupar por nombre). El reporte une con categoria (<= 10 filas).
    categoria_id    BIGINT        NOT NULL,
    -- NUMERIC(14,2) y no (10,2): es un AGREGADO (suma de >= 100 000 lineas por dia/categoria,
    -- ~2e8 en los datos de prueba) y NUMERIC(10,2) se desbordaria en 99 999 999,99. Excepcion
    -- justificada a la regla de montos del proyecto.
    total_vendido   NUMERIC(14,2) NOT NULL,
    -- Permite borrar la fila al llegar a 0 lineas: un total 0 no distingue "sin ventas" de
    -- "ventas de subtotal 0", y asi la tabla coincide con la consulta normalizada.
    cantidad_lineas INTEGER       NOT NULL,
    actualizado_en  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    -- PK (fecha, categoria_id): sirve ademas al filtro `fecha = hoy` del reporte (prefijo), por lo
    -- que no se necesita un indice adicional.
    CONSTRAINT pk_ventas_diarias_categoria PRIMARY KEY (fecha, categoria_id),
    -- ON DELETE RESTRICT: no se puede borrar una categoria con totales historicos.
    CONSTRAINT fk_vdc_categoria FOREIGN KEY (categoria_id) REFERENCES categoria (id) ON DELETE RESTRICT,
    CONSTRAINT chk_vdc_total_no_negativo  CHECK (total_vendido   >= 0),
    CONSTRAINT chk_vdc_lineas_no_negativo CHECK (cantidad_lineas >= 0)
);

-- Funcion nucleo: suma un delta a la fila (fecha, categoria) y la borra al llegar a 0 lineas.
--  * delta_lineas > 0 : upsert atomico (INSERT ... ON CONFLICT DO UPDATE); bloquea la fila hasta el
--    commit, de modo que dos transacciones concurrentes suman sin perder actualizaciones.
--  * delta_lineas < 0 : UPDATE de una fila que debe existir (si no, la tabla ya estaba
--    desincronizada: se aborta con un error explicito en lugar de ocultarlo).
--  Un INSERT directo con delta negativo violaria el CHECK antes de resolver el conflicto, por eso
--  los dos caminos.
CREATE OR REPLACE FUNCTION fn_vdc_aplicar(
    p_fecha         DATE,
    p_categoria_id  BIGINT,
    p_delta_monto   NUMERIC,
    p_delta_lineas  INTEGER
) RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_delta_lineas = 0 AND p_delta_monto = 0 THEN
        RETURN;
    ELSIF p_delta_lineas > 0 THEN
        INSERT INTO ventas_diarias_categoria AS v (fecha, categoria_id, total_vendido, cantidad_lineas)
        VALUES (p_fecha, p_categoria_id, p_delta_monto, p_delta_lineas)
        ON CONFLICT (fecha, categoria_id) DO UPDATE
        SET total_vendido   = v.total_vendido   + EXCLUDED.total_vendido,
            cantidad_lineas = v.cantidad_lineas + EXCLUDED.cantidad_lineas,
            actualizado_en  = now();
    ELSE
        UPDATE ventas_diarias_categoria v
        SET    total_vendido   = v.total_vendido   + p_delta_monto,
               cantidad_lineas = v.cantidad_lineas + p_delta_lineas,
               actualizado_en  = now()
        WHERE  v.fecha = p_fecha AND v.categoria_id = p_categoria_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'ventas_diarias_categoria desincronizada: falta la fila (%, %)', p_fecha, p_categoria_id;
        END IF;
        DELETE FROM ventas_diarias_categoria v
        WHERE  v.fecha = p_fecha AND v.categoria_id = p_categoria_id AND v.cantidad_lineas = 0;
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- Contribucion de una linea: una linea de pedido_detalle contribuye sii
--   NOT detalle.eliminado AND NOT pedido.eliminado,
-- y su clave es (fn_dia_negocio(pedido.fecha), producto.categoria_id ACTUAL). La categoria NO se
-- congela a la fecha de venta: la fuente de verdad (la consulta de la consigna) usa la categoria
-- actual del producto; congelarla haria divergir reporte y auditoria de esa consulta.
-- Este helper lo usa el disparador de detalles; el de pedidos y el de productos usan variantes
-- agregadas del mismo criterio.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_vdc_linea(
    p_pedido_id   BIGINT,
    p_producto_id BIGINT,
    p_subtotal    NUMERIC,
    p_signo       INTEGER      -- +1 agrega la linea, -1 la quita
) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_fecha DATE;
    v_cat   BIGINT;
BEGIN
    SELECT fn_dia_negocio(p.fecha), pr.categoria_id INTO v_fecha, v_cat
    FROM   pedido p, producto pr
    WHERE  p.id = p_pedido_id AND pr.id = p_producto_id AND NOT p.eliminado;
    IF FOUND THEN                       -- un pedido eliminado no aporta lineas
        PERFORM fn_vdc_aplicar(v_fecha, v_cat, p_signo * p_subtotal, p_signo);
    END IF;
END $$;

-- Aporte agregado de TODAS las lineas vigentes de un pedido, por categoria, en el dia que
-- corresponde a p_fecha (p_signo = +1 suma, -1 resta). Lo usa el disparador de pedidos.
CREATE OR REPLACE FUNCTION fn_vdc_pedido_aplicar(
    p_pedido_id BIGINT,
    p_fecha     TIMESTAMPTZ,
    p_signo     INTEGER
) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT pr.categoria_id, SUM(d.subtotal) AS total, COUNT(*)::int AS n
             FROM   pedido_detalle d JOIN producto pr ON pr.id = d.producto_id   -- PK (pedido_id, producto_id)
             WHERE  d.pedido_id = p_pedido_id AND NOT d.eliminado
             GROUP  BY pr.categoria_id
    LOOP
        PERFORM fn_vdc_aplicar(fn_dia_negocio(p_fecha), r.categoria_id, p_signo * r.total, p_signo * r.n);
    END LOOP;
END $$;

-- Disparador sobre pedido_detalle: UPDATE = "quitar la linea vieja + agregar la nueva". Un unico
-- camino cubre cambios de subtotal, producto, pedido y baja logica / reactivacion.
CREATE OR REPLACE FUNCTION fn_vdc_trg_detalle() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') AND NOT OLD.eliminado THEN
        PERFORM fn_vdc_linea(OLD.pedido_id, OLD.producto_id, OLD.subtotal, -1);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') AND NOT NEW.eliminado THEN
        PERFORM fn_vdc_linea(NEW.pedido_id, NEW.producto_id, NEW.subtotal, 1);
    END IF;
    RETURN NULL;    -- AFTER ROW: el valor de retorno se ignora
END $$;

-- Disparador sobre pedido: baja logica / reactivacion o cambio de fecha mueve o descuenta todos sus
-- detalles vigentes. INSERT de pedido no requiere accion (aun no tiene detalles); el DELETE fisico
-- esta bloqueado por la FK RESTRICT mientras tenga detalles.
CREATE OR REPLACE FUNCTION fn_vdc_trg_pedido() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT OLD.eliminado THEN
        PERFORM fn_vdc_pedido_aplicar(OLD.id, OLD.fecha, -1);   -- estado viejo: quitar
    END IF;
    IF NOT NEW.eliminado THEN
        PERFORM fn_vdc_pedido_aplicar(NEW.id, NEW.fecha, 1);    -- estado nuevo: agregar
    END IF;
    RETURN NULL;
END $$;

-- Disparador sobre producto: recategorizar mueve, para cada dia con ventas vigentes del producto, el
-- monto de la categoria vieja a la nueva. Usa idx_detalle_producto_id (que viene del TP3 y NO esta
-- en Proyecto_Integrador/database/schema.sql). Es costoso para productos con mucho historial pero
-- infrecuente.
CREATE OR REPLACE FUNCTION fn_vdc_trg_producto() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT fn_dia_negocio(p.fecha) AS dia, SUM(d.subtotal) AS total, COUNT(*)::int AS n
             FROM   pedido_detalle d JOIN pedido p ON p.id = d.pedido_id
             WHERE  d.producto_id = NEW.id AND NOT d.eliminado AND NOT p.eliminado
             GROUP  BY 1
    LOOP
        PERFORM fn_vdc_aplicar(r.dia, OLD.categoria_id, -r.total, -r.n);
        PERFORM fn_vdc_aplicar(r.dia, NEW.categoria_id,  r.total,  r.n);
    END LOOP;
    RETURN NULL;
END $$;

-- Instalacion atomica: bloqueo + disparadores + carga inicial en UNA transaccion (un bloque DO es
-- una sola sentencia/transaccion, tambien via un cliente que ejecuta de a una sentencia).
-- SHARE ROW EXCLUSIVE bloquea escrituras concurrentes en las tres tablas fuente hasta el commit
-- (las lecturas siguen permitidas): ninguna venta puede quedar fuera de la carga inicial ni de los
-- disparadores. La carga recalcula TODO el historico por fn_dia_negocio y categoria actual.
--
-- Concurrencia en operacion normal: dos transacciones que venden la misma categoria el mismo dia
-- serializan sobre la fila caliente (fecha, categoria) hasta el commit (aceptado para el volumen del
-- TP; mitigacion futura: contadores fragmentados). Si dos transacciones tocan categorias A y B en
-- orden inverso puede haber interbloqueo: PostgreSQL aborta una y la aplicacion reintenta.
-- TRUNCATE de las tablas fuente NO esta sincronizado (la auditoria lo detectaria).
DO $$
BEGIN
    LOCK TABLE pedido, pedido_detalle, producto IN SHARE ROW EXCLUSIVE MODE;

    DROP TRIGGER IF EXISTS trg_vdc_pedido_detalle ON pedido_detalle;
    DROP TRIGGER IF EXISTS trg_vdc_pedido         ON pedido;
    DROP TRIGGER IF EXISTS trg_vdc_producto       ON producto;

    CREATE TRIGGER trg_vdc_pedido_detalle
        AFTER INSERT OR UPDATE OF subtotal, producto_id, pedido_id, eliminado OR DELETE
        ON pedido_detalle
        FOR EACH ROW EXECUTE FUNCTION fn_vdc_trg_detalle();

    CREATE TRIGGER trg_vdc_pedido
        AFTER UPDATE OF eliminado, fecha ON pedido
        FOR EACH ROW
        WHEN (OLD.eliminado IS DISTINCT FROM NEW.eliminado OR OLD.fecha IS DISTINCT FROM NEW.fecha)
        EXECUTE FUNCTION fn_vdc_trg_pedido();

    CREATE TRIGGER trg_vdc_producto
        AFTER UPDATE OF categoria_id ON producto
        FOR EACH ROW
        WHEN (OLD.categoria_id IS DISTINCT FROM NEW.categoria_id)
        EXECUTE FUNCTION fn_vdc_trg_producto();

    TRUNCATE ventas_diarias_categoria;
    INSERT INTO ventas_diarias_categoria (fecha, categoria_id, total_vendido, cantidad_lineas)
    SELECT fn_dia_negocio(p.fecha), pr.categoria_id, SUM(d.subtotal), COUNT(*)
    FROM   pedido_detalle d
    JOIN   pedido   p  ON p.id  = d.pedido_id
    JOIN   producto pr ON pr.id = d.producto_id
    WHERE  NOT p.eliminado AND NOT d.eliminado
    GROUP  BY 1, 2;
END $$;

-- =============================================================================
-- SECCION 7: REVERSION (comentada) - retira la desnormalizacion sin tocar la fuente
-- Ejecutar dentro de una transaccion si se desea (BEGIN; ...; COMMIT;). No elimina la columna
-- `eliminado` ni fn_dia_negocio (no forman parte de la desnormalizacion). pedido, pedido_detalle,
-- producto y categoria no se modifican. Verificado por TP4/tests/test_reversibilidad.sql.
-- =============================================================================
-- DROP VIEW IF EXISTS v_top5_categorias_dia;
-- DROP VIEW IF EXISTS v_auditoria_ventas_diarias;
-- DROP TRIGGER IF EXISTS trg_vdc_pedido_detalle ON pedido_detalle;
-- DROP TRIGGER IF EXISTS trg_vdc_pedido         ON pedido;
-- DROP TRIGGER IF EXISTS trg_vdc_producto       ON producto;
-- DROP FUNCTION IF EXISTS fn_vdc_trg_detalle();
-- DROP FUNCTION IF EXISTS fn_vdc_trg_pedido();
-- DROP FUNCTION IF EXISTS fn_vdc_trg_producto();
-- DROP FUNCTION IF EXISTS fn_vdc_linea(BIGINT, BIGINT, NUMERIC, INTEGER);
-- DROP FUNCTION IF EXISTS fn_vdc_pedido_aplicar(BIGINT, TIMESTAMPTZ, INTEGER);
-- DROP FUNCTION IF EXISTS fn_vdc_aplicar(DATE, BIGINT, NUMERIC, INTEGER);
-- DROP TABLE    IF EXISTS ventas_diarias_categoria;
