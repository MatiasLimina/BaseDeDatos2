-- =====================================================================
-- Proyecto Integrador: Food Store (TP1 - Base de Datos I)
-- Archivo: schema.sql
-- Motor: PostgreSQL
-- Descripción: Creación del esquema definitivo (DDL)
-- =====================================================================

-- Eliminar tipos y tablas si existen (orden inverso por dependencias)
DROP TABLE IF EXISTS pedido_detalle CASCADE;
DROP TABLE IF EXISTS pedido CASCADE;
DROP TABLE IF EXISTS cliente CASCADE;
DROP TABLE IF EXISTS producto CASCADE;
DROP TABLE IF EXISTS categoria CASCADE;

DROP TYPE IF EXISTS forma_pago_enum CASCADE;

-- ---------------------------------------------------------------------
-- 1. Tipos Enumerados
-- ---------------------------------------------------------------------
CREATE TYPE forma_pago_enum AS ENUM (
    'EFECTIVO',
    'TARJETA',
    'TRANSFERENCIA',
    'OTRO'
);

-- ---------------------------------------------------------------------
-- 2. Tabla: categoria
-- ---------------------------------------------------------------------
CREATE TABLE categoria (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL UNIQUE,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 3. Tabla: producto
-- ---------------------------------------------------------------------
CREATE TABLE producto (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    precio NUMERIC(10,2) NOT NULL,
    stock INTEGER NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    categoria_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Restricciones de Dominio (CHECK) - R5: Stock y precio no negativos
    CONSTRAINT chk_producto_precio_no_negativo CHECK (precio >= 0.00),
    CONSTRAINT chk_producto_stock_no_negativo CHECK (stock >= 0),
    
    -- Integridad Referencial (1:N)
    -- ON DELETE RESTRICT: Impide borrar categorías con productos asociados (R7)
    CONSTRAINT fk_producto_categoria 
        FOREIGN KEY (categoria_id) 
        REFERENCES categoria(id) 
        ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- 4. Tabla: cliente
-- ---------------------------------------------------------------------
CREATE TABLE cliente (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(60) NOT NULL,
    apellido VARCHAR(60) NOT NULL,
    email VARCHAR(120) NOT NULL,
    telefono VARCHAR(30), -- Parcial: puede no tener teléfono registrado
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Restricción UNIQUE - R6: Email único en el sistema
    CONSTRAINT unq_cliente_email UNIQUE (email)
);

-- ---------------------------------------------------------------------
-- 5. Tabla: pedido
-- ---------------------------------------------------------------------
CREATE TABLE pedido (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha TIMESTAMPTZ NOT NULL DEFAULT now(),
    forma_pago forma_pago_enum NOT NULL,
    cliente_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Integridad Referencial (1:N)
    -- ON DELETE RESTRICT: Protege el historial de pedidos ante borrados de clientes
    CONSTRAINT fk_pedido_cliente 
        FOREIGN KEY (cliente_id) 
        REFERENCES cliente(id) 
        ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- 6. Tabla Intermedia: pedido_detalle (Relación N:M)
-- ---------------------------------------------------------------------
CREATE TABLE pedido_detalle (
    pedido_id BIGINT NOT NULL,
    producto_id BIGINT NOT NULL,
    cantidad INTEGER NOT NULL,
    precio_unitario NUMERIC(10,2) NOT NULL, -- R4: Histórico al momento de la venta
    subtotal NUMERIC(10,2) NOT NULL,
    
    -- Clave Primaria Compuesta
    CONSTRAINT pk_pedido_detalle PRIMARY KEY (pedido_id, producto_id),
    
    -- Restricciones CHECK para cantidades y precios unitarios históricos válidos
    CONSTRAINT chk_detalle_cantidad_positiva CHECK (cantidad > 0),
    CONSTRAINT chk_detalle_precio_positivo CHECK (precio_unitario >= 0.00),
    CONSTRAINT chk_detalle_subtotal_positivo CHECK (subtotal >= 0.00),
    
    -- Claves Foráneas con ON DELETE RESTRICT para trazabilidad histórica
    CONSTRAINT fk_detalle_pedido 
        FOREIGN KEY (pedido_id) 
        REFERENCES pedido(id) 
        ON DELETE RESTRICT,
    CONSTRAINT fk_detalle_producto 
        FOREIGN KEY (producto_id) 
        REFERENCES producto(id) 
        ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- 7. Índices Justificados
-- ---------------------------------------------------------------------

-- Índice 1: Acelera la búsqueda de todos los pedidos realizados por un cliente específico.
CREATE INDEX idx_pedido_cliente_id ON pedido(cliente_id);

-- Índice 2: Acelera el listado y filtrado de productos vigentes (activos) dentro de una categoría.
CREATE INDEX idx_producto_categoria_activo ON producto(categoria_id, activo);