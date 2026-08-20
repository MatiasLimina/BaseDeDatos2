# Contexto del Proyecto: Food Store (TP1 - Base de Datos I)

## Reglas de Negocio
- R1: Todo producto pertenece exactamente a una categoría; una categoría puede tener muchos productos o ninguno.
- R2: Todo pedido pertenece exactamente a un cliente registrado; un cliente puede no tener pedidos o tener varios[cite: 1].
- R3: Relación N:M entre pedido y producto (tabla intermedia requerida)[cite: 1].
- R4: En el detalle del pedido registrar cantidad y precio unitario histórico al momento de la venta[cite: 1].
- R5: Stock y precio de producto no pueden ser negativos (CHECK)[cite: 1].
- R6: Email de cliente único (UNIQUE)[cite: 1].
- R7: Baja lógica con flag booleano (ej. `activo BOOLEAN NOT NULL DEFAULT TRUE`), sin borrado físico[cite: 1].

## Directivas Técnicas para DDL (PostgreSQL)
- Motor: PostgreSQL[cite: 1].
- Claves primarias: `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY`.
- Tipos de datos:
  - Textos: `VARCHAR(n)` con longitudes máximas razonables.
  - Monedas y precios: `NUMERIC(10,2)` (nunca floats).
  - Fechas: `TIMESTAMPTZ NOT NULL DEFAULT now()`.
  - Enumerados: Crear tipos con `CREATE TYPE ... AS ENUM` para dominios cerrados (ej. `forma_pago_enum`).
- Integridad referencial: `FOREIGN KEY ... REFERENCES` explícitas con política justificada (ej. `ON DELETE RESTRICT`).
- Restricciones: Al menos 1 `UNIQUE`, al menos 3 `CHECK`, y `NOT NULL` justificado por participación total.
- Índices: Incluir al menos 2 `CREATE INDEX` con comentarios que expliquen la consulta que optimizan.