# Base de Datos II — Trabajo Práctico Unidad 3

## Índices, Vistas y Vistas Materializadas en Food Store

**Materia:** Base de Datos II  
**Carrera:** Tecnicatura Universitaria en Programación  
**Motor de BD:** PostgreSQL 16+  
**Repositorio GitHub:** [https://github.com/MatiasLimina/BaseDeDatos2.git](https://github.com/MatiasLimina/BaseDeDatos2.git)

### Integrantes del Equipo
* **Matías Limina**
* **Nicolás Monjelardi**
* **Lautaro Agüero**

*(Modalidad grupal de 3 integrantes, conforme a la consigna §1).*

---

## 1. Estructura del Entregable (Consigna §7)

```text
TP3/
├── README.md                 # Guía de reproducción, autores, enlace a repo y protocolo de seguridad
├── indices.sql               # Plan de indexado: índice aceptado (idx_pedido_fecha) e índices descartados
├── views.sql                 # Vistas del sistema, verificación de equivalencia (EXCEPT + COUNT) y prueba DCL
├── queries.sql               # Consultas frecuentes del negocio y bloque de prueba de inserción
├── materializadas.sql        # Vista materializada mv_facturacion_categoria_mes con índice UNIQUE
├── duia.md                   # Bitácora consolidada de Declaración de Uso de IA (Kiro y OpenCode)
├── informe_mediciones.md     # Informe técnico completo con análisis EXPLAIN ANALYZE antes/después
├── spec_punto_4_1.md         # Especificación Kiro - Parte A (Plan de indexado)
├── spec_punto_4.2/           # Especificación Kiro - Parte B (Vistas ordinarias)
└── spec_punto_4.3/           # Especificación Kiro - Parte C (Vista materializada)
```

---

## 2. Protocolo de Seguridad y Respaldo (Consigna §5.3)

Conforme a la directiva de la cátedra (*"Probar sobre una copia de la base o dentro de una transacción reversible, con respaldo previo cuando corresponda"*), todas las mediciones y pruebas destructivas se realizaron bajo el siguiente esquema:

### 2.1 Respaldo previo de la base operativa
Antes de iniciar la creación de índices o la ejecución de inserciones masivas, se generó un respaldo completo del esquema y datos mediante `pg_dump`:

```bash
# 1. Respaldo preventivo en formato Custom (según protocolo_seguridad.md)
pg_dump -U postgres -h localhost -p 5432 -d foodstore -F c -b -v -f "backup_foodstore_pre_tp3.backup"

# 2. Respaldo en texto plano (SQL) como salvaguarda
pg_dump -U postgres -h localhost -p 5432 -d foodstore -F p -v -f "backup_foodstore_pre_tp3.sql"
```

### 2.2 Entorno aislado de pruebas (`foodstore_copia`)
Para no afectar el entorno base ni contaminar datos de auditoría, las pruebas se ejecutaron sobre una copia clonada dedicada:

```bash
# Creación de la copia de trabajo a partir de template (según protocolo_seguridad.md)
createdb -U postgres -T foodstore foodstore_copia
```

O mediante SQL:
```sql
CREATE DATABASE foodstore_copia WITH TEMPLATE foodstore OWNER postgres;
```

### 2.3 Ejecución en transacciones reversibles (`BEGIN ... ROLLBACK`)
Las pruebas de estrés de escrituras y las mediciones de impacto de inserción masiva se envolvieron en transacciones con reversión automática para garantizar idempotencia:

```sql
\c foodstore_copia

BEGIN;

-- Medición de inserción masiva (500 tuplas)
DO $$
BEGIN
  FOR i IN 1..500 LOOP
    INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
    VALUES (i, (i % 100) + 1, FLOOR(RANDOM() * 10) + 1, ROUND((RANDOM() * 100)::numeric, 2), 0);
  END LOOP;
END $$;

-- Verificación de registros insertados temporalmente
SELECT COUNT(*) FROM pedido_detalle WHERE subtotal = 0;

-- Reversión de la transacción para mantener el estado limpio
ROLLBACK;
```

---

## 3. Guía de Reproducción Paso a Paso

Para reproducir los resultados y mediciones reportados en `informe_mediciones.md`, ejecutar los scripts en el siguiente orden estricto dentro de PostgreSQL 16+:

### Paso 1: Inicialización del esquema base
```bash
psql -U postgres -d foodstore_copia -f "../Proyecto_Integrador/database/schema.sql"
```

### Paso 2: Carga masiva de datos (Dataset para medición)
Se requiere un volumen representativo (mínimo ~50.000 productos y ~600.000 detalles de pedidos) para observar diferencias significativas en el optimizador:
```bash
psql -U postgres -d foodstore_copia -f "../Proyecto_Integrador/database/seed.sql"
```

### Paso 3: Verificación de consultas previas a indexar
Ejecutar las consultas base y verificar los planes iniciales:
```bash
psql -U postgres -d foodstore_copia -f "queries.sql"
```

### Paso 4: Aplicación del Plan de Indexado
Aplica únicamente el índice que demostró ganancia empírica real (`idx_pedido_fecha`) y mantiene comentados los índices descartados por sobreindexación:
```bash
psql -U postgres -d foodstore_copia -f "indices.sql"
```

### Paso 5: Despliegue y verificación de vistas ordinarias
Crea las 3 vistas, ejecuta las pruebas de equivalencia simétrica con `EXCEPT` complementadas con `COUNT(*)`, y valida el aislamiento de seguridad mediante `GRANT` y un rol restringido:
```bash
psql -U postgres -d foodstore_copia -f "views.sql"
```

### Paso 6: Despliegue de la Vista Materializada
Crea `mv_facturacion_categoria_mes` con `WITH DATA`, genera su índice `UNIQUE` y ejecuta la comparación de tiempo de respuesta (760 ms vs 0.020 ms):
```bash
psql -U postgres -d foodstore_copia -f "materializadas.sql"
```

---

## 4. Resumen de Decisiones de Optimización

1. **Índices Aceptados vs. Descartados:**
   - **Aceptado:** `idx_pedido_fecha ON pedido(fecha)`. Redujo el tiempo de 289.65 ms a 0.018 ms (~16.000×) cambiando `Parallel Seq Scan` a `Index Scan`.
   - **Descartado por Sobreindexación 1:** `idx_detalle_producto_id ON pedido_detalle(producto_id)`. El planner lo ignoró (mantuvo `Seq Scan + Hash Join`) debido al alto volumen a procesar. La aparente mejora fue efecto de *warm cache*.
   - **Descartado por Sobreindexación 2:** `idx_detalle_subtotal ON pedido_detalle(pedido_id, subtotal DESC)`. La consulta ya utilizaba `Index Scan` sobre la clave primaria `pk_pedido_detalle`. El índice nuevo aumentó el tiempo de ejecución de 0.055 ms a 0.102 ms (+85% de overhead innecesario).
   - **Descartado por Baja Cardinalidad:** `idx_pedido_forma_pago ON pedido(forma_pago)`. Columna tipo ENUM de 4 valores; baja selectividad que PostgreSQL resuelve con `Seq Scan`.

2. **Equivalencia de Vistas:**
   - Las verificaciones con `EXCEPT` eliminan duplicados por definición de conjuntos (`DISTINCT` implícito). Para garantizar equivalencia multiconjunto rigurosa, se complementaron con comparaciones automáticas de `COUNT(*)`.

3. **Seguridad en Vistas (Principio de Mínimo Privilegio):**
   - La vista `vw_pedidos_cliente` restringe columnas sensibles (`email`, `telefono`, `created_at`). Se probó con el rol `rol_reportes_foodstore`, verificando acceso concedido a la vista y denegado (`permission denied`) a la tabla `cliente`.
