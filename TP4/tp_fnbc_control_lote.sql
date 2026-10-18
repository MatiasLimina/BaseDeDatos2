-- =============================================================================
-- TP4 - Parte 1: Forma Normal de Boyce-Codd (FNBC) - control_lote_almacen
-- Proyecto : Food Store - Base de Datos II
-- Motor    : PostgreSQL 18
-- Base     : tp4_foodstore (NUNCA food_store ni food_store_copia)
-- Ejecucion: psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f TP4/tp_fnbc_control_lote.sql
-- El script es idempotente: puede ejecutarse varias veces sobre la misma base.
-- Contenido:
--   Seccion 1: esquema original + instancia de ejemplo
--   Seccion 2: descomposicion en FNBC
--   Seccion 3: migracion, vista de compatibilidad y verificacion
-- =============================================================================

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
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE deposito (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre     VARCHAR(80) NOT NULL UNIQUE,      -- nombre obligatorio y unico por deposito
    activo     BOOLEAN NOT NULL DEFAULT TRUE,    -- baja logica (R7), sin borrado fisico
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE usuario (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre     VARCHAR(60) NOT NULL,
    apellido   VARCHAR(60) NOT NULL,
    activo     BOOLEAN NOT NULL DEFAULT TRUE,    -- baja logica (R7), sin borrado fisico
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
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
