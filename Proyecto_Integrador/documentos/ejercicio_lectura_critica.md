# Ejercicio de Lectura Crítica (TP2 - Parte 3)

**Proyecto:** Food Store (Base de Datos II)  
**Objetivo:** Analizar críticamente scripts generados por IA antes de su ejecución para evitar incidentes destructivos en bases de datos.

---

## 1. Análisis del Script 1

### Script Original
```sql
-- Generado para: dar de baja las funciones de películas retiradas de cartel
UPDATE funcion
SET activa = FALSE;
```

### Análisis y Efecto Real
- **¿Qué filas afectaría realmente tal como está escrito?**  
  Afectaría y desactivaría **absolutamente todas** las filas de la tabla `funcion` (o en el contexto de nuestro dominio, desactivaría todos los productos o registros de la tabla sin importar si están vigentes o no).
- **¿Por qué no coincide con la consigna?**  
  Carece completamente de una cláusula `WHERE` que filtre únicamente aquellos registros que cumplan la condición de "retirados de cartel" o vencidos. La ausencia del filtro convierte una operación específica en un borrado/desactivación masiva global.
- **Versión Corregida:**
  ```sql
  -- Corrección: Incluir la cláusula WHERE para afectar únicamente a los registros vencidos o retirados
  UPDATE funcion
  SET activa = FALSE
  WHERE fecha_funcion < CURRENT_DATE -- o la condición de vigencia correspondiente
    AND activa = TRUE;
  ```

---

## 2. Análisis del Script 2

### Script Original
```sql
-- Generado para: limpiar las categorías sin productos asociados
DELETE FROM categoria
WHERE id NOT IN (SELECT categoria_id FROM producto);
```

### Análisis y Efecto Real
- **¿Qué filas afectaría realmente tal como está escrito?**  
  Tal como está escrito, si la subconsulta `SELECT categoria_id FROM producto` devuelve **al menos un valor `NULL`** (por ejemplo, si hay un producto huérfano o un registro con `categoria_id IS NULL`), el operador `NOT IN` evaluará a `UNKNOWN` para todas las filas de la tabla `categoria`. Como resultado, **no se eliminará ninguna categoría** (o peor aún, según el motor y la lógica de subconsultas con nulos, puede comportarse de forma inesperada dejando la tabla intacta o vaciándola si se usa `NOT EXISTS` mal implementado). En SQL estándar, `NOT IN` con un solo `NULL` en la lista de resultados anula todo el predicado.
- **¿Por qué no coincide con la consigna?**  
  Falla en el manejo de valores `NULL` dentro de las subconsultas con `NOT IN`. La IA asumió que la subconsulta siempre devolvería un conjunto estricto de IDs válidos no nulos, ignorando el riesgo relacional.
- **Versión Corregida:**
  ```sql
  -- Corrección 1: Usando NOT EXISTS (forma recomendada y segura frente a NULLs)
  DELETE FROM categoria c
  WHERE NOT EXISTS (
      SELECT 1 
      FROM producto p 
      WHERE p.categoria_id = c.id
  );

  -- Corrección 2: Asegurando la exclusión explícita de NULLs si se usa NOT IN
  DELETE FROM categoria
  WHERE id NOT IN (
      SELECT categoria_id 
      FROM producto 
      WHERE categoria_id IS NOT NULL
  );
  ```
