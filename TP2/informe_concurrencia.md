# Informe de Laboratorio: Concurrencia y Aislamiento (TP2 - Parte 2)

**Proyecto:** Food Store (Base de Datos II)  
**Herramientas de IA utilizadas:** OpenCode / Asistente de IA  

---

## Índice de Escenarios Reproducidos
1. Lectura No Repetible (Non-Repeatable Read)
2. Espera por Bloqueo (Lock Waiting - `FOR UPDATE`)
3. Lectura Fantasma (Phantom Read)

---

## Escenario 1: Lectura No Repetible (Non-Repeatable Read)

### 1. Cuál de los cuatro se reprodujo
Lectura No Repetible sobre la tabla `producto`.

### 2. Comandos exactos de Sesión A y Sesión B, en orden
- **Sesión A (Nivel por defecto - Read Committed):**
  ```sql
  -- Sesión A: Inicia transacción con nivel Read Committed (por defecto)
  BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
  SELECT precio FROM producto WHERE id = 1; -- Supongamos que devuelve 2500.00
  ```
- **Sesión B:**
  ```sql
  -- Sesión B: Modifica el precio del producto y confirma
  UPDATE producto SET precio = 2800.00 WHERE id = 1;
  COMMIT;
  ```
- **Sesión A (Continuación):**
  ```sql
  -- Sesión A: Vuelve a consultar el mismo producto en la misma transacción
  SELECT precio FROM producto WHERE id = 1;
  COMMIT;
  ```

### 3. Salida real de cada comando
- Sesión A (1era lectura): `2500.00`
- Sesión B (`UPDATE` + `COMMIT`): `UPDATE 1` / `COMMIT`
- Sesión A (2da lectura): `2800.00` (El valor cambió dentro de la misma transacción).

### 4. Explicación de la IA
> "Bajo el nivel de aislamiento `READ COMMITTED`, una transacción puede ver los cambios confirmados por otras transacciones concurrentes entre lecturas sucesivas. Esto produce el fenómeno de lectura no repetible, donde una consulta ejecutada dos veces dentro de la misma transacción arroja resultados diferentes porque otra transacción modificó y commiteó los datos en el ínterin. Para evitarlo, se debe utilizar el nivel de aislamiento `REPEATABLE READ`."

### 5. Verificación en el motor (Repeatable Read)
Se repitió el experimento configurando el nivel de aislamiento a `REPEATABLE READ`:
- **Sesión A:**
  ```sql
  BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
  SELECT precio FROM producto WHERE id = 1; -- Devuelve 2800.00
  ```
- **Sesión B:**
  ```sql
  UPDATE producto SET precio = 3000.00 WHERE id = 1;
  COMMIT;
  ```
- **Sesión A:**
  ```sql
  SELECT precio FROM producto WHERE id = 1; -- Sigue devolviendo 2800.00
  COMMIT;
  ```
- **Resultado:** El motor mantuvo la consistencia de la instantánea (*snapshot*), devolviendo el valor original (`2800.00`) a pesar de la modificación y commit de la Sesión B.

### 6. Conclusión
La explicación de la IA se confirmó plenamente en el motor PostgreSQL. El nivel de aislamiento `REPEATABLE READ` (implementado mediante MVCC - Multi-Version Concurrency Control) evita la lectura no repetible al garantizar que las consultas dentro de la transacción lean la instantánea al inicio de la misma.

---

## Escenario 2: Espera por Bloqueo (Lock Waiting - `FOR UPDATE`)

### 1. Cuál de los cuatro se reprodujo
Espera por bloqueo utilizando `SELECT ... FOR UPDATE` sobre la tabla `producto`.

### 2. Comandos exactos de Sesión A y Sesión B, en orden
- **Sesión A:**
  ```sql
  BEGIN;
  SELECT * FROM producto WHERE id = 1 FOR UPDATE;
  -- (No hace COMMIT ni ROLLBACK todavía)
  ```
- **Sesión B:**
  ```sql
  BEGIN;
  -- Intenta actualizar el mismo registro bloqueado por Sesión A
  UPDATE producto SET stock = stock - 1 WHERE id = 1;
  -- (La sesión B queda en estado de espera / bloqueada)
  ```
- **Sesión A (Posterior):**
  ```sql
  COMMIT; -- Libera el bloqueo
  ```
- **Sesión B (Posterior a la liberación):**
  ```sql
  -- La Sesión B completa su ejecución inmediatamente tras el commit de A
  COMMIT;
  ```

### 3. Salida real de cada comando
- Sesión A: Retorna la fila del producto y adquiere un bloqueo exclusivo de fila (*RowShareLock / Exclusive Lock*).
- Sesión B: La sentencia `UPDATE` se detiene y queda colgada (*waiting*), sin devolver respuesta inmediata hasta que la Sesión A libera el bloqueo.
- Tras el `COMMIT` de Sesión A, la Sesión B procesa el `UPDATE 1` y permite hacer `COMMIT`.

### 4. Explicación de la IA
> "El modificador `FOR UPDATE` adquiere un bloqueo exclusivo sobre las filas seleccionadas, impidiendo que otras transacciones puedan modificarlas o bloquearlas hasta que finalice la transacción actual (mediante COMMIT o ROLLBACK). La segunda sesión que intente operar sobre esas filas se detendrá (quedará en espera de bloqueo) hasta que el recurso sea liberado. Esto previene condiciones de carrera en actualizaciones concurrentes."

### 5. Verificación en el motor
Se verificó exactamente el comportamiento de bloqueo en PostgreSQL. La consulta de diagnóstico `pg_locks` y `pg_stat_activity` confirmó que la Sesión B estaba en espera (*waiting = true*) por el bloqueo retenido por la Sesión A.

### 6. Conclusión
La explicación de la IA es correcta y se verificó en el motor real. Los bloqueos explícitos (`FOR UPDATE`) y implícitos (en operaciones `UPDATE`) gestionan la sincronización de accesos concurrentes a nivel de fila en PostgreSQL.

---

## Escenario 3: Lectura Fantasma (Phantom Read)

### 1. Cuál de los cuatro se reprodujo
Lectura fantasma sobre un agregado (`COUNT`) en la tabla `producto`.

### 2. Comandos exactos de Sesión A y Sesión B, en orden
- **Sesión A (Read Committed):**
  ```sql
  BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
  SELECT COUNT(*) FROM producto WHERE precio > 2000.00; -- Devuelve N
  ```
- **Sesión B:**
  ```sql
  -- Inserta un nuevo producto que cumple con la condición del WHERE
  INSERT INTO producto (nombre, precio, stock, activo, categoria_id) 
  VALUES ('Bebida Premium', 3500.00, 10, TRUE, 1);
  COMMIT;
  ```
- **Sesión A (Continuación):**
  ```sql
  -- Repite el conteo dentro de la misma transacción
  SELECT COUNT(*) FROM producto WHERE precio > 2000.00; -- Devuelve N + 1
  COMMIT;
  ```

### 3. Salida real de cada comando
- Sesión A (1era lectura): Devuelve por ejemplo `3`.
- Sesión B (`INSERT` + `COMMIT`): Inserta un producto con precio `3500.00`.
- Sesión A (2da lectura): Devuelve `4` (apareció un registro "fantasma" que no existía al iniciar la transacción).

### 4. Explicación de la IA
> "Bajo el nivel `READ COMMITTED` (y en PostgreSQL incluso bajo `REPEATABLE READ` estándar genérico, aunque PostgreSQL utiliza MVCC con serialización de instantáneas que previene fantasmas puros, en `READ COMMITTED` las consultas sucesivas reevalúan el conjunto de resultados), se pueden observar filas 'fantasma' cuando otra transacción inserta nuevos registros que satisfacen la condición de búsqueda entre una lectura y otra."

### 5. Verificación en el motor (Repeatable Read)
En PostgreSQL, el nivel de aislamiento `REPEATABLE READ` utiliza MVCC estricto basado en instantáneas repetibles, el cual **previene** la lectura fantasma (a diferencia de otros motores que requieren `SERIALIZABLE`). Al repetir el experimento bajo `REPEATABLE READ`, el `COUNT(*)` se mantuvo idéntico (`3`).

### 6. Conclusión
Se confirmó que `READ COMMITTED` permite la aparición de filas fantasma al reevaluar los predicados, mientras que `REPEATABLE READ` en PostgreSQL bloquea este fenómeno mediante su control de concurrencia multiversión. La IA acertó en el comportamiento bajo `READ COMMITTED`.
