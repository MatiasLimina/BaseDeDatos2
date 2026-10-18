-- =====================================================================
-- Proyecto Integrador: Food Store (TP4 - Parte 1)
-- Archivo: tp4_fnbc_control_lote.sql
-- Motor: PostgreSQL 16+ (probado en PostgreSQL 18)
-- Descripcion: Forma Normal de Boyce-Codd (FNBC) sobre control_lote_almacen:
--              esquema original con la DF ResponsableControlID -> DepositoID,
--              descomposicion en responsable_deposito + control_lote, vista de
--              compatibilidad v_control_lote_almacen y migracion verificada.
-- Ejecucion: psql -v ON_ERROR_STOP=1 -d <base> -f Proyecto_Integrador/database/tp4_fnbc_control_lote.sql
--            (independiente de schema.sql y de la Parte 2; no requiere orden previo).
-- Idempotente: puede ejecutarse varias veces sobre la misma base.
-- ATENCION: la limpieza inicial hace DROP ... CASCADE de las tablas lote, deposito,
--           usuario, control_lote_almacen, responsable_deposito y control_lote y de la
--           vista v_control_lote_almacen. Son objetos propios de esta parte y no existen
--           en schema.sql; si la base ya tuviera otra tabla llamada `usuario`, `lote` o
--           `deposito`, no ejecute este script.
-- Tests: Proyecto_Integrador/database/tests_tp4/test_fnbc_*.sql
-- Informe: Proyecto_Integrador/documentos/informe_tp4.md (Parte 1)
-- Contenido:
--   Seccion 1: esquema original + instancia de ejemplo
--   Seccion 2: descomposicion en FNBC
--   Seccion 3: migracion, vista de compatibilidad y verificacion
-- =====================================================================

-- -----------------------------------------------------------------------------
-- Limpieza previa (orden inverso de dependencias) -> idempotencia.
-- Solo se borran objetos propios de esta parte.
-- -----------------------------------------------------------------------------
DROP VIEW  IF EXISTS v_control_lote_almacen   CASCADE;
DROP TABLE IF EXISTS control_lote             CASCADE;
DROP TABLE IF EXISTS responsable_deposito     CASCADE;
DROP TABLE IF EXISTS control_lote_almacen     CASCADE;
DROP TABLE IF EXISTS usuario                  CASCADE;
DROP TABLE IF EXISTS deposito                 CASCADE;
DROP TABLE IF EXISTS lote                     CASCADE;

-- =============================================================================
-- SECCION 1: ESQUEMA ORIGINAL E INSTANCIA DE EJEMPLO
-- =============================================================================

-- Tablas maestras minimas (aisladas del resto del TP; usuario NO reemplaza a cliente).
CREATE TABLE lote (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo     VARCHAR(30) NOT NULL UNIQUE,      -- codigo de lote: identificador de negocio, obligatorio y unico
    activo     BOOLEAN NOT NULL DEFAULT TRUE,    -- baja logica (R7), sin borrado fisico
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_lote_codigo_no_vacio CHECK (btrim(codigo) <> '')   -- evita codigos en blanco
);

CREATE TABLE deposito (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre     VARCHAR(80) NOT NULL UNIQUE,      -- nombre obligatorio y unico por deposito
    activo     BOOLEAN NOT NULL DEFAULT TRUE,    -- baja logica (R7), sin borrado fisico
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_deposito_nombre_no_vacio CHECK (btrim(nombre) <> '')   -- evita nombres en blanco
);

CREATE TABLE usuario (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre     VARCHAR(60) NOT NULL,
    apellido   VARCHAR(60) NOT NULL,
    activo     BOOLEAN NOT NULL DEFAULT TRUE,    -- baja logica (R7), sin borrado fisico
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_usuario_nombre_no_vacio   CHECK (btrim(nombre)   <> ''),
    CONSTRAINT ck_usuario_apellido_no_vacio CHECK (btrim(apellido) <> '')
);

-- Esquema ORIGINAL de la consigna: R(LoteID, DepositoID, ResponsableControlID)
-- con PK (LoteID, DepositoID). Tiene la DF ResponsableControlID -> DepositoID que
-- viola FNBC (se analiza en el informe y se descompone en la seccion 2).
CREATE TABLE control_lote_almacen (
    lote_id                BIGINT NOT NULL,      -- participacion total: todo control es sobre un lote
    deposito_id            BIGINT NOT NULL,      -- participacion total: todo control ocurre en un deposito
    responsable_control_id BIGINT NOT NULL,      -- participacion total: todo control tiene responsable
    CONSTRAINT pk_control_lote_almacen PRIMARY KEY (lote_id, deposito_id),
    -- ON DELETE RESTRICT: el historial de controles de calidad no debe perderse
    -- si alguien intenta borrar un lote, deposito o usuario referenciado.
    CONSTRAINT fk_cla_lote        FOREIGN KEY (lote_id)                REFERENCES lote (id)     ON DELETE RESTRICT,
    CONSTRAINT fk_cla_deposito    FOREIGN KEY (deposito_id)            REFERENCES deposito (id) ON DELETE RESTRICT,
    CONSTRAINT fk_cla_responsable FOREIGN KEY (responsable_control_id) REFERENCES usuario (id)  ON DELETE RESTRICT
);

COMMENT ON TABLE control_lote_almacen IS
    'Esquema original de la consigna TP4 (3FN pero no FNBC): DF ResponsableControlID -> DepositoID.';

-- Instancia de ejemplo. Los ids son fijos (consigna) -> OVERRIDING SYSTEM VALUE,
-- luego se reajustan las secuencias para que los proximos ids generados no choquen.
INSERT INTO lote (id, codigo) OVERRIDING SYSTEM VALUE
VALUES (501, 'LOTE-501'), (502, 'LOTE-502'), (503, 'LOTE-503');

INSERT INTO deposito (id, nombre) OVERRIDING SYSTEM VALUE
VALUES (30, 'Deposito 30'), (31, 'Deposito 31');

INSERT INTO usuario (id, nombre, apellido) OVERRIDING SYSTEM VALUE
VALUES (801, 'Responsable', 'Ochocientos Uno'), (802, 'Responsable', 'Ochocientos Dos');

SELECT setval(pg_get_serial_sequence('lote', 'id'),     (SELECT max(id) FROM lote));
SELECT setval(pg_get_serial_sequence('deposito', 'id'), (SELECT max(id) FROM deposito));
SELECT setval(pg_get_serial_sequence('usuario', 'id'),  (SELECT max(id) FROM usuario));

INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id)
VALUES (501, 30, 801),
       (502, 30, 801),
       (503, 31, 802);

-- -----------------------------------------------------------------------------
-- Evidencia de la DF  ResponsableControlID -> DepositoID  sobre la instancia.
-- Si la DF vale, ningun responsable aparece asociado a mas de un deposito:
-- la consulta debe devolver 0 filas.
-- (Una instancia no PRUEBA una DF; solo es coherente con ella. La DF proviene
--  de la regla de negocio: cada responsable pertenece a un unico deposito.)
-- -----------------------------------------------------------------------------
SELECT responsable_control_id
FROM   control_lote_almacen
GROUP  BY responsable_control_id
HAVING count(DISTINCT deposito_id) > 1;

-- =============================================================================
-- SECCION 2: DESCOMPOSICION EN FNBC
-- Algoritmo de clase sobre la DF violatoria  R -> D  (R = ResponsableControlID, D = DepositoID):
--   R1 = X u Y   = {R, D}       -> responsable_deposito   (clave: R)
--   R2 = R - Y   = {L, R}       -> control_lote           (clave: {L, R})
-- Ambas relaciones estan en FNBC: el unico determinante no trivial de R1 es R (su clave);
-- R2 no tiene DFs no triviales distintas de las de su clave.
-- La descomposicion es SIN PERDIDA: el atributo comun R es clave de R1.
-- =============================================================================

-- R1: cada responsable pertenece a UN unico deposito (PK = responsable). Es la DF R -> D
-- convertida en restriccion de clave.
CREATE TABLE responsable_deposito (
    responsable_control_id BIGINT NOT NULL,   -- participacion total: define la fila
    deposito_id            BIGINT NOT NULL,   -- participacion total: todo responsable tiene deposito
    CONSTRAINT pk_responsable_deposito PRIMARY KEY (responsable_control_id),
    -- RESTRICT: no se puede borrar un usuario/deposito que ya tiene asignaciones.
    CONSTRAINT fk_rd_responsable FOREIGN KEY (responsable_control_id) REFERENCES usuario (id)  ON DELETE RESTRICT,
    CONSTRAINT fk_rd_deposito    FOREIGN KEY (deposito_id)            REFERENCES deposito (id) ON DELETE RESTRICT
);

-- R2: que responsable controla cada lote. La FK apunta a responsable_deposito (no a usuario):
-- asi todo responsable usado en un control tiene deposito asignado y la reunion natural
-- no pierde filas. El mismo nombre de columna permite el NATURAL JOIN de la seccion 3.
CREATE TABLE control_lote (
    lote_id                BIGINT NOT NULL,
    responsable_control_id BIGINT NOT NULL,
    CONSTRAINT pk_control_lote PRIMARY KEY (lote_id, responsable_control_id),
    CONSTRAINT fk_cl_lote        FOREIGN KEY (lote_id)                REFERENCES lote (id)                                    ON DELETE RESTRICT,
    CONSTRAINT fk_cl_responsable FOREIGN KEY (responsable_control_id) REFERENCES responsable_deposito (responsable_control_id) ON DELETE RESTRICT
);

-- Indices de la descomposicion. Las PK ya cubren las busquedas por (lote) y por (responsable) en
-- responsable_deposito; faltan los accesos inversos:
-- Consulta que optimiza: "que lotes controla el responsable X" y la verificacion de la FK
-- fk_cl_responsable al borrar/actualizar un responsable_deposito (la PK (lote_id, responsable_control_id)
-- no sirve para buscar por la segunda columna).
CREATE INDEX idx_control_lote_responsable ON control_lote (responsable_control_id);
-- Consulta que optimiza: "que responsables tiene el deposito X" (listar el personal de un
-- deposito) y la verificacion de fk_rd_deposito al borrar un deposito.
CREATE INDEX idx_responsable_deposito_deposito ON responsable_deposito (deposito_id);

COMMENT ON TABLE responsable_deposito IS 'FNBC: R -> D. Cada responsable de control pertenece a un unico deposito.';
COMMENT ON TABLE control_lote         IS 'FNBC: que responsable controla cada lote. El deposito se obtiene via responsable_deposito.';

-- =============================================================================
-- SECCION 3: MIGRACION, VISTA DE COMPATIBILIDAD Y VERIFICACION
-- =============================================================================

-- Verificacion previa: la migracion solo es segura si la DF R -> D vale en los datos
-- (un responsable con dos depositos haria ambiguo el SELECT DISTINCT). Debe dar 0 filas.
SELECT responsable_control_id
FROM   control_lote_almacen
GROUP  BY responsable_control_id
HAVING count(DISTINCT deposito_id) > 1;

-- Migracion: R1 (un hecho por responsable) y luego R2 (un control por lote/responsable).
-- Orden obligatorio: R2 tiene FK hacia R1.
INSERT INTO responsable_deposito (responsable_control_id, deposito_id)
SELECT DISTINCT responsable_control_id, deposito_id
FROM   control_lote_almacen;

INSERT INTO control_lote (lote_id, responsable_control_id)
SELECT lote_id, responsable_control_id
FROM   control_lote_almacen;

-- Vista de compatibilidad: reconstruye la relacion original por NATURAL JOIN. El unico atributo
-- comun es responsable_control_id, que es CLAVE de responsable_deposito -> reunion sin perdida.
-- (En produccion se eliminaria control_lote_almacen y la vista tomaria su nombre; aqui se
--  conserva la tabla original como evidencia para la verificacion EXCEPT.)
CREATE VIEW v_control_lote_almacen AS
SELECT lote_id, deposito_id, responsable_control_id
FROM   control_lote NATURAL JOIN responsable_deposito;

COMMENT ON VIEW v_control_lote_almacen IS
    'Compatibilidad: reconstruye control_lote_almacen(lote_id, deposito_id, responsable_control_id) por NATURAL JOIN sobre responsable_control_id (union sin perdida).';

-- Verificacion de equivalencia: EXCEPT en ambos sentidos. Ambas consultas deben dar 0 filas.
SELECT lote_id, deposito_id, responsable_control_id FROM control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id FROM v_control_lote_almacen;

SELECT lote_id, deposito_id, responsable_control_id FROM v_control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id FROM control_lote_almacen;

-- Mismo conteo (3 y 3).
SELECT (SELECT count(*) FROM control_lote_almacen)   AS filas_original,
       (SELECT count(*) FROM v_control_lote_almacen) AS filas_vista;

-- -----------------------------------------------------------------------------
-- Demostracion: la DF {Lote, Deposito} -> Responsable NO se preserva.
-- En el esquema original la PK (lote_id, deposito_id) la imponia. Tras descomponer, ninguna
-- clave local la impone: un segundo responsable del deposito 30 para el lote 501 es ACEPTADO.
-- Todo ocurre dentro de una transaccion que se REVIERTE (no queda rastro).
-- Decision: solo se documenta y demuestra; NO se impone con disparador.
-- -----------------------------------------------------------------------------
BEGIN;
INSERT INTO usuario (id, nombre, apellido) OVERRIDING SYSTEM VALUE
VALUES (900803, 'Responsable', 'Ochocientos Tres');
INSERT INTO responsable_deposito (responsable_control_id, deposito_id) VALUES (900803, 30);
INSERT INTO control_lote (lote_id, responsable_control_id) VALUES (501, 900803);   -- aceptado
-- La vista muestra DOS responsables para (lote 501, deposito 30):
SELECT * FROM v_control_lote_almacen WHERE lote_id = 501 ORDER BY responsable_control_id;
ROLLBACK;
