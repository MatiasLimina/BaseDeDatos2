-- =====================================================================
-- Proyecto Integrador: Food Store (TP2)
-- Archivo: seed.sql
-- Descripción: Datos iniciales de prueba (seed data) para verificar
--              restricciones, triggers y escenarios de concurrencia.
-- =====================================================================

-- Limpiar datos existentes (si se reejecuta)
TRUNCATE TABLE pedido_detalle, pedido, producto, cliente, categoria RESTART IDENTITY CASCADE;

-- 1. Insertar Categorías
INSERT INTO categoria (nombre, activo) VALUES
('Bebidas', TRUE),
('Snacks', TRUE),
('Lácteos', TRUE);

-- 2. Insertar Productos (incluyendo uno inactivo para probar Regla 3)
INSERT INTO producto (nombre, precio, stock, activo, categoria_id) VALUES
('Coca Cola 1.5L', 2500.00, 50, TRUE, 1),
('Agua Mineral 500ml', 1200.00, 100, TRUE, 1),
('Papas Fritas 150g', 1800.00, 30, TRUE, 2),
('Queso Tybo x 200g', 3200.00, 15, TRUE, 3),
('Producto Descatalogado', 999.00, 0, FALSE, 2);

-- 3. Insertar Clientes (incluyendo uno inactivo para probar Regla 1)
INSERT INTO cliente (nombre, apellido, email, telefono, activo) VALUES
('Juan', 'Pérez', 'juan.perez@email.com', '1122334455', TRUE),
('María', 'Gómez', 'maria.gomez@email.com', '1199887766', TRUE),
('Carlos', 'Inactivo', 'carlos.inactivo@email.com', NULL, FALSE);

-- 4. Insertar un Pedido y su Detalle inicial (para pruebas y concurrencia)
INSERT INTO pedido (forma_pago, cliente_id) VALUES
('EFECTIVO', 1); -- ID 1 (Juan Pérez)

INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES
(1, 1, 2, 2500.00, 5000.00); -- 2 x Coca Cola 1.5L
