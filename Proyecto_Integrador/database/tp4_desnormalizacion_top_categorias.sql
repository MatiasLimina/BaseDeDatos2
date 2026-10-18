-- =====================================================================
-- Proyecto Integrador: Food Store (TP4 - Parte 2)
-- Archivo: tp4_desnormalizacion_top_categorias.sql
-- Motor: PostgreSQL 16+ (probado en PostgreSQL 18)
-- Descripción: Desnormalización controlada para el reporte «top 5 de categorías
--              del día»: tabla redundante ventas_diarias_categoria mantenida por
--              disparadores, carga inicial (backfill) sobre los datos reales,
--              reporte, auditoría de desincronización y reversión.
-- Ejecución: psql -v ON_ERROR_STOP=1 -d <base> -f Proyecto_Integrador/database/tp4_desnormalizacion_top_categorias.sql
-- Prerrequisitos: schema.sql (categoria, producto, cliente, pedido, pedido_detalle).
--   Objetos que usa y que deben existir (la sección 1 los crea si faltan):
--     * pedido.eliminado y pedido_detalle.eliminado (se agregan con ALTER idempotente;
--       NO están en schema.sql).
--     * idx_pedido_fecha ON pedido(fecha) y idx_detalle_producto_id ON
--       pedido_detalle(producto_id) (vienen del TP3; no están en schema.sql).
-- Idempotente: puede ejecutarse varias veces; re-ejecutarlo reconstruye los totales.
-- Datos de prueba masivos: están en tp4_datos_prueba_top_categorias.sql (SOLO EN COPIA).
-- Tests: Proyecto_Integrador/database/tests_tp4/.
-- Informe: Proyecto_Integrador/documentos/informe_tp4.md (Parte 2) y sección 8 del
--          informe técnico consolidado.
-- Contenido:
--   Sección 1: baja lógica `eliminado`, índices prerrequisito y función de día de negocio
--   Sección 2: (datos de prueba: movida a tp4_datos_prueba_top_categorias.sql)
--   Sección 3: consulta original (baseline, normalizada)
--   Sección 4: tabla ventas_diarias_categoria + disparadores + carga inicial
--   Sección 5: consulta desnormalizada + vista del reporte
--   Sección 6: auditoría de desincronización
--   Sección 7: reversión (comentada)
-- Adaptaciones al schema real respecto de la consigna: ver informe_tp4.md (Parte 2).
-- =====================================================================

-- Este archivo está en UTF-8. psql en la consola de Windows usa la codificación del sistema
-- (WIN1252/CP850); se fuerza UTF8 para que los textos con tilde no se corrompan.
SET client_encoding = 'UTF8';

-- =============================================================================
-- SECCION 1: BAJA LOGICA Y DIA DE NEGOCIO
-- =============================================================================

-- Baja logica con flag booleano (regla R7 del proyecto). En PostgreSQL >= 11 agregar una columna
-- NOT NULL con DEFAULT constante es un cambio de catalogo: no reescribe la tabla y todas las
-- filas existentes quedan en FALSE. NOT NULL porque un tercer estado (NULL) no tiene significado:
-- una fila esta vigente o esta dada de baja.
ALTER TABLE pedido         ADD COLUMN IF NOT EXISTS eliminado BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE pedido_detalle ADD COLUMN IF NOT EXISTS eliminado BOOLEAN NOT NULL DEFAULT FALSE;

-- Índices prerrequisito. Vienen del TP3 y NO están en schema.sql ni en
-- indices_parciales_soft_delete.sql; se crean sólo si no hay ya un índice B-tree válido, no
-- parcial, cuya primera columna sea la indicada (con ese u otro nombre), para no duplicar.
--  * idx_pedido_fecha ON pedido(fecha): hace sargable el filtro por rango de día de la consulta
--    normalizada (sección 3) y de las consultas por fecha de pedido.
--  * idx_detalle_producto_id ON pedido_detalle(producto_id): lo usa trg_vdc_producto
--    (fn_vdc_trg_producto) para hallar las líneas de un producto al recategorizarlo; sin él cada
--    UPDATE de producto.categoria_id recorrería todo pedido_detalle. La PK (pedido_id,
--    producto_id) no sirve: su primera columna es pedido_id.
-- Limitaciones conocidas del bloque (documentadas, la lógica no se cambió):
--  * No filtra por método de acceso (btree): un índice BRIN o hash sobre esa columna haría que
--    se saltee la creación aunque no sirva para el rango/orden.
--  * Si ya existe un índice PARCIAL o INVÁLIDO llamado idx_pedido_fecha (o idx_detalle_producto_id),
--    la condición no lo cuenta y el CREATE INDEX falla por nombre duplicado.
--  * No usa CREATE INDEX CONCURRENTLY (no puede ir dentro de un bloque DO): en una base grande
--    bloquea las escrituras de la tabla mientras construye el índice.
--  * La rama CREATE INDEX no se probó (en tp4_foodstore los índices ya existían).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_index i
        WHERE  i.indrelid = 'pedido'::regclass AND i.indisvalid AND i.indpred IS NULL
          AND  i.indkey[0] = (SELECT attnum FROM pg_attribute WHERE attrelid = 'pedido'::regclass AND attname = 'fecha')
    ) THEN
        CREATE INDEX idx_pedido_fecha ON pedido (fecha);
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_index i
        WHERE  i.indrelid = 'pedido_detalle'::regclass AND i.indisvalid AND i.indpred IS NULL
          AND  i.indkey[0] = (SELECT attnum FROM pg_attribute WHERE attrelid = 'pedido_detalle'::regclass AND attname = 'producto_id')
    ) THEN
        CREATE INDEX idx_detalle_producto_id ON pedido_detalle (producto_id);
    END IF;
END $$;

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
-- SECCION 2: DATOS DE PRUEBA -> movida a tp4_datos_prueba_top_categorias.sql
-- (SOLO EN COPIA / entornos de prueba). Este script trabaja con los datos reales: la carga
-- inicial de la sección 4 recalcula los totales de todo el histórico existente.
-- =============================================================================

-- =============================================================================
-- SECCION 3: CONSULTA ORIGINAL (BASELINE, NORMALIZADA)
-- Consigna: top 5 de categorias por monto vendido "hoy". Adaptada al schema real:
--   * detalle_pedido -> pedido_detalle
--   * ped.fecha = CURRENT_DATE -> rango [inicio del dia de negocio, +1 dia): pedido.fecha es
--     TIMESTAMPTZ; el rango es sargable sobre idx_pedido_fecha.
--   * baja logica en pedido y detalle; desempate por nombre para que el top 5 sea determinista.
-- Medicion: ejecutar con EXPLAIN (ANALYZE, BUFFERS) 3 veces (ver Proyecto_Integrador/documentos/tp4_evidencias/explain_antes.txt).
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

-- Desviaciones deliberadas de las directivas de AGENTS.md (justificadas):
--  * PK compuesta natural (fecha, categoria_id) en lugar de `BIGINT GENERATED ALWAYS AS IDENTITY`:
--    la tabla es un agregado cuya identidad ES el par (dia, categoria); la clave natural es la que
--    habilita el upsert INSERT ... ON CONFLICT (fecha, categoria_id) y el filtro `fecha = hoy` por
--    prefijo de indice; una clave subrogada exigiria ademas un UNIQUE(fecha, categoria_id).
--  * `fecha` es DATE (dia de negocio) y no `TIMESTAMPTZ NOT NULL DEFAULT now()`: no representa un
--    instante de alta sino la clave de agregacion (el instante de la ultima actualizacion esta en
--    `actualizado_en`, que si es TIMESTAMPTZ NOT NULL DEFAULT now()).
--  * `total_vendido` es NUMERIC(14,2) y no NUMERIC(10,2) (ver mas abajo).
CREATE TABLE IF NOT EXISTS ventas_diarias_categoria (
    fecha           DATE          NOT NULL,   -- dia de negocio (fn_dia_negocio) de pedido.fecha
    -- Se guarda categoria_id y no el nombre: el nombre puede cambiar (y es UNIQUE, por lo que
    -- agrupar por id equivale a agrupar por nombre). El reporte une con categoria (<= 10 filas).
    categoria_id    BIGINT        NOT NULL,
    -- NUMERIC(14,2) y no (10,2): es un AGREGADO (en los datos de prueba, ~15 000 lineas por
    -- categoria y dia con subtotales de miles suman ~1e8-2e8) y NUMERIC(10,2) se desbordaria en
    -- 99 999 999,99. Excepcion justificada a la regla de montos del proyecto.
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
    v_elim  BOOLEAN;
    v_fecha DATE;
    v_cat   BIGINT;
BEGIN
    -- Se bloquea SIEMPRE (sin filtrar por p.eliminado en el WHERE) y se decide DESPUES de leer:
    -- si el filtro estuviera en el WHERE, un pedido eliminado no tomaria ningun bloqueo y una
    -- reactivacion concurrente (UPDATE pedido SET eliminado = FALSE) podria perder la linea.
    -- Ver "CONCURRENCIA" mas abajo.
    SELECT p.eliminado, fn_dia_negocio(p.fecha), pr.categoria_id INTO v_elim, v_fecha, v_cat
    FROM   pedido p, producto pr
    WHERE  p.id = p_pedido_id AND pr.id = p_producto_id
    FOR SHARE OF p, pr;
    IF FOUND AND NOT v_elim THEN        -- un pedido eliminado no aporta lineas
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

-- TRUNCATE de pedido / pedido_detalle no dispara disparadores de fila y dejaria la tabla de totales
-- desincronizada sin aviso: se bloquea con un disparador BEFORE TRUNCATE que aborta la sentencia
-- (decision: es barato y evita el error silencioso; para vaciar las fuentes use DELETE, que si
-- sincroniza, o desinstale primero la desnormalizacion con la seccion 7). `producto` no necesita
-- guarda propia: las FK de pedido_detalle impiden TRUNCATE producto sin CASCADE, y con CASCADE
-- (tambien TRUNCATE categoria CASCADE) la cascada alcanza a pedido_detalle y dispara este mismo
-- bloqueo, por lo que la sentencia aborta.
CREATE OR REPLACE FUNCTION fn_vdc_bloquear_truncate() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'TRUNCATE de % no permitido: ventas_diarias_categoria no se puede sincronizar con TRUNCATE; use DELETE o reconstruya los totales (ver seccion 4 del script)', TG_TABLE_NAME
        USING ERRCODE = 'feature_not_supported';
END $$;

-- -----------------------------------------------------------------------------
-- CONCURRENCIA (analisis completo; ver tambien design.md decision 14 e informe, punto c)
--
-- 1. Escenario sin proteccion (READ COMMITTED, lectura sin bloqueo en fn_vdc_linea):
--      T1: UPDATE pedido SET eliminado = TRUE WHERE id = 7;
--          -> trg_vdc_pedido lee los detalles del pedido 7 (los que ve su sentencia) y RESTA su aporte.
--      T2 (a la vez): INSERT INTO pedido_detalle (pedido_id = 7, ...);
--          -> trg_vdc_pedido_detalle lee el pedido 7: como T1 aun no hizo commit, lo ve con
--             eliminado = FALSE y SUMA la linea.
--      Ambas hacen commit. Resultado: pedido eliminado pero con una linea sumada que nadie resto
--      (T1 no vio el detalle de T2 y T2 no vio la baja de T1): total de mas, auditoria != 0.
--    Analogo con producto: T1 cambia producto.categoria_id mientras T2 inserta un detalle de ese
--    producto (T2 suma en la categoria vieja y T1 no movio esa linea).
--
-- 2. Por que los bloqueos existentes no lo evitan: el INSERT en pedido_detalle toma, por las FK,
--    FOR KEY SHARE sobre la fila de pedido y sobre la de producto; el UPDATE de pedido.eliminado /
--    fecha y de producto.categoria_id toma FOR NO KEY UPDATE (no modifican columnas de clave).
--    FOR KEY SHARE y FOR NO KEY UPDATE son COMPATIBLES: ninguna transaccion espera a la otra.
--
-- 3. Que cierra FOR SHARE OF p, pr en fn_vdc_linea: FOR SHARE SI conflicta con FOR NO KEY UPDATE.
--    Cuando el disparador del detalle lee pedido y producto toma ese bloqueo y lo conserva hasta el
--    commit de T2. Si T1 llega despues, su UPDATE espera a T2 y, al despertar, su disparador
--    (con snapshot nuevo, READ COMMITTED) ya ve el detalle de T2 y lo resta. Si T1 llego primero,
--    T2 espera a T1 y al despertar la fila de pedido re-evaluada tiene eliminado = TRUE: no suma.
--    Importante: el bloqueo se toma tambien cuando el pedido YA esta eliminado (la funcion lee
--    p.eliminado sin filtrarlo en el WHERE y decide despues). Caso espejo, REACTIVACION: T1 hace
--    UPDATE pedido SET eliminado = FALSE sobre un pedido eliminado y trg_vdc_pedido SUMA los detalles
--    vigentes que ve; T2 inserta un detalle del mismo pedido. Si T2 no tomara bloqueo (filtro
--    NOT p.eliminado en el WHERE) leeria eliminado = TRUE, no sumaria y la linea se perderia al
--    confirmar T1. Con el bloqueo T2 espera a T1, relee eliminado = FALSE y suma; si T2 llego primero,
--    T1 espera a T2 y su disparador ya ve el detalle de T2 y lo suma. En los escenarios
--    analizados (baja y reactivacion, en ambos ordenes de llegada) el resultado es correcto.
--
-- 4. Costo: (a) contencion: mientras dura la transaccion que inserta/modifica el detalle, las filas
--    de pedido y producto leidas quedan bloqueadas contra UPDATE; en particular un
--    UPDATE producto SET stock = ... concurrente espera a que terminen las ventas en curso de ese
--    producto. (b) deadlocks posibles: dos ventas del mismo producto que hacen primero INSERT
--    (cada una con FOR SHARE) y despues UPDATE producto SET stock (que necesita FOR NO KEY UPDATE)
--    se esperan mutuamente. Mitigacion: la aplicacion debe actualizar el stock ANTES de insertar
--    detalles (toma primero el bloqueo fuerte) o ordenar siempre igual los productos; PostgreSQL
--    detecta el deadlock y aborta una transaccion, que se reintenta. (c) fila caliente: ventas
--    simultaneas de la misma categoria el mismo dia se serializan en la fila (fecha, categoria) de
--    ventas_diarias_categoria hasta el commit (mitigacion futura: contadores fragmentados); con
--    categorias tocadas en orden inverso tambien puede haber deadlock. (d) ciclos nuevos introducidos
--    por FOR SHARE: pedido <-> fila de totales y producto <-> fila de totales. Ejemplo: T2 ya vendio
--    una linea de la categoria C ese dia (tiene la fila (hoy, C) bloqueada) y ahora inserta otro
--    detalle del pedido 7 (necesita FOR SHARE sobre pedido 7), mientras T1 hizo UPDATE pedido SET
--    eliminado sobre el pedido 7 (tiene la fila de pedido y quiere actualizar la fila (hoy, C)):
--    se esperan mutuamente. Analogo con UPDATE producto SET categoria_id (tiene la fila de producto
--    y quiere las filas de totales) contra una venta de ese producto. PostgreSQL detecta el ciclo y
--    aborta UNA de las transacciones con el error de deadlock (sin corrupcion: se revierte entera)
--    y la aplicacion reintenta. Mitigacion ya en uso en el proyecto: el SP real
--    Proyecto_Integrador/database/procedures.sql (lineas 110-114) toma SELECT ... FOR UPDATE sobre
--    producto ANTES de insertar el detalle, es decir toma primero el bloqueo fuerte.
--
-- 5. Carrera residual (NO cerrada): baja logica / cambio de fecha de un PEDIDO vs recategorizacion
--    de un PRODUCTO que ese pedido contiene. trg_vdc_pedido y trg_vdc_producto leen sin bloquearse
--    mutuamente: el primero resta de la categoria vieja y el segundo, que no ve la baja sin commit,
--    mueve esa misma linea de la vieja a la nueva. Es una operacion administrativa muy poco
--    frecuente; mitigaciones: ejecutar ambas operaciones en transacciones SERIALIZABLE (una aborta
--    con error de serializacion y se reintenta) o aceptar la ventana y detectarla con la
--    auditoria (seccion 6) y reconstruir (punto 7).
--
-- 6. Caso exotico no soportado: sentencia con CTE modificante que cambia pedido.eliminado y
--    inserta detalles del mismo pedido en UNA sola sentencia (WITH u AS (UPDATE pedido ...) INSERT
--    INTO pedido_detalle ...). Los disparadores AFTER corren al final, con la baja ya visible:
--    trg_vdc_pedido_detalle no suma las lineas nuevas pero trg_vdc_pedido las resta como si
--    estuvieran sumadas; la sentencia aborta con "desincronizada" si falta la fila o, si no, la
--    auditoria lo detecta. Se evita separando la baja y el alta en sentencias distintas.
--
-- 7. Reconstruccion (si la auditoria devuelve filas): volver a ejecutar el bloque de instalacion
--    de abajo (LOCK + TRUNCATE ventas_diarias_categoria + carga inicial), que es idempotente y
--    deja la tabla igual a la fuente. Mientras corre, las escrituras en las fuentes esperan.
--
-- 8. Garantia: con el bloqueo FOR SHARE (tambien sobre pedidos eliminados) y los disparadores, la
--    tabla queda consistente en los escenarios de concurrencia analizados (puntos 1 a 3, en
--    READ COMMITTED); NO es una garantia absoluta: quedan la carrera residual (punto 5), el caso
--    exotico (punto 6) y cualquier interleaving que este analisis no haya contemplado. La auditoria
--    (seccion 6) es la red de seguridad.
--
-- 9. Privilegios: SELECT ... FOR SHARE exige, ademas de SELECT, privilegio UPDATE (sobre al menos
--    una columna) en pedido y producto para el rol que dispara el trigger, porque las funciones
--    NO son SECURITY DEFINER. Al integrar al proyecto hay que verificar los privilegios del rol de
--    la aplicacion o declarar las funciones fn_vdc_* SECURITY DEFINER con search_path fijo.
-- -----------------------------------------------------------------------------

-- Instalacion atomica: bloqueo + disparadores + carga inicial en UNA transaccion (un bloque DO es
-- una sola sentencia/transaccion, tambien via un cliente que ejecuta de a una sentencia).
-- SHARE ROW EXCLUSIVE bloquea escrituras concurrentes en las tres tablas fuente hasta el commit
-- (las lecturas siguen permitidas): ninguna venta puede quedar fuera de la carga inicial ni de los
-- disparadores durante la instalacion. La carga recalcula TODO el historico por fn_dia_negocio y
-- categoria actual. (La concurrencia en operacion normal se analiza arriba.)
DO $$
BEGIN
    LOCK TABLE pedido, pedido_detalle, producto IN SHARE ROW EXCLUSIVE MODE;

    DROP TRIGGER IF EXISTS trg_vdc_pedido_detalle ON pedido_detalle;
    DROP TRIGGER IF EXISTS trg_vdc_pedido         ON pedido;
    DROP TRIGGER IF EXISTS trg_vdc_producto       ON producto;
    DROP TRIGGER IF EXISTS trg_vdc_truncate_pedido  ON pedido;
    DROP TRIGGER IF EXISTS trg_vdc_truncate_detalle ON pedido_detalle;

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

    CREATE TRIGGER trg_vdc_truncate_pedido
        BEFORE TRUNCATE ON pedido
        FOR EACH STATEMENT EXECUTE FUNCTION fn_vdc_bloquear_truncate();

    CREATE TRIGGER trg_vdc_truncate_detalle
        BEFORE TRUNCATE ON pedido_detalle
        FOR EACH STATEMENT EXECUTE FUNCTION fn_vdc_bloquear_truncate();

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
-- SECCION 5: CONSULTA DESNORMALIZADA (REPORTE) Y VISTA
-- Lee ventas_diarias_categoria (<= 10 filas por dia) y une con categoria solo para el nombre.
-- Medicion: EXPLAIN (ANALYZE, BUFFERS) 3 veces (ver Proyecto_Integrador/documentos/tp4_evidencias/explain_despues.txt).
-- =============================================================================
SELECT c.nombre AS categoria, v.total_vendido
FROM   ventas_diarias_categoria v
JOIN   categoria c ON c.id = v.categoria_id
WHERE  v.fecha = fn_dia_negocio(now())
ORDER  BY v.total_vendido DESC, c.nombre
LIMIT  5;

-- La misma consulta como vista, para que los tests la comparen con la normalizada. Es un SELECT
-- simple: el planificador la expande y el plan es el mismo que el de la consulta suelta.
CREATE OR REPLACE VIEW v_top5_categorias_dia AS
SELECT c.nombre AS categoria, v.total_vendido
FROM   ventas_diarias_categoria v
JOIN   categoria c ON c.id = v.categoria_id
WHERE  v.fecha = fn_dia_negocio(now())
ORDER  BY v.total_vendido DESC, c.nombre
LIMIT  5;

-- =============================================================================
-- SECCION 6: AUDITORIA DE DESINCRONIZACION
-- Recalcula desde la fuente de verdad (mismo criterio de contribucion que los disparadores) todo
-- el historico por (dia de negocio, categoria actual) y lo compara con ventas_diarias_categoria
-- con FULL OUTER JOIN: devuelve una fila por cada (fecha, categoria_id) cuyo total o cantidad
-- de lineas difiere, que falta en la tabla redundante o que sobra en ella.
-- Resultado esperado: 0 filas. Es una tarea de auditoria (recorre todo el historico), no del panel.
-- =============================================================================
CREATE OR REPLACE VIEW v_auditoria_ventas_diarias AS
WITH fuente AS (
    SELECT fn_dia_negocio(ped.fecha) AS fecha, pr.categoria_id, SUM(dp.subtotal) AS total, COUNT(*)::int AS lineas
    FROM   pedido_detalle dp
    JOIN   pedido   ped ON ped.id = dp.pedido_id
    JOIN   producto pr  ON pr.id  = dp.producto_id
    WHERE  NOT ped.eliminado AND NOT dp.eliminado
    GROUP  BY 1, 2
)
SELECT COALESCE(f.fecha, v.fecha)               AS fecha,
       COALESCE(f.categoria_id, v.categoria_id) AS categoria_id,
       f.total   AS total_fuente,  v.total_vendido    AS total_tabla,
       f.lineas  AS lineas_fuente, v.cantidad_lineas  AS lineas_tabla
FROM   fuente f
FULL   OUTER JOIN ventas_diarias_categoria v ON v.fecha = f.fecha AND v.categoria_id = f.categoria_id
WHERE  f.total  IS DISTINCT FROM v.total_vendido
   OR  f.lineas IS DISTINCT FROM v.cantidad_lineas;

-- Ejecucion de la auditoria (0 filas = sincronizada):
SELECT * FROM v_auditoria_ventas_diarias ORDER BY fecha, categoria_id;

-- =============================================================================
-- SECCION 7: REVERSION (comentada) - retira la desnormalizacion sin tocar la fuente
-- Ejecutar dentro de una transaccion si se desea (BEGIN; ...; COMMIT;). No elimina la columna
-- `eliminado` ni fn_dia_negocio (no forman parte de la desnormalizacion). pedido, pedido_detalle,
-- producto y categoria no se modifican. Verificado por Proyecto_Integrador/database/tests_tp4/test_reversibilidad.sql.
-- =============================================================================
-- DROP VIEW IF EXISTS v_top5_categorias_dia;
-- DROP VIEW IF EXISTS v_auditoria_ventas_diarias;
-- DROP TRIGGER IF EXISTS trg_vdc_pedido_detalle ON pedido_detalle;
-- DROP TRIGGER IF EXISTS trg_vdc_pedido         ON pedido;
-- DROP TRIGGER IF EXISTS trg_vdc_producto       ON producto;
-- DROP TRIGGER IF EXISTS trg_vdc_truncate_pedido  ON pedido;
-- DROP TRIGGER IF EXISTS trg_vdc_truncate_detalle ON pedido_detalle;
-- DROP FUNCTION IF EXISTS fn_vdc_trg_detalle();
-- DROP FUNCTION IF EXISTS fn_vdc_trg_pedido();
-- DROP FUNCTION IF EXISTS fn_vdc_trg_producto();
-- DROP FUNCTION IF EXISTS fn_vdc_bloquear_truncate();
-- DROP FUNCTION IF EXISTS fn_vdc_linea(BIGINT, BIGINT, NUMERIC, INTEGER);
-- DROP FUNCTION IF EXISTS fn_vdc_pedido_aplicar(BIGINT, TIMESTAMPTZ, INTEGER);
-- DROP FUNCTION IF EXISTS fn_vdc_aplicar(DATE, BIGINT, NUMERIC, INTEGER);
-- DROP TABLE    IF EXISTS ventas_diarias_categoria;
