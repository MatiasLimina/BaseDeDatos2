PRAGMA foreign_keys = ON;
-- ^ Tiene que ser la primera sentencia: PRAGMA foreign_keys vale por conexion y,
--   sin esto, SQLite acepta items de productos inexistentes en silencio (caso C7).

-- Esquema de la base de la tablet (TP8). Re-ejecutable: borra y recrea todo en orden
-- inverso de dependencias. Todas las tablas son STRICT: el tipo declarado se respeta
-- y un valor que no corresponde (por ejemplo 't' en una columna INTEGER) se rechaza.
DROP TABLE IF EXISTS cola_sync;
DROP TABLE IF EXISTS item_borrador;
DROP TABLE IF EXISTS pedido_borrador;
DROP TABLE IF EXISTS snapshot_servidor;
DROP TABLE IF EXISTS producto_cache;

-- Copia local (solo lectura) del catalogo del servidor. El id es el del servidor, por
-- eso no lleva AUTOINCREMENT. Los booleanos son 0/1 porque SQLite no tiene tipo booleano.
CREATE TABLE producto_cache (
  id INTEGER PRIMARY KEY,
  nombre TEXT NOT NULL,
  precio_centavos INTEGER NOT NULL CHECK (precio_centavos >= 0),  -- entero: sin errores de redondeo
  stock_visto INTEGER NOT NULL CHECK (stock_visto >= 0),          -- el stock que vio la tablet, no el real
  disponible INTEGER NOT NULL CHECK (disponible IN (0,1)),
  eliminado INTEGER NOT NULL CHECK (eliminado IN (0,1)),          -- "lapida": la fila no se borra nunca
  copiado_en TEXT NOT NULL                                        -- ISO-8601 UTC: ordenable como texto
) STRICT;

-- Borrador de pedido hecho en la tablet. El id es un UUID canonico en minusculas
-- (36 caracteres, guiones en 9/14/19/24 y el resto hexadecimal): generado en la tablet,
-- sin depender de un contador del servidor. GLOB distingue mayusculas, por eso rechaza A-F.
CREATE TABLE pedido_borrador (
  id_local TEXT PRIMARY KEY CHECK (length(id_local) = 36
    AND substr(id_local,9,1) = '-' AND substr(id_local,14,1) = '-'
    AND substr(id_local,19,1) = '-' AND substr(id_local,24,1) = '-'
    AND length(replace(id_local,'-','')) = 32
    AND replace(id_local,'-','') NOT GLOB '*[^0-9a-f]*'),
  usuario TEXT NOT NULL,                                          -- alias (nunca datos personales reales)
  -- OTRO existe en el enum del servidor pero queda afuera a proposito: la consigna
  -- limita la tablet a tres formas de pago.
  forma_pago TEXT NOT NULL CHECK (forma_pago IN ('EFECTIVO','TARJETA','TRANSFERENCIA')),
  fecha TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))  -- SQLite no tiene tipo fecha
) STRICT;

-- Items del borrador. La PK compuesta replica pk_pedido_detalle del servidor y garantiza
-- un item por producto (el semaforo suma por solicitud). Sin ON DELETE CASCADE: en la
-- tablet nada se borra fisicamente, los borradores son historia.
CREATE TABLE item_borrador (
  id_local TEXT NOT NULL REFERENCES pedido_borrador (id_local),
  producto_id INTEGER NOT NULL REFERENCES producto_cache (id),
  cantidad INTEGER NOT NULL CHECK (cantidad > 0),                 -- cantidad 0 no es un item
  precio_centavos_visto INTEGER NOT NULL CHECK (precio_centavos_visto >= 0),  -- base del conflicto de precio
  PRIMARY KEY (id_local, producto_id)
) STRICT;

-- Cola de solicitudes de sincronizacion. La PK es el UUID de la solicitud: reenviar el
-- mismo UUID falla por clave duplicada (idempotencia, caso C6). Nace PENDIENTE y solo
-- el semaforo la cambia. evaluada_en y snapshot_copiado_en dejan registro de cuando y
-- contra que instantanea se evaluo.
CREATE TABLE cola_sync (
  solicitud_uuid TEXT PRIMARY KEY CHECK (length(solicitud_uuid) = 36
    AND substr(solicitud_uuid,9,1) = '-' AND substr(solicitud_uuid,14,1) = '-'
    AND substr(solicitud_uuid,19,1) = '-' AND substr(solicitud_uuid,24,1) = '-'
    AND length(replace(solicitud_uuid,'-','')) = 32
    AND replace(solicitud_uuid,'-','') NOT GLOB '*[^0-9a-f]*'),
  id_local TEXT NOT NULL REFERENCES pedido_borrador (id_local),
  estado TEXT NOT NULL DEFAULT 'PENDIENTE'
    CHECK (estado IN ('PENDIENTE','SIMULADO_APROBADO','CONFLICTO','RECHAZADO')),
  motivo TEXT,
  creada_en TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
  evaluada_en TEXT,
  snapshot_copiado_en TEXT
) STRICT;

-- Tabla de aterrizaje del .import del CSV del servidor. Se crea ACA, antes del .import,
-- con las mismas columnas y el mismo orden que la vista v_snapshot_movil. Si la creara
-- .import, todas las columnas serian TEXT. La comparacion directa columna contra columna
-- igual funcionaria (por afinidad), pero fallan en silencio las expresiones
-- ("cantidad + 0 > stock"), max(stock) y ORDER BY, que comparan texto: ver
-- evidencias/importacion_sin_tabla_previa.txt. Con STRICT previa, .import convierte '123'
-- en 123 y rechaza 't'/'f' o '12.50' en columnas enteras. Sin claves foraneas ni PK: es de paso.
CREATE TABLE snapshot_servidor (
  id INTEGER NOT NULL,
  nombre TEXT NOT NULL,
  precio_centavos INTEGER NOT NULL CHECK (precio_centavos >= 0),
  stock INTEGER NOT NULL CHECK (stock >= 0),
  disponible INTEGER NOT NULL CHECK (disponible IN (0,1)),
  eliminado INTEGER NOT NULL CHECK (eliminado IN (0,1)),
  copiado_en TEXT NOT NULL,
  filas_copia INTEGER NOT NULL      -- total esperado: la importacion verifica que no falto ninguna fila
) STRICT;
