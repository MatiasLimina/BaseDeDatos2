---
name: tpi-documenter
description: >-
  Audita, unifica y construye la documentación técnica y el informe final del Trabajo Práctico Integrador (TPI) «Food Store» para Base de Datos II (PostgreSQL 16+), garantizando el cumplimiento de los 9 objetivos de evaluación de la cátedra, la consolidación de los scripts DDL/DML/PLpgSQL, el reporte de optimización con mediciones y la declaración de uso de IA (DUIA).
---

# TPI Documenter - Base de Datos II (Food Store)

Esta skill define el procedimiento estándar para auditar, consolidar y redactar la documentación técnica del Trabajo Práctico Integrador (**TPI**) «Food Store» para **PostgreSQL 16+**, asegurando la cobertura exhaustiva de los criterios exigidos por la cátedra.

---

## 1. Criterios de Evaluación Obligatorios (Checklist de la Cátedra)

Toda documentación generada debe dar cuenta explícita y verificable de los siguientes **9 objetivos**:

1. **Modelo ER:** Entidades, atributos, claves primarias, cardinalidad y tipo de participación (total/parcial).
2. **Paso de ER a Modelo Relacional:** Transformación rigurosa, explicitando resolución de relaciones 1:N y N:M mediante tablas intermedias.
3. **Normalización hasta 3FN/BCNF:** Justificación formal de Dependencias Funcionales (DF), claves candidatas y eliminación de redundancias/anomalías.
4. **DDL Completo (PostgreSQL 16+):**
   - Claves primarias: `BIGINT GENERATED ALWAYS AS IDENTITY`.
   - Claves foráneas con políticas de integridad justificadas (`ON DELETE RESTRICT`, etc.).
   - Tipos de datos estrictos: `VARCHAR(n)`, `NUMERIC(10,2)` (sin floats), `TIMESTAMPTZ DEFAULT now()`, `JSONB`, `CREATE TYPE ... AS ENUM`.
   - Índices creados explícitamente (`CREATE INDEX`) con comentario justificativo de la consulta que optimizan.
5. **DML y Consultas Avanzadas:** Uso justificado de `JOIN`, funciones de agregación, subconsultas, `GROUP BY / HAVING` y **funciones de ventana** (`OVER (PARTITION BY ... ORDER BY ...)`).
6. **Vistas, Funciones y Procedimientos Almacenados (PL/pgSQL):**
   - Vistas estándar y Vistas Materializadas (`REFRESH MATERIALIZED VIEW`).
   - Procedimientos almacenados invocados con `CALL`, con manejo explícito de transacciones (`COMMIT` / `ROLLBACK` en su interior si aplica).
   - Funciones PL/pgSQL retornando valores o disparadas por triggers.
7. **Reglas de Negocio:**
   - Restricciones declarativas: al menos 1 `UNIQUE` y al menos 3 `CHECK` (ej. stock y precios no negativos).
   - Triggers avanzados en PL/pgSQL utilizando tablas de transición (`REFERENCING NEW TABLE / OLD TABLE`) o validaciones complejas.
8. **Transacciones y Concurrencia:**
   - Demostración de atomicidad, `COMMIT`, `ROLLBACK`.
   - Pruebas con distintos niveles de aislamiento (`READ COMMITTED`, `REPEATABLE READ`, `SERIALIZABLE`).
   - Control de anomalías (lecturas sucias, lecturas no repetibles, lecturas fantasma, serialización).
9. **Borrado Lógico (*Soft Delete*):**
   - Flag booleano (`activo BOOLEAN NOT NULL DEFAULT TRUE` / `fecha_baja`).
   - Demostración de su impacto e integración en consultas, vistas e índices parciales (`WHERE activo = TRUE`).

---

## 2. Estructura del Informe Técnico Consolidado

El informe técnico final debe seguir la estructura de los **5 ejes solicitados por la cátedra**:

### Sección 1: Elementos Implementados por Unidad
- **Unidad 1 (Integridad, Transacciones y Concurrencia):** Restricciones DDL, borrado lógico, triggers, scripts de concurrencia y aislamiento.
- **Unidad 2 (Optimización de Consultas):** Métricas basales, planes de ejecución (`EXPLAIN (ANALYZE, BUFFERS)`), diseño de índices específicos y reescritura de queries.
- **Unidad 3 (Índices, Vistas y Objetos Programables):** Vistas estándar y materializadas, procedimientos `CALL`, funciones PL/pgSQL, funciones de ventana.

### Sección 2: Metodología de Pruebas y Validación
- Entorno de ejecución (versión exacta de PostgreSQL, volumen del dataset generado con `seed.sql` / generador de registros).
- Procedimientos de prueba paso a paso para cada objeto de base de datos.
- Scripts de prueba transaccionales y escenarios de conflicto simulados.

### Sección 3: Resultados Obtenidos
- Tablas y capturas de salida de ejecución exitosa de procedimientos, triggers y restricciones.
- Verificación del comportamiento del motor ante violaciones de integridad referencial o de negocio.

### Sección 4: Comparativa de Optimización (Antes vs. Después)
Estandarizar en tablas Markdown los resultados de `EXPLAIN ANALYZE`:

| ID Consulta | Descripción | Costo Inicial (Plan) | Tiempo Inicial (ms) | Estrategia Aplicada (Índice / Reesctructuración) | Costo Final (Plan) | Tiempo Final (ms) | % Mejora Tiempo |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Q1** | Búsqueda por rango / cliente | ... | ... | Índice B-Tree / Parcial | ... | ... | ... |
| **Q2** | Agregación con ventana | ... | ... | Índice compuesto | ... | ... | ... |

### Sección 5: Declaración de Uso de IA (DUIA Unificado)
Integración de `DUIA_Parte1.md`, `DUIA_Parte2.md` y `DUIA_Parte3.md` detallando:
- Herramientas utilizadas (Gemini, ChatGPT, DeepSeek, etc.).
- Finalidad en cada etapa (generación de datasets, revisión sintáctica, propuestas de índices).
- **Decisiones críticas:** Qué sugerencias fueron aceptadas y cuáles fueron **descartadas o corregidas** con fundamento técnico.

---

## 3. Flujo de Trabajo para Construir la Documentación

Al invocar esta skill, el agente debe:

1. **Relevar las fuentes existentes:**
   - Inspeccionar `Proyecto_Integrador/database/` para asegurar concordancia entre el código SQL real y la documentación.
   - Leer los informes previos en `Proyecto_Integrador/documentos/` y carpetas `TP1/`, `TP2/`, `TP3/`.
2. **Ejecutar Matriz de Auditoría:** Validar que los 9 puntos del checklist estén cubiertos sin omisiones.
3. **Redactar el Documento Maestro:**
   - Generar el archivo consolidado en `Proyecto_Integrador/documentos/TPI_FoodStore_Informe_Consolidado.md`.
   - Utilizar diagramas Mermaid claros para el modelo ER y los flujos transaccionales.
   - Formatear bloques de código SQL con sintaxis coloreada y comentarios explicativos.
4. **Verificar Renderizado y Exportación:** Asegurar que el Markdown esté formateado limpiamente para su posterior conversión a PDF.
