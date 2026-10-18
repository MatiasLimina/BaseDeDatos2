# Pruebas manuales – TP4 (FNBC y desnormalización controlada)

Guía para verificar a mano, sobre la base `tp4_foodstore`, todo lo que implementan `TP4/tp_fnbc_control_lote.sql` y `TP4/tp_desnormalizacion_top_categorias.sql`. Cada prueba tiene objetivo, SQL/comando exacto, resultado esperado y una casilla `[ ]` para tildar.

**Cómo se verificaron los resultados esperados.** Los valores de este documento se obtuvieron el 2026-10-18 sobre `tp4_foodstore` (PostgreSQL 18.6) con consultas de lectura y con las mismas operaciones de escritura ejecutadas dentro de transacciones que se revirtieron. Los **importes y conteos** son los de esa base (250 002 pedidos, 771 201 detalles, 10 categorías, 1 756 filas en `ventas_diarias_categoria`); si regenerás los datos o pasó un día, cambian los números pero **no** la estructura del resultado. Donde el valor depende de la fecha se indica. La única prueba que no pudo ejecutarse de forma automática es la de concurrencia (prueba 27), porque necesita dos sesiones simultáneas: está descrita paso a paso y su resultado esperado se deduce del mecanismo de bloqueo de PostgreSQL (ver su nota).

---

## Prerrequisitos

1. **Apuntar a la base correcta.** Estas pruebas **solo** se ejecutan sobre `tp4_foodstore`. Nunca sobre `food_store` ni `food_store_copia`: los scripts hacen `DROP`/`TRUNCATE` de objetos propios y la parte 2 genera ~50 000 pedidos. Para confirmarlo, ya conectado:

   ```sql
   SELECT current_database();   -- debe devolver: tp4_foodstore
   ```

2. **Conexión con `psql`.** Desde la raíz del repositorio (`BaseDeDatos2/`). Agregá `-h`, `-p` y `-U` si tu servidor no es el local por defecto:

   ```bash
   psql -d tp4_foodstore
   ```

   `psql` **pide la contraseña** del usuario (no la escribas en archivos del repo). Para correr varios comandos seguidos sin que la pida cada vez, definila solo en esa terminal: en bash `export PGPASSWORD='...'`, en PowerShell `$env:PGPASSWORD = '...'`. Con pgAdmin o DBeaver: abrí una conexión a `tp4_foodstore` y usá **una sola pestaña de consultas por prueba** (las tablas temporales y `BEGIN ... ROLLBACK` viven en una sesión).

3. **Cómo ejecutar cada bloque.** Pegalo completo y ejecutalo como script (en `psql`, pegar; en pgAdmin, F5 y mirar solo el último resultado, por lo que conviene correr los pasos de a uno; en DBeaver, Alt+X). Los bloques con `BEGIN` terminan en `ROLLBACK`: **no dejan rastro**. Si una prueba falla a mitad de camino con una transacción abierta, ejecutá `ROLLBACK;` antes de seguir.

4. **Los datos de la parte 2 dependen del día.** Los pedidos de prueba se generan con la fecha del día en que se ejecutó el script 2. Antes de las pruebas 15 a 19, 23 a 25 y 28 verificá que hay datos de hoy:

   ```sql
   SELECT count(*) FROM ventas_diarias_categoria WHERE fecha = fn_dia_negocio(now());   -- esperado: 10
   ```

   Si devuelve 0 (pasó la medianoche, hora de Buenos Aires), volvé a correr el script 2 (prueba 2): genera los datos de hoy y reconstruye los totales. Quedan datos de días anteriores, no se pierden.

5. **Ayudantes de sesión para las pruebas de disparadores (20, 21, 22, 24, 26).** Ejecutalos **una vez por sesión**, antes de esas pruebas. Son tablas/vistas temporales: desaparecen al cerrar la sesión y no tocan el esquema.

   ```sql
   CREATE TEMP TABLE t_antes (LIKE ventas_diarias_categoria);

   -- t_delta = diferencias entre ventas_diarias_categoria y la foto guardada en t_antes
   CREATE TEMP VIEW t_delta AS
   SELECT COALESCE(v.fecha, a.fecha)               AS fecha,
          COALESCE(v.categoria_id, a.categoria_id) AS categoria_id,
          COALESCE(v.total_vendido, 0)   - COALESCE(a.total_vendido, 0)   AS delta_total,
          COALESCE(v.cantidad_lineas, 0) - COALESCE(a.cantidad_lineas, 0) AS delta_lineas
   FROM   ventas_diarias_categoria v
   FULL   JOIN t_antes a ON a.fecha = v.fecha AND a.categoria_id = v.categoria_id
   WHERE  v.total_vendido IS DISTINCT FROM a.total_vendido
      OR  v.cantidad_lineas IS DISTINCT FROM a.cantidad_lineas;
   ```

   Verificá además a qué categoría pertenecen los productos que usan las pruebas:

   ```sql
   SELECT id AS producto_id, categoria_id FROM producto WHERE id IN (10, 11, 12) ORDER BY id;
   ```

   Esperado: `10 -> 1` (Bebidas), `11 -> 2` (Snacks), `12 -> 3` (Lácteos). Si tus categorías son otras, ajustá los números de categoría esperados en las pruebas 20 a 22.

6. **Correr los tests automáticos de `TP4/tests/`** (prueba 3). Son bloques `DO $$ ... ASSERT ... $$`: si una aserción falla, `psql` muestra `ERROR` y, con `ON_ERROR_STOP`, termina con código distinto de 0.

---

## A. Carga de esquema y tests automáticos

### Prueba 1 – Script de la Parte 1 (FNBC): carga limpia y re-ejecución

- **Objetivo:** el script crea el esquema original, lo descompone, migra, crea la vista y verifica; y es idempotente (se puede correr dos veces).
- **Comando** (desde la raíz del repo; ejecutalo **dos veces seguidas**):

  ```bash
  psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f TP4/tp_fnbc_control_lote.sql
  psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f TP4/tp_fnbc_control_lote.sql
  echo "codigo de salida: $?"          # PowerShell: $LASTEXITCODE
  ```

- **Resultado esperado** (en las dos ejecuciones):
  - Ninguna línea `ERROR`; código de salida `0`. Pueden aparecer `NOTICE` de `DROP ... IF EXISTS` (inofensivos).
  - Tres resultados de `setval` (uno por secuencia: `503`, `31`, `802`).
  - Las consultas de verificación de la DF y los dos `EXCEPT` devuelven `(0 rows)`.
  - El conteo devuelve `filas_original = 3`, `filas_vista = 3`.
  - La demostración final (en `BEGIN ... ROLLBACK`) devuelve 2 filas: `501 | 30 | 801` y `501 | 30 | 900803`.
- [ ] Aprobada (1.ª ejecución)  [ ] Aprobada (2.ª ejecución)

### Prueba 2 – Script de la Parte 2 (desnormalización): carga y re-ejecución

- **Objetivo:** el script agrega `eliminado`, `fn_dia_negocio`, datos de prueba, tabla, disparadores, vistas y auditoría; y es idempotente.
- **Comando** (dos veces seguidas; recorre ~770 000 detalles, puede tardar varios segundos, no es un cuelgue):

  ```bash
  psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f TP4/tp_desnormalizacion_top_categorias.sql
  psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f TP4/tp_desnormalizacion_top_categorias.sql
  echo "codigo de salida: $?"
  ```

- **Resultado esperado:**
  - Ninguna línea `ERROR`; código de salida `0` en ambas.
  - Avisos benignos `NOTICE: column "eliminado" ... already exists, skipping` y `relation ... already exists, skipping`.
  - Si los datos de hoy ya estaban: `NOTICE:  datos de prueba ya cargados (137000 detalles vigentes hoy): no se inserta nada` (el número es el de la base del autor; debe ser >= 100000). Si es la primera vez del día, en cambio, el script inserta ~50 000 pedidos y no muestra ese aviso.
  - La consulta baseline (sección 3) y la consulta desnormalizada (sección 5) devuelven las **mismas 5 filas**: `Lácteos 190001983.35`, `Congelados 188996044.10`, `Golosinas 151840063.72`, `Panadería 150872583.56`, `Carnes 122887183.95` (valores de los datos del 2026-10-18).
  - La auditoría de la sección 6 devuelve `(0 rows)`.
  - **Advertencia:** correr este script **otro día** agrega otros ~50 000 pedidos y ~150 000 detalles (la guarda solo mira "hoy").
- [ ] Aprobada (1.ª ejecución)  [ ] Aprobada (2.ª ejecución)

### Prueba 3 – Suite de tests automáticos (14 archivos)

- **Objetivo:** todos los `TP4/tests/test_*.sql` pasan.
- **Comando** (cada archivo se ejecuta aparte para ver cuál falla):

  ```bash
  # bash
  for f in TP4/tests/test_*.sql; do
    echo "== $f"
    psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f "$f" || echo "FALLO: $f"
  done
  ```

  ```powershell
  # PowerShell
  Get-ChildItem TP4/tests/test_*.sql | ForEach-Object {
    Write-Host "== $($_.Name)"
    psql -v ON_ERROR_STOP=1 -d tp4_foodstore -f $_.FullName
    if ($LASTEXITCODE -ne 0) { Write-Host "FALLO: $($_.Name)" -ForegroundColor Red }
  }
  ```

- **Resultado esperado:** los 14 archivos terminan sin `ERROR` y sin la línea `FALLO:`. Cada uno imprime `DO` (y algunos `NOTICE: OK test_...`); los dos de disparadores muestran además `CREATE FUNCTION` y `DROP FUNCTION` de los ayudantes `t4_vdc_*`.
- **Limitación conocida (dependen del día):** `test_baja_logica.sql` considera "histórico" todo pedido con fecha anterior a `CURRENT_DATE - 1` y exige que ninguno esté eliminado, por lo que pasa el día en que se generaron los datos y el siguiente, y **falla desde el segundo día posterior** (porque los pedidos de prueba eliminados ya son "históricos"). `test_datos_prueba.sql` y `test_ventas_diarias_estructura.sql` necesitan datos del **día actual** (>= 100 000 detalles vigentes, 10 filas de hoy). No son fallas de los scripts.
- [ ] Aprobada (anotá cuántos archivos pasaron: ____ / 14)

---

## B. Parte 1 – FNBC

### Prueba 4 – Instancia original

- **Objetivo:** `control_lote_almacen` contiene exactamente la instancia de la consigna.
- **SQL:**

  ```sql
  SELECT * FROM control_lote_almacen ORDER BY lote_id;
  ```

- **Resultado esperado:** 3 filas: `501 | 30 | 801`, `502 | 30 | 801`, `503 | 31 | 802`.
- [ ] Aprobada

### Prueba 5 – La PK y las FK del esquema original rechazan datos inválidos

- **Objetivo:** PK `(lote_id, deposito_id)` y FK con `ON DELETE RESTRICT`.
- **SQL** (cada `INSERT` falla y deja la transacción abortada; cerrá con `ROLLBACK` antes del siguiente):

  ```sql
  BEGIN;
  INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id) VALUES (501, 30, 802);
  ROLLBACK;

  BEGIN;
  INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id) VALUES (999999, 30, 801);
  ROLLBACK;
  ```

- **Resultado esperado:**
  - 1.º: `ERROR: ... unique constraint "pk_control_lote_almacen"` (en un servidor en español: "llave duplicada viola restricción de unicidad").
  - 2.º: `ERROR: ... foreign key constraint "fk_cla_lote"`.
  - El texto exacto depende del idioma del servidor; lo que se verifica es el **nombre de la restricción**.
- [ ] Aprobada

### Prueba 6 – Violación de FNBC: la DF `R → D` con `R` no superclave

- **Objetivo:** mostrar con datos que `ResponsableControlID → DepositoID` se cumple pero `ResponsableControlID` no es clave (por eso el esquema no está en FNBC).
- **SQL:**

  ```sql
  -- (a) R determina D: cada responsable aparece con UN solo depósito
  SELECT responsable_control_id, count(DISTINCT deposito_id) AS depositos
  FROM control_lote_almacen GROUP BY 1 ORDER BY 1;

  -- (b) pero R NO es superclave: se repite en varias filas
  SELECT responsable_control_id, count(*) AS filas
  FROM control_lote_almacen GROUP BY 1 HAVING count(*) > 1;

  -- (c) la única clave declarada es (lote_id, deposito_id)
  SELECT pg_get_constraintdef(oid) FROM pg_constraint
  WHERE conrelid = 'control_lote_almacen'::regclass AND contype = 'p';
  ```

- **Resultado esperado:** (a) `801 | 1` y `802 | 1`; (b) una fila: `801 | 2`; (c) `PRIMARY KEY (lote_id, deposito_id)`. Conclusión: `R → D` vale, `R` se repite (no es superclave) y por lo tanto el determinante de una DF no trivial no es superclave: viola FNBC.
- [ ] Aprobada

### Prueba 7 – Anomalía de inserción (original) y su solución (descompuesto)

- **Objetivo:** en el esquema original no se puede registrar a un responsable sin lote y se puede contradecir `R → D`; en el descompuesto no.
- **SQL:**

  ```sql
  BEGIN;
  INSERT INTO usuario (id, nombre, apellido) OVERRIDING SYSTEM VALUE VALUES (900803, 'Responsable', 'Ochocientos Tres');

  -- (a) original: registrar que 900803 trabaja en el depósito 30 sin lote es imposible
  INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id) VALUES (NULL, 30, 900803);
  ROLLBACK;

  BEGIN;
  -- (b) original: se acepta que 801 (depósito 30) figure también en el 31, contradiciendo R -> D
  INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id) VALUES (501, 31, 801);
  SELECT responsable_control_id, count(DISTINCT deposito_id) AS depositos
  FROM control_lote_almacen GROUP BY 1 HAVING count(DISTINCT deposito_id) > 1;
  ROLLBACK;

  BEGIN;
  INSERT INTO usuario (id, nombre, apellido) OVERRIDING SYSTEM VALUE VALUES (900803, 'Responsable', 'Ochocientos Tres');
  -- (c) descompuesto: se registra al responsable sin lotes
  INSERT INTO responsable_deposito (responsable_control_id, deposito_id) VALUES (900803, 30);
  SELECT * FROM responsable_deposito WHERE responsable_control_id = 900803;
  -- (d) descompuesto: 801 en el depósito 31 se rechaza
  INSERT INTO responsable_deposito (responsable_control_id, deposito_id) VALUES (801, 31);
  ROLLBACK;
  ```

- **Resultado esperado:** (a) `ERROR: null value in column "lote_id" ... violates not-null constraint`; (b) `INSERT 0 1` y la consulta devuelve `801 | 2` (la contradicción entró sin error); (c) `INSERT 0 1` y devuelve la fila `900803 | 30`; (d) `ERROR: ... unique constraint "pk_responsable_deposito"`.
- [ ] Aprobada

### Prueba 8 – Anomalía de borrado

- **Objetivo:** en el original, borrar el último control de un responsable borra el hecho "802 pertenece al depósito 31"; en el descompuesto el hecho se conserva.
- **SQL:**

  ```sql
  BEGIN;
  DELETE FROM control_lote_almacen WHERE lote_id = 503;
  SELECT count(*) AS filas_de_802_en_original FROM control_lote_almacen WHERE responsable_control_id = 802;
  ROLLBACK;

  BEGIN;
  DELETE FROM control_lote WHERE lote_id = 503;
  SELECT deposito_id AS deposito_de_802_en_descompuesto FROM responsable_deposito WHERE responsable_control_id = 802;
  ROLLBACK;
  ```

- **Resultado esperado:** primero `0` (el dato "802 → depósito 31" se perdió); después `31` (se conserva).
- [ ] Aprobada

### Prueba 9 – Anomalía de actualización

- **Objetivo:** trasladar al responsable 801 del depósito 30 al 31: en el original hay que tocar varias filas (y si se toca una sola queda inconsistente); en el descompuesto se modifica una fila.
- **SQL:**

  ```sql
  BEGIN;
  UPDATE control_lote_almacen SET deposito_id = 31 WHERE lote_id = 501 AND responsable_control_id = 801;   -- solo una de las dos filas de 801
  SELECT responsable_control_id, count(DISTINCT deposito_id) AS depositos
  FROM control_lote_almacen GROUP BY 1 HAVING count(DISTINCT deposito_id) > 1;
  ROLLBACK;

  BEGIN;
  UPDATE responsable_deposito SET deposito_id = 31 WHERE responsable_control_id = 801;
  SELECT lote_id, deposito_id, responsable_control_id FROM v_control_lote_almacen
  WHERE responsable_control_id = 801 ORDER BY lote_id;
  ROLLBACK;
  ```

- **Resultado esperado:** 1.º: `UPDATE 1` y la consulta devuelve `801 | 2` (inconsistente: 801 aparece en dos depósitos). 2.º: `UPDATE 1` (una sola fila) y la vista devuelve `501 | 31 | 801` y `502 | 31 | 801` (los dos lotes siguen al responsable).
- [ ] Aprobada

### Prueba 10 – Descomposición: estructura y rechazos

- **Objetivo:** `responsable_deposito` y `control_lote` tienen las claves y FK `RESTRICT` previstas y rechazan lo inválido.
- **SQL:**

  ```sql
  SELECT conrelid::regclass AS tabla, conname, pg_get_constraintdef(oid) AS definicion
  FROM pg_constraint
  WHERE conrelid IN ('responsable_deposito'::regclass, 'control_lote'::regclass) AND contype IN ('p','f')
  ORDER BY conrelid::regclass::text, contype DESC, conname;

  BEGIN; INSERT INTO control_lote (lote_id, responsable_control_id) VALUES (501, 999999); ROLLBACK;
  BEGIN; DELETE FROM deposito WHERE id = 30; ROLLBACK;
  BEGIN; DELETE FROM lote WHERE id = 501; ROLLBACK;
  ```

- **Resultado esperado:**
  - La consulta devuelve 6 filas: `control_lote`: `pk_control_lote PRIMARY KEY (lote_id, responsable_control_id)`, `fk_cl_lote` y `fk_cl_responsable` (esta apunta a `responsable_deposito(responsable_control_id)`); `responsable_deposito`: `pk_responsable_deposito PRIMARY KEY (responsable_control_id)`, `fk_rd_deposito`, `fk_rd_responsable`. Todas las FK terminan en `ON DELETE RESTRICT`.
  - `INSERT` de un responsable inexistente: `ERROR: ... foreign key constraint "fk_cl_responsable"`.
  - `DELETE` del depósito 30 y del lote 501: `ERROR: update or delete on table ... violates RESTRICT setting of foreign key constraint ...` (el nombre que menciona puede ser `fk_cla_deposito`/`fk_cla_lote`, de la tabla original que sigue existiendo, o `fk_rd_deposito`/`fk_cl_lote`: PostgreSQL informa la primera que evalúa; lo que importa es que se rechaza).
- [ ] Aprobada

### Prueba 11 – Migración y vista de compatibilidad (`EXCEPT` en ambos sentidos y conteos)

- **Objetivo:** la vista `v_control_lote_almacen` reconstruye exactamente la tabla original.
- **SQL:**

  ```sql
  SELECT lote_id, deposito_id, responsable_control_id FROM control_lote_almacen
  EXCEPT
  SELECT lote_id, deposito_id, responsable_control_id FROM v_control_lote_almacen;

  SELECT lote_id, deposito_id, responsable_control_id FROM v_control_lote_almacen
  EXCEPT
  SELECT lote_id, deposito_id, responsable_control_id FROM control_lote_almacen;

  SELECT (SELECT count(*) FROM control_lote_almacen)   AS filas_original,
         (SELECT count(*) FROM v_control_lote_almacen) AS filas_vista,
         (SELECT count(*) FROM responsable_deposito)   AS filas_responsable_deposito,
         (SELECT count(*) FROM control_lote)           AS filas_control_lote;

  SELECT * FROM v_control_lote_almacen ORDER BY lote_id;
  ```

- **Resultado esperado:** los dos `EXCEPT` devuelven `(0 rows)`; el conteo devuelve `3 | 3 | 2 | 3`; la vista devuelve `501 | 30 | 801`, `502 | 30 | 801`, `503 | 31 | 802`.
- [ ] Aprobada

### Prueba 12 – La dependencia `{Lote, Depósito} → Responsable` no se preserva

- **Objetivo:** demostrar el costo de FNBC: el esquema descompuesto acepta dos responsables para el mismo `(lote, depósito)`, cosa que la PK original impedía.
- **SQL:**

  ```sql
  BEGIN;
  INSERT INTO usuario (id, nombre, apellido) OVERRIDING SYSTEM VALUE VALUES (900803, 'Responsable', 'Ochocientos Tres');
  INSERT INTO responsable_deposito (responsable_control_id, deposito_id) VALUES (900803, 30);
  INSERT INTO control_lote (lote_id, responsable_control_id) VALUES (501, 900803);   -- aceptado
  SELECT * FROM v_control_lote_almacen WHERE lote_id = 501 ORDER BY responsable_control_id;
  -- en el esquema original la PK lo rechaza:
  INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id) VALUES (501, 30, 900803);
  ROLLBACK;
  ```

- **Resultado esperado:** el 3.º `INSERT` termina en `INSERT 0 1`; la vista devuelve dos filas: `501 | 30 | 801` y `501 | 30 | 900803`; el último `INSERT` (tabla original) falla con `ERROR: ... unique constraint "pk_control_lote_almacen"`.
- [ ] Aprobada

---

## C. Parte 2 – Base: baja lógica, día de negocio y datos

### Prueba 13 – `eliminado` por defecto, `NOT NULL`

- **Objetivo:** `pedido.eliminado` y `pedido_detalle.eliminado` son `BOOLEAN NOT NULL DEFAULT false`.
- **SQL:**

  ```sql
  SELECT table_name, column_name, data_type, is_nullable, column_default
  FROM information_schema.columns
  WHERE table_schema = 'public' AND column_name = 'eliminado' AND table_name IN ('pedido','pedido_detalle')
  ORDER BY table_name;

  BEGIN;
  INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now(), 'EFECTIVO', (SELECT min(id) FROM cliente))
  RETURNING id, eliminado;
  UPDATE pedido SET eliminado = NULL WHERE id = currval(pg_get_serial_sequence('pedido', 'id'));
  ROLLBACK;
  ```

- **Resultado esperado:** la consulta devuelve 2 filas (`pedido` y `pedido_detalle`): `boolean | NO | false`. El `INSERT ... RETURNING` devuelve `eliminado = f`. El `UPDATE ... = NULL` falla con `ERROR: null value in column "eliminado" ... violates not-null constraint`.
- [ ] Aprobada

### Prueba 14 – Día de negocio independiente de la zona horaria de la sesión

- **Objetivo:** `fn_dia_negocio` usa `America/Argentina/Buenos_Aires` y es `IMMUTABLE`.
- **SQL:**

  ```sql
  BEGIN;
  SET LOCAL TimeZone = 'UTC';
  SELECT fn_dia_negocio('2026-10-18 23:30-03'::timestamptz) AS con_sesion_utc,
         ('2026-10-18 23:30-03'::timestamptz AT TIME ZONE 'UTC')::date AS sin_la_funcion;
  SET LOCAL TimeZone = 'America/Argentina/Buenos_Aires';
  SELECT fn_dia_negocio('2026-10-18 23:30-03'::timestamptz) AS con_sesion_ba;
  ROLLBACK;

  SELECT provolatile FROM pg_proc WHERE proname = 'fn_dia_negocio';
  ```

- **Resultado esperado:** `con_sesion_utc = 2026-10-18` y `sin_la_funcion = 2026-10-19` (por eso hace falta la función: a las 23:30 de Buenos Aires ya es el día siguiente en UTC); `con_sesion_ba = 2026-10-18`; `provolatile = i` (immutable).
- [ ] Aprobada

### Prueba 15 – Datos de prueba del día

- **Objetivo:** hay >= 8 categorías con ventas hoy, >= 100 000 detalles vigentes de hoy y pedidos/detalles eliminados.
- **SQL:**

  ```sql
  SELECT (SELECT count(*) FROM categoria)                   AS categorias,
         count(DISTINCT p.id)                               AS pedidos_hoy,
         count(DISTINCT p.id) FILTER (WHERE p.eliminado)    AS pedidos_eliminados,
         count(*) FILTER (WHERE NOT d.eliminado AND NOT p.eliminado) AS detalles_vigentes,
         count(*) FILTER (WHERE d.eliminado)                AS detalles_eliminados
  FROM   pedido_detalle d JOIN pedido p ON p.id = d.pedido_id
  WHERE  p.fecha >= (fn_dia_negocio(now())::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires')
    AND  p.fecha <  (fn_dia_negocio(now())::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires') + INTERVAL '1 day';
  ```

- **Resultado esperado** (base del autor): `10 | 50000 | 2500 | 137000 | 6000`. Criterio de aprobación: `categorias >= 8`, `detalles_vigentes >= 100000`, `pedidos_eliminados > 0` y `detalles_eliminados > 0`.
- [ ] Aprobada

### Prueba 16 – Estructura de `ventas_diarias_categoria` y consistencia de la carga inicial

- **Objetivo:** PK `(fecha, categoria_id)`, FK `RESTRICT`, CHECKs no negativos, y la tabla tiene tantas filas como grupos (día, categoría) tiene la fuente.
- **SQL:**

  ```sql
  SELECT conname, contype, pg_get_constraintdef(oid) AS definicion
  FROM pg_constraint
  WHERE conrelid = 'ventas_diarias_categoria'::regclass AND contype IN ('p','f','c')
  ORDER BY contype DESC, conname;

  SELECT (SELECT count(*) FROM ventas_diarias_categoria) AS filas_tabla,
         (SELECT count(*) FROM (SELECT 1
                                FROM pedido_detalle d JOIN pedido p ON p.id = d.pedido_id JOIN producto pr ON pr.id = d.producto_id
                                WHERE NOT p.eliminado AND NOT d.eliminado
                                GROUP BY fn_dia_negocio(p.fecha), pr.categoria_id) g) AS grupos_fuente;

  BEGIN;
  UPDATE ventas_diarias_categoria SET total_vendido = -1
  WHERE fecha = fn_dia_negocio(now()) AND categoria_id = 1;
  ROLLBACK;
  ```

- **Resultado esperado:** la 1.ª consulta devuelve 4 filas: `pk_ventas_diarias_categoria PRIMARY KEY (fecha, categoria_id)`, `fk_vdc_categoria ... REFERENCES categoria(id) ON DELETE RESTRICT`, `chk_vdc_lineas_no_negativo CHECK ((cantidad_lineas >= 0))` y `chk_vdc_total_no_negativo CHECK ((total_vendido >= (0)::numeric))`. La 2.ª devuelve dos números **iguales** (`1756 | 1756` en la base del autor). El `UPDATE` falla con `ERROR: ... violates check constraint "chk_vdc_total_no_negativo"`.
- [ ] Aprobada

---

## D. Consulta top 5 y medición

### Prueba 17 – Top 5 desnormalizado = top 5 normalizado

- **Objetivo:** el reporte desde `ventas_diarias_categoria` (vista `v_top5_categorias_dia`) devuelve lo mismo que la consulta original.
- **SQL:**

  ```sql
  -- (a) consulta normalizada (baseline)
  SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido
  FROM   pedido_detalle dp
  JOIN   pedido    ped ON ped.id = dp.pedido_id
  JOIN   producto  pr  ON pr.id  = dp.producto_id
  JOIN   categoria c   ON c.id   = pr.categoria_id
  WHERE  ped.fecha >= (fn_dia_negocio(now())::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires')
    AND  ped.fecha <  (fn_dia_negocio(now())::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires') + INTERVAL '1 day'
    AND  ped.eliminado = FALSE AND dp.eliminado = FALSE
  GROUP  BY c.nombre ORDER BY total_vendido DESC, c.nombre LIMIT 5;

  -- (b) consulta desnormalizada
  SELECT c.nombre AS categoria, v.total_vendido
  FROM   ventas_diarias_categoria v JOIN categoria c ON c.id = v.categoria_id
  WHERE  v.fecha = fn_dia_negocio(now())
  ORDER  BY v.total_vendido DESC, c.nombre LIMIT 5;

  -- (c) diferencia en ambos sentidos
  (SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido
   FROM pedido_detalle dp JOIN pedido ped ON ped.id = dp.pedido_id JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id
   WHERE ped.fecha >= (fn_dia_negocio(now())::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires')
     AND ped.fecha <  (fn_dia_negocio(now())::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires') + INTERVAL '1 day'
     AND ped.eliminado = FALSE AND dp.eliminado = FALSE
   GROUP BY c.nombre ORDER BY total_vendido DESC, c.nombre LIMIT 5)
  EXCEPT SELECT categoria, total_vendido FROM v_top5_categorias_dia;

  SELECT categoria, total_vendido FROM v_top5_categorias_dia
  EXCEPT
  (SELECT c.nombre, SUM(dp.subtotal)
   FROM pedido_detalle dp JOIN pedido ped ON ped.id = dp.pedido_id JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id
   WHERE ped.fecha >= (fn_dia_negocio(now())::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires')
     AND ped.fecha <  (fn_dia_negocio(now())::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires') + INTERVAL '1 day'
     AND ped.eliminado = FALSE AND dp.eliminado = FALSE
   GROUP BY c.nombre ORDER BY SUM(dp.subtotal) DESC, c.nombre LIMIT 5);
  ```

- **Resultado esperado:** (a) y (b) devuelven las mismas 5 filas en el mismo orden: `Lácteos 190001983.35`, `Congelados 188996044.10`, `Golosinas 151840063.72`, `Panadería 150872583.56`, `Carnes 122887183.95` (datos del 2026-10-18); (c) las dos consultas `EXCEPT` devuelven `(0 rows)`. Nota: `Perfumería 122872504.68` queda 6.ª por solo 14 678,67 de diferencia con `Carnes`.
- [ ] Aprobada

### Prueba 18 – `EXPLAIN (ANALYZE, BUFFERS)` ANTES (consulta normalizada)

- **Objetivo:** medir el costo de la consulta original.
- **SQL** (ejecutala **3 veces seguidas** y anotá `Execution Time`):

  ```sql
  EXPLAIN (ANALYZE, BUFFERS)
  SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido
  FROM   pedido_detalle dp
  JOIN   pedido    ped ON ped.id = dp.pedido_id
  JOIN   producto  pr  ON pr.id  = dp.producto_id
  JOIN   categoria c   ON c.id   = pr.categoria_id
  WHERE  ped.fecha >= (fn_dia_negocio(now())::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires')
    AND  ped.fecha <  (fn_dia_negocio(now())::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires') + INTERVAL '1 day'
    AND  ped.eliminado = FALSE AND dp.eliminado = FALSE
  GROUP  BY c.nombre ORDER BY total_vendido DESC, c.nombre LIMIT 5;
  ```

- **Resultado esperado:** el plan incluye `Parallel Seq Scan on pedido_detalle dp` (recorre toda la tabla, ~771 000 filas), `Hash Join` con un `Seq Scan` de `producto` y `Bitmap Index Scan on idx_pedido_fecha` para `pedido`; `Execution Time` de referencia **~140 ms** (el autor midió 141,857 / 138,899 / 142,337 ms) y del orden de 11 000 buffers. **Los tiempos dependen del equipo, del caché y de la carga**: en otra máquina pueden ser distintos. Criterio de aprobación: el nodo dominante es el `Seq Scan` de `pedido_detalle` y el tiempo es del orden de decenas a pocos cientos de ms.
- [ ] Aprobada   Tiempos obtenidos: ______ / ______ / ______ ms

### Prueba 19 – `EXPLAIN (ANALYZE, BUFFERS)` DESPUÉS (consulta desnormalizada)

- **Objetivo:** medir el costo del reporte desde `ventas_diarias_categoria`.
- **SQL** (3 veces seguidas):

  ```sql
  EXPLAIN (ANALYZE, BUFFERS)
  SELECT c.nombre AS categoria, v.total_vendido
  FROM   ventas_diarias_categoria v
  JOIN   categoria c ON c.id = v.categoria_id
  WHERE  v.fecha = fn_dia_negocio(now())
  ORDER  BY v.total_vendido DESC, c.nombre
  LIMIT  5;
  ```

- **Resultado esperado:** el plan usa `Bitmap Index Scan on pk_ventas_diarias_categoria` (o `Index Scan`) y devuelve 10 filas antes del `LIMIT`; `Buffers: shared hit=13`; `Execution Time` de referencia **~0,1 ms** (el autor midió 0,104 / 0,100 / 0,101 ms; una medición posterior dio 0,118 ms). **Depende del equipo**. Criterio de aprobación: no hay `Seq Scan` de `pedido_detalle`, el tiempo es menor que ~1 ms y es **al menos ~100 veces menor** que el de la prueba 18.
- [ ] Aprobada   Tiempos obtenidos: ______ / ______ / ______ ms

---

## E. Disparadores

Todas estas pruebas usan los ayudantes del prerrequisito 5 y terminan en `ROLLBACK`. En cada paso, `t_delta` muestra **qué cambió** en `ventas_diarias_categoria` respecto de la foto inicial. "Hoy" es `fn_dia_negocio(now())`.

### Prueba 20 – Disparador de `pedido_detalle`: alta, modificación, cambio de producto, baja lógica, reactivación y borrado

- **Objetivo:** cada operación sobre un detalle ajusta el total en la misma transacción.
- **SQL** (ejecutá el bloque entero; o paso a paso sin cerrar la transacción):

  ```sql
  BEGIN;
  DELETE FROM t_antes;
  INSERT INTO t_antes SELECT * FROM ventas_diarias_categoria;

  -- Paso 1: alta de un detalle de 100.00 (producto 10, categoría 1)
  INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now(), 'EFECTIVO', (SELECT min(id) FROM cliente));
  INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
  VALUES (currval(pg_get_serial_sequence('pedido', 'id')), 10, 1, 100.00, 100.00);
  SELECT * FROM t_delta ORDER BY fecha, categoria_id;

  -- Paso 2: el subtotal pasa de 100.00 a 250.00
  UPDATE pedido_detalle SET subtotal = 250.00, precio_unitario = 250.00
  WHERE pedido_id = currval(pg_get_serial_sequence('pedido', 'id')) AND producto_id = 10;
  SELECT * FROM t_delta ORDER BY fecha, categoria_id;

  -- Paso 3: el detalle cambia al producto 11 (categoría 2)
  UPDATE pedido_detalle SET producto_id = 11
  WHERE pedido_id = currval(pg_get_serial_sequence('pedido', 'id')) AND producto_id = 10;
  SELECT * FROM t_delta ORDER BY fecha, categoria_id;

  -- Paso 4: baja lógica del detalle
  UPDATE pedido_detalle SET eliminado = TRUE
  WHERE pedido_id = currval(pg_get_serial_sequence('pedido', 'id')) AND producto_id = 11;
  SELECT * FROM t_delta ORDER BY fecha, categoria_id;

  -- Paso 5: reactivación
  UPDATE pedido_detalle SET eliminado = FALSE
  WHERE pedido_id = currval(pg_get_serial_sequence('pedido', 'id')) AND producto_id = 11;
  SELECT * FROM t_delta ORDER BY fecha, categoria_id;

  -- Paso 6: borrado físico del detalle
  DELETE FROM pedido_detalle
  WHERE pedido_id = currval(pg_get_serial_sequence('pedido', 'id')) AND producto_id = 11;
  SELECT * FROM t_delta ORDER BY fecha, categoria_id;

  -- Paso 7: la auditoría sigue vacía
  SELECT count(*) AS filas_auditoria FROM v_auditoria_ventas_diarias;
  ROLLBACK;
  ```

- **Resultado esperado** (columnas `fecha | categoria_id | delta_total | delta_lineas`):
  1. una fila: `hoy | 1 | 100.00 | 1`
  2. una fila: `hoy | 1 | 250.00 | 1` (el total subió 150.00 más sobre el paso anterior)
  3. una fila: `hoy | 2 | 250.00 | 1` (la categoría 1 vuelve a su valor original y deja de aparecer; la 2 gana la línea)
  4. `(0 rows)` (la baja lógica resta la línea)
  5. una fila: `hoy | 2 | 250.00 | 1` (la reactivación la devuelve)
  6. `(0 rows)`
  7. `filas_auditoria = 0`
- [ ] Aprobada

### Prueba 21 – Disparador de `pedido`: baja lógica, reactivación y cambio de fecha

- **Objetivo:** dar de baja un pedido descuenta todos sus detalles vigentes (en cada categoría); cambiar su fecha los mueve de día.
- **SQL:**

  ```sql
  BEGIN;
  DELETE FROM t_antes;
  INSERT INTO t_antes SELECT * FROM ventas_diarias_categoria;

  -- Paso 1: pedido de hoy con dos detalles en dos categorías
  INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now(), 'EFECTIVO', (SELECT min(id) FROM cliente));
  INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
  VALUES (currval(pg_get_serial_sequence('pedido', 'id')), 10, 1, 100.00, 100.00),
         (currval(pg_get_serial_sequence('pedido', 'id')), 11, 1,  50.00,  50.00);
  SELECT * FROM t_delta ORDER BY fecha, categoria_id;

  -- Paso 2: baja lógica del pedido
  UPDATE pedido SET eliminado = TRUE WHERE id = currval(pg_get_serial_sequence('pedido', 'id'));
  SELECT * FROM t_delta ORDER BY fecha, categoria_id;

  -- Paso 3: reactivación
  UPDATE pedido SET eliminado = FALSE WHERE id = currval(pg_get_serial_sequence('pedido', 'id'));
  SELECT * FROM t_delta ORDER BY fecha, categoria_id;

  -- Paso 4: el pedido pasa a ayer (fecha - 1 día)
  UPDATE pedido SET fecha = fecha - INTERVAL '1 day' WHERE id = currval(pg_get_serial_sequence('pedido', 'id'));
  SELECT * FROM t_delta ORDER BY fecha, categoria_id;

  -- Paso 5: la auditoría sigue vacía
  SELECT count(*) AS filas_auditoria FROM v_auditoria_ventas_diarias;
  ROLLBACK;
  ```

- **Resultado esperado:**
  1. dos filas: `hoy | 1 | 100.00 | 1` y `hoy | 2 | 50.00 | 1`
  2. `(0 rows)` (la baja lógica del pedido resta ambas líneas)
  3. las mismas dos filas del paso 1
  4. dos filas con la fecha de **ayer** (`hoy - 1`): `ayer | 1 | 100.00 | 1` y `ayer | 2 | 50.00 | 1` (las filas de "hoy" desaparecen del delta: volvieron a su valor original)
  5. `filas_auditoria = 0`
- [ ] Aprobada

### Prueba 22 – Disparador de `producto`: recategorización con ventas en varios días

- **Objetivo:** cambiar la categoría de un producto mueve, en todos los días con ventas, el monto de la categoría vieja a la nueva.
- **SQL:**

  ```sql
  -- Valores esperados de antemano: ventas vigentes del producto 10 (categoría 1) y días involucrados
  SELECT sum(d.subtotal) AS total_producto, count(*) AS lineas, count(DISTINCT fn_dia_negocio(p.fecha)) AS dias
  FROM   pedido_detalle d JOIN pedido p ON p.id = d.pedido_id
  WHERE  d.producto_id = 10 AND NOT d.eliminado AND NOT p.eliminado;

  BEGIN;
  DELETE FROM t_antes;
  INSERT INTO t_antes SELECT * FROM ventas_diarias_categoria;

  UPDATE producto SET categoria_id = 3 WHERE id = 10;       -- de Bebidas (1) a Lácteos (3)

  SELECT categoria_id, sum(delta_total) AS delta_total, sum(delta_lineas) AS delta_lineas, count(*) AS dias
  FROM   t_delta GROUP BY categoria_id ORDER BY categoria_id;

  SELECT count(*) AS filas_auditoria FROM v_auditoria_ventas_diarias;
  ROLLBACK;
  ```

- **Resultado esperado** (base del autor): la 1.ª consulta devuelve `22349.10 | 8 | 6`. Luego `UPDATE 1` y el resumen devuelve dos filas: `1 | -22349.10 | -8 | 6` y `3 | 22349.10 | 8 | 6` (lo que pierde la categoría 1 lo gana la 3, en los mismos 6 días). `filas_auditoria = 0`. En otra base, los números de la 1.ª consulta son los que deben aparecer (con signo opuesto en la categoría de origen).
- [ ] Aprobada

---

## F. Auditoría

### Prueba 23 – Auditoría vacía en una base sincronizada (antes)

- **Objetivo:** la vista `v_auditoria_ventas_diarias` recalcula desde la fuente y no encuentra diferencias.
- **SQL:**

  ```sql
  SELECT * FROM v_auditoria_ventas_diarias ORDER BY fecha, categoria_id;
  ```

- **Resultado esperado:** `(0 rows)` (recorre todo el histórico; tarda un par de segundos).
- [ ] Aprobada

### Prueba 24 – La auditoría detecta una alteración manual

- **Objetivo:** si alguien modifica o borra una fila de `ventas_diarias_categoria` a mano, la auditoría lo informa.
- **SQL:**

  ```sql
  BEGIN;
  -- (a) total alterado en +1.00
  UPDATE ventas_diarias_categoria SET total_vendido = total_vendido + 1.00
  WHERE fecha = fn_dia_negocio(now()) AND categoria_id = 1;
  SELECT * FROM v_auditoria_ventas_diarias ORDER BY fecha, categoria_id;

  -- (b) además, una fila borrada
  DELETE FROM ventas_diarias_categoria WHERE fecha = fn_dia_negocio(now()) AND categoria_id = 2;
  SELECT * FROM v_auditoria_ventas_diarias ORDER BY fecha, categoria_id;
  ROLLBACK;

  SELECT count(*) AS filas_auditoria_tras_rollback FROM v_auditoria_ventas_diarias;
  ```

- **Resultado esperado** (importes del 2026-10-18; columnas `fecha | categoria_id | total_fuente | total_tabla | lineas_fuente | lineas_tabla`):
  - (a) una fila: `hoy | 1 | 83107897.56 | 83107898.56 | 15000 | 15000` (`total_tabla = total_fuente + 1.00`);
  - (b) dos filas: la anterior y `hoy | 2 | 30069120.34 | NULL | 11001 | NULL` (la fila falta en la tabla);
  - tras el `ROLLBACK`: `filas_auditoria_tras_rollback = 0`.
- [ ] Aprobada

### Prueba 25 – Auditoría vacía después de todas las pruebas

- **Objetivo:** tras ejecutar las pruebas 20 a 22, 24, 26 y 28 (todas revertidas) la base sigue sincronizada.
- **SQL:**

  ```sql
  SELECT * FROM v_auditoria_ventas_diarias ORDER BY fecha, categoria_id;
  SELECT (SELECT count(*) FROM ventas_diarias_categoria) AS filas_vdc,
         (SELECT count(*) FROM pg_trigger WHERE tgname LIKE 'trg\_vdc\_%' AND NOT tgisinternal) AS disparadores;
  ```

- **Resultado esperado:** `(0 rows)`; y `filas_vdc` igual al de antes de empezar (`1756` en la base del autor) con `disparadores = 5`. Si hiciste la prueba 27 (que sí confirma cambios), esta consulta es la que confirma que su limpieza quedó bien.
- [ ] Aprobada

---

## G. `TRUNCATE`, concurrencia y reversión

### Prueba 26 – `TRUNCATE` de las fuentes queda bloqueado

- **Objetivo:** como `TRUNCATE` no dispara disparadores de fila y desincronizaría la tabla de totales, un disparador `BEFORE TRUNCATE` lo rechaza.
- **SQL:**

  ```sql
  BEGIN;
  TRUNCATE pedido_detalle;
  ROLLBACK;

  BEGIN;
  TRUNCATE pedido CASCADE;
  ROLLBACK;

  SELECT count(*) AS detalles, (SELECT count(*) FROM pedido) AS pedidos FROM pedido_detalle;
  ```

- **Resultado esperado:** ambos `TRUNCATE` fallan con `ERROR: TRUNCATE de pedido_detalle no permitido: ventas_diarias_categoria no se puede sincronizar con TRUNCATE; use DELETE o reconstruya los totales (ver seccion 4 del script)` (el segundo menciona `pedido`); `SQLSTATE 0A000`. Los conteos siguen igual (`771201 | 250002` en la base del autor).
- [ ] Aprobada

### Prueba 27 – Concurrencia con DOS sesiones: `FOR SHARE` hace esperar

- **Objetivo:** comprobar que `fn_vdc_linea` bloquea (`FOR SHARE`) las filas de `pedido` y `producto` que lee, de modo que un detalle que se inserta y una baja lógica del mismo pedido simultáneos no desincronizan los totales.
- **Preparación:** abrí **dos terminales** con `psql -d tp4_foodstore`: **Sesión A** y **Sesión B**. A diferencia de las demás pruebas, esta **confirma cambios** (`COMMIT`) y por eso tiene un paso de limpieza. En **ambas** sesiones ejecutá primero esto (elige un pedido de hoy vigente que todavía no tiene el producto 10 y lo guarda en la variable `pid`):

  ```sql
  SELECT min(p.id) AS pid FROM pedido p
  WHERE  p.fecha >= (fn_dia_negocio(now())::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires')
    AND  NOT p.eliminado
    AND  NOT EXISTS (SELECT 1 FROM pedido_detalle d WHERE d.pedido_id = p.id AND d.producto_id = 10)
  \gset
  \echo pedido elegido: :pid
  ```

  Las dos sesiones deben mostrar el **mismo** número de pedido. Anotalo.

**Variante 1 – primero el detalle (A), después la baja lógica (B):**

| Paso | Sesión | Comando | Resultado esperado |
|------|--------|---------|--------------------|
| 1 | A | `BEGIN;` | `BEGIN` |
| 2 | A | `INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (:pid, 10, 1, 100.00, 100.00);` | `INSERT 0 1` (A ahora retiene `FOR SHARE` sobre la fila del pedido y del producto 10 hasta su `COMMIT`) |
| 3 | B | `BEGIN;` | `BEGIN` |
| 4 | B | `UPDATE pedido SET eliminado = TRUE WHERE id = :pid;` | **B se queda esperando**: no vuelve el prompt ni aparece `UPDATE 1` |
| 5 | A | `SELECT pid, pg_blocking_pids(pid) AS bloqueado_por, state, wait_event_type, left(query, 55) AS consulta FROM pg_stat_activity WHERE datname = current_database() AND cardinality(pg_blocking_pids(pid)) > 0;` | **1 fila**: la consulta de B (`UPDATE pedido SET eliminado = TRUE ...`), `state = active`, `wait_event_type = Lock`, `bloqueado_por = {pid de la sesión A}` |
| 6 | A | `COMMIT;` | `COMMIT`; en ese instante B se destraba |
| 7 | B | (se completa solo) | `UPDATE 1`; el disparador de B ya ve el detalle de A y lo resta |
| 8 | B | `COMMIT;` | `COMMIT` |
| 9 | cualquiera | `SELECT * FROM v_auditoria_ventas_diarias;` | `(0 rows)` |

**Variante 2 – primero la baja lógica (B), después el detalle (A):** (antes, ejecutá la limpieza de abajo para volver al estado inicial)

| Paso | Sesión | Comando | Resultado esperado |
|------|--------|---------|--------------------|
| 1 | B | `BEGIN;` y `UPDATE pedido SET eliminado = TRUE WHERE id = :pid;` | `UPDATE 1` (sin esperar) |
| 2 | A | `BEGIN;` y `INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (:pid, 10, 1, 100.00, 100.00);` | **A se queda esperando** en el `INSERT` (su disparador intenta `FOR SHARE` sobre la fila que B modificó) |
| 3 | B | `COMMIT;` | `COMMIT`; A se destraba |
| 4 | A | (se completa solo) | `INSERT 0 1`: A relee el pedido, lo ve con `eliminado = TRUE` y **no suma** la línea |
| 5 | A | `COMMIT;` | `COMMIT` |
| 6 | cualquiera | `SELECT * FROM v_auditoria_ventas_diarias;` | `(0 rows)` |

**Variante 3 – REACTIVACIÓN: primero `UPDATE eliminado = FALSE` (A), después un detalle (B).** Antes, en ambas sesiones, elegí un pedido de hoy **eliminado** sin el producto 10:

```sql
SELECT min(p.id) AS pid2 FROM pedido p
WHERE  p.fecha >= (fn_dia_negocio(now())::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires')
  AND  p.eliminado
  AND  NOT EXISTS (SELECT 1 FROM pedido_detalle d WHERE d.pedido_id = p.id AND d.producto_id = 10)
\gset
\echo pedido eliminado elegido: :pid2
```

| Paso | Sesión | Comando | Resultado esperado |
|------|--------|---------|--------------------|
| 1 | A | `BEGIN;` y `UPDATE pedido SET eliminado = FALSE WHERE id = :pid2;` | `UPDATE 1` (A tiene la fila del pedido bloqueada; su disparador suma los detalles vigentes que ve) |
| 2 | B | `BEGIN;` y `INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (:pid2, 10, 1, 100.00, 100.00);` | **B se queda esperando**: su disparador pide `FOR SHARE` sobre un pedido que está eliminado. Con la versión defectuosa original (filtro `NOT p.eliminado` en el `WHERE`) B **no** esperaría, leería `eliminado = TRUE` y no sumaría la línea |
| 3 | A | `SELECT pid, pg_blocking_pids(pid) AS bloqueado_por, wait_event_type FROM pg_stat_activity WHERE datname = current_database() AND cardinality(pg_blocking_pids(pid)) > 0;` | 1 fila: la sesión B, `wait_event_type = Lock`, bloqueada por A |
| 4 | A | `COMMIT;` | `COMMIT`; B se destraba |
| 5 | B | (se completa solo) | `INSERT 0 1`: B relee el pedido con `eliminado = FALSE` y **suma** la línea de 100,00 |
| 6 | B | `COMMIT;` | `COMMIT` |
| 7 | cualquiera | `SELECT * FROM v_auditoria_ventas_diarias;` | `(0 rows)`. Si la línea se hubiera perdido, aparecería 1 fila con `total_fuente` 100,00 mayor que `total_tabla` |

**Variante 4 – REACTIVACIÓN, orden inverso: primero el detalle (B), después `UPDATE eliminado = FALSE` (A).** (antes, limpieza de abajo con `:pid2`)

| Paso | Sesión | Comando | Resultado esperado |
|------|--------|---------|--------------------|
| 1 | B | `BEGIN;` y `INSERT INTO pedido_detalle (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (:pid2, 10, 1, 100.00, 100.00);` | `INSERT 0 1` (pedido eliminado: no suma, pero B retiene `FOR SHARE` sobre la fila del pedido) |
| 2 | A | `BEGIN;` y `UPDATE pedido SET eliminado = FALSE WHERE id = :pid2;` | **A se queda esperando** (`FOR SHARE` de B conflictúa con el `UPDATE`) |
| 3 | B | `COMMIT;` | `COMMIT`; A se destraba |
| 4 | A | (se completa solo) | `UPDATE 1`: el disparador de A ya ve el detalle de B y lo **suma** junto con los demás vigentes |
| 5 | A | `COMMIT;` | `COMMIT` |
| 6 | cualquiera | `SELECT * FROM v_auditoria_ventas_diarias;` | `(0 rows)` |

**Limpieza (después de cada variante, en cualquier sesión; sin transacción abierta):**

```sql
UPDATE pedido SET eliminado = FALSE WHERE id = :pid;                          -- UPDATE 1
DELETE FROM pedido_detalle WHERE pedido_id = :pid AND producto_id = 10;       -- DELETE 1
SELECT * FROM v_auditoria_ventas_diarias;                                     -- (0 rows)
-- Variantes 3 y 4 (reactivación): volver a dejar el pedido eliminado y sin el detalle de prueba
DELETE FROM pedido_detalle WHERE pedido_id = :pid2 AND producto_id = 10;      -- DELETE 1
UPDATE pedido SET eliminado = TRUE WHERE id = :pid2;                          -- UPDATE 1
SELECT * FROM v_auditoria_ventas_diarias;                                     -- (0 rows)
```

- **Criterio de aprobación:** en las variantes 1 y 2 (baja) y 3 y 4 (reactivación) se **observa la espera** (pasos 4/5 de la variante 1, paso 2 de la 2, paso 2 de la 3 y paso 2 de la 4) y la auditoría final y tras la limpieza devuelve `(0 rows)`. Si en la variante 1 la sesión B **no** espera (devuelve `UPDATE 1` al instante), el `FOR SHARE` no está actuando: la prueba falla.
- **Nota:** esta prueba no pudo ejecutarse de forma automática (requiere dos sesiones). Su resultado esperado sale del mecanismo documentado en el informe (punto c) y en el script (sección 4): `FOR SHARE` conflictúa con `FOR NO KEY UPDATE`, que es el bloqueo del `UPDATE` de `pedido.eliminado`. El test automático `test_concurrencia.sql` solo verifica que el bloqueo está declarado en `fn_vdc_linea` (y que no se filtra por `eliminado` en el `WHERE`). Las variantes 3 y 4 cubren el caso de la reactivación concurrente, que con el bloqueo condicionado a `NOT p.eliminado` perdía la línea.
- [ ] Aprobada (variante 1)  [ ] Aprobada (variante 2)  [ ] Aprobada (variante 3)  [ ] Aprobada (variante 4)  [ ] Limpieza hecha y auditoría vacía

### Prueba 28 – Reversión de la desnormalización

- **Objetivo:** el bloque de reversión elimina disparadores, funciones, vistas y tabla sin tocar las fuentes, y la consulta normalizada sigue igual.
- **SQL** (todo dentro de una transacción que se revierte al final):

  ```sql
  BEGIN;
  DROP VIEW IF EXISTS v_top5_categorias_dia;
  DROP VIEW IF EXISTS v_auditoria_ventas_diarias;
  DROP TRIGGER IF EXISTS trg_vdc_pedido_detalle ON pedido_detalle;
  DROP TRIGGER IF EXISTS trg_vdc_pedido         ON pedido;
  DROP TRIGGER IF EXISTS trg_vdc_producto       ON producto;
  DROP TRIGGER IF EXISTS trg_vdc_truncate_pedido  ON pedido;
  DROP TRIGGER IF EXISTS trg_vdc_truncate_detalle ON pedido_detalle;
  DROP FUNCTION IF EXISTS fn_vdc_trg_detalle();
  DROP FUNCTION IF EXISTS fn_vdc_trg_pedido();
  DROP FUNCTION IF EXISTS fn_vdc_trg_producto();
  DROP FUNCTION IF EXISTS fn_vdc_bloquear_truncate();
  DROP FUNCTION IF EXISTS fn_vdc_linea(BIGINT, BIGINT, NUMERIC, INTEGER);
  DROP FUNCTION IF EXISTS fn_vdc_pedido_aplicar(BIGINT, TIMESTAMPTZ, INTEGER);
  DROP FUNCTION IF EXISTS fn_vdc_aplicar(DATE, BIGINT, NUMERIC, INTEGER);
  DROP TABLE    IF EXISTS ventas_diarias_categoria;

  SELECT (SELECT count(*) FROM pg_trigger WHERE tgname LIKE 'trg\_vdc\_%' AND NOT tgisinternal) AS disparadores,
         to_regclass('ventas_diarias_categoria') AS tabla,
         (SELECT count(*) FROM pedido_detalle) AS detalles;

  SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido
  FROM   pedido_detalle dp JOIN pedido ped ON ped.id = dp.pedido_id JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id
  WHERE  fn_dia_negocio(ped.fecha) = fn_dia_negocio(now()) AND NOT ped.eliminado AND NOT dp.eliminado
  GROUP  BY c.nombre ORDER BY total_vendido DESC, c.nombre LIMIT 5;
  ROLLBACK;

  SELECT (SELECT count(*) FROM pg_trigger WHERE tgname LIKE 'trg\_vdc\_%' AND NOT tgisinternal) AS disparadores,
         (SELECT count(*) FROM ventas_diarias_categoria) AS filas_vdc;
  ```

- **Resultado esperado:** dentro de la transacción: `disparadores = 0`, `tabla` vacío (`NULL`), `detalles = 771201` (la fuente intacta) y el top 5 normalizado con las mismas 5 filas de la prueba 17. Tras el `ROLLBACK`: `disparadores = 5` y `filas_vdc = 1756`.
- [ ] Aprobada

---

## Resumen y aprobación

| Grupo | Pruebas | Aprobadas |
|-------|---------|-----------|
| A. Carga y tests automáticos | 1, 2, 3 | [ ] 1  [ ] 2  [ ] 3 |
| B. Parte 1 – FNBC | 4 a 12 | [ ] 4  [ ] 5  [ ] 6  [ ] 7  [ ] 8  [ ] 9  [ ] 10  [ ] 11  [ ] 12 |
| C. Parte 2 – base | 13 a 16 | [ ] 13  [ ] 14  [ ] 15  [ ] 16 |
| D. Top 5 y medición | 17, 18, 19 | [ ] 17  [ ] 18  [ ] 19 |
| E. Disparadores | 20, 21, 22 | [ ] 20  [ ] 21  [ ] 22 |
| F. Auditoría | 23, 24, 25 | [ ] 23  [ ] 24  [ ] 25 |
| G. TRUNCATE, concurrencia, reversión | 26, 27, 28 | [ ] 26  [ ] 27  [ ] 28 |

- [ ] **Todas las pruebas (28) aprobadas.**
- Ejecutado por: ______________________   Fecha: ______________   Equipo / PostgreSQL: ______________________
- Observaciones (pruebas que fallaron y por qué): ______________________________________________
