# Ejercicio de Lectura Crítica — Parte 3 (TP2)

Este documento registra el análisis crítico, identificación de fallas y corrección de dos scripts generados por IA antes de su ejecución sobre bases de datos, cumpliendo con el protocolo de seguridad y lectura crítica de la cátedra.

---

## Análisis del Script 1

### Script Original:
```sql
-- Generado para: dar de baja las funciones de películas retiradas de cartel
-- (Adaptado al dominio Food Store: dar de baja productos sin stock)
UPDATE producto
SET activo = FALSE;
```

### 1. ¿Qué filas afectaría realmente tal como está escrito?
Afectaría al **100% de las filas** de la tabla `producto` (todos los registros existentes), cambiando el estado `activo` a `FALSE` masivamente en toda la base de datos.

### 2. ¿Por qué eso no coincide con la consigna que dice cumplir?
La consigna dictaba dar de baja registros específicos (por ejemplo, productos retirados o sin stock). Sin embargo, el script omite por completo la cláusula `WHERE`, lo que provoca una modificación destructiva global que inutiliza todo el catálogo de la tienda.

### 3. Versión Corregida:
Para cumplir con la consigna de manera segura, se debe incorporar un filtro `WHERE` explícito que acote la actualización únicamente a los productos que cumplen la condición de baja (por ejemplo, stock en cero o fecha de caducidad superada):
```sql
-- Versión corregida: Desactivar únicamente productos con stock cero
UPDATE producto
SET activo = FALSE
WHERE stock = 0 AND activo = TRUE;
```

---

## Análisis del Script 2

### Script Original:
```sql
-- Generado para: limpiar las categorías sin productos asociados
DELETE FROM categoria
WHERE id NOT IN (SELECT categoria_id FROM producto);
```

### 1. ¿Qué filas afectaría realmente tal como está escrito?
Dependiendo de los datos almacenados en la tabla `producto`, este script **puede no borrar ninguna fila** (comportamiento silencioso erróneo). Si la columna `categoria_id` en la tabla `producto` contiene al menos un valor `NULL`, la subconsulta `(SELECT categoria_id FROM producto)` incluirá `NULL`. En SQL, cualquier comparación con `NOT IN` frente a un conjunto que contenga un `NULL` evalúa a `UNKNOWN`, haciendo que la condición del `WHERE` falle para todas las filas y **ninguna categoría sea eliminada**, a pesar de existir categorías huérfanas.

### 2. ¿Por qué eso no coincide con la consigna que dice cumplir?
La consigna busca eliminar exclusivamente las categorías que no tienen ningún producto asociado. El uso de `NOT IN` frente a posibles valores nulos introduce un fallo lógico por lógica trivaluada de SQL que invalida la operación sin arrojar errores de sintaxis.

### 3. Versión Corregida:
La forma robusta y segura de realizar esta operación evitando problemas con valores `NULL` es utilizar `NOT EXISTS` con una subconsulta correlacionada:
```sql
-- Versión corregida: Eliminar categorías sin productos asociados de forma segura
DELETE FROM categoria c
WHERE NOT EXISTS (
    SELECT 1 
    FROM producto p 
    WHERE p.categoria_id = c.id
);
```
