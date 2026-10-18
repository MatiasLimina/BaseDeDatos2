# Informe TP4 – FNBC y desnormalización controlada (Food Store)

> Base de trabajo: `tp4_foodstore` (PostgreSQL 18). Notación: **L** = `LoteID`, **D** = `DepositoID`, **R** = `ResponsableControlID`.
> Artefactos de la Parte 1: `TP4/tp_fnbc_control_lote.sql` y `TP4/tests/test_fnbc_*.sql`.

# Parte 1 – Forma Normal de Boyce-Codd: `control_lote_almacen`

Esquema original (consigna): `control_lote_almacen(L, D, R)` con PK `(L, D)`.
Instancia de ejemplo (sección 1 del script):

| LoteID | DepositoID | ResponsableControlID |
|--------|------------|----------------------|
| 501 | 30 | 801 |
| 502 | 30 | 801 |
| 503 | 31 | 802 |

## a) Dependencias funcionales

Regla de negocio: el control de un lote en un depósito lo realiza un responsable, y cada responsable pertenece a **un único depósito**. En notación formal:

- **DF1**: `{L, D} → R` (dado un lote y un depósito, el responsable queda determinado; es la PK).
- **DF2**: `R → D` (un responsable pertenece a un solo depósito).

Evidencia sobre la instancia (script, sección 1): la consulta `GROUP BY responsable_control_id HAVING count(DISTINCT deposito_id) > 1` devuelve **0 filas**, coherente con DF2 (801 → 30, 802 → 31). Una instancia no demuestra una DF; sólo es coherente con ella, la DF proviene de la regla de negocio.

## b) Clausuras y claves candidatas

Con `F = { {L,D} → R ; R → D }` y el esquema `{L, D, R}`:

| Conjunto X | Cálculo de X⁺ | X⁺ | ¿Superclave? |
|------------|---------------|----|--------------|
| `{L}` | ninguna DF aplicable | `{L}` | No |
| `{D}` | ninguna DF aplicable | `{D}` | No |
| `{R}` | `R → D` agrega D | `{R, D}` | No (falta L) |
| `{L, D}` | `{L,D} → R` agrega R | `{L, D, R}` | **Sí** |
| `{L, R}` | `R → D` agrega D | `{L, R, D}` | **Sí** |
| `{D, R}` | `R → D` no agrega nada nuevo | `{D, R}` | No (falta L) |

Claves candidatas (superclaves minimales): **`{L, D}`** y **`{L, R}`**. Ninguno de sus subconjuntos propios es superclave (ver filas de `{L}`, `{D}`, `{R}`).

**Atributos primos** (pertenecen a alguna clave candidata): L (en ambas), D (en `{L,D}`) y R (en `{L,R}`). Los **tres atributos son primos**; no hay atributos no primos.

## c) Forma normal

- **3FN: sí.** Para cada DF `X → A` no trivial, o X es superclave o A es primo. DF1: `{L,D}` es superclave. DF2: `R` no es superclave, pero `D` es primo. Cumple.
- **FNBC: no.** FNBC exige que el determinante de **toda** DF no trivial sea superclave. DF2 `R → D` es no trivial y `R⁺ = {R, D} ≠ {L, D, R}`: el determinante `R` no es superclave (no incluye a `L`). Por lo tanto **DF2 es la DF violatoria**.

Este es el caso clásico en que 3FN (que tolera determinantes no superclave si el dependiente es primo) es más débil que FNBC.

## d) Anomalías

Todas surgen de que el hecho "el responsable 801 pertenece al depósito 30" está **repetido** en cada fila de control de ese responsable.

- **Anomalía de inserción.** No se puede registrar que un nuevo responsable (por ejemplo 803) pertenece al depósito 30 mientras no controle algún lote, porque `L` es parte de la PK y no puede ser nulo. El hecho "803 trabaja en el depósito 30" no tiene dónde almacenarse. Al revés, al asignarle un primer lote hay que repetir correctamente el depósito, y nada impide escribir `(504, 31, 801)`, contradiciendo DF2 (801 pertenece a 30) sin que la PK `(L, D)` lo detecte.
- **Anomalía de borrado.** Si se elimina la fila `(503, 31, 802)` (por ejemplo, el lote 503 deja de controlarse), se pierde el único registro de que el responsable 802 pertenece al depósito 31. Lo mismo ocurre con 801 y el depósito 30 si se borran las filas 501 y 502.
- **Anomalía de actualización.** Si el responsable 801 se traslada del depósito 30 al 31, hay que modificar **dos filas** (501 y 502). Si sólo se actualiza una, la instancia queda inconsistente: 801 aparecería en los depósitos 30 y 31 a la vez, violando DF2. Cuantos más lotes controle un responsable, más filas hay que mantener sincronizadas.

## e) Descomposición en FNBC

**Algoritmo aplicado** (descomposición por una DF violatoria): se toma `X → Y` con X no superclave; aquí `X = R`, `Y = D`, es decir **`R → D`**. Se reemplaza el esquema `S = {L, D, R}` por:

- **R1 = X ∪ Y = {R, D}** → tabla `responsable_deposito(responsable_control_id, deposito_id)`, clave `R`.
- **R2 = S − Y = {L, R}** → tabla `control_lote(lote_id, responsable_control_id)`, clave `{L, R}`.

**Por qué cada esquema está en FNBC** (el único determinante de toda DF no trivial es una superclave):

- `responsable_deposito(R, D)`: la única DF no trivial es `R → D` y `R` es su clave (`R⁺ = {R, D}`).
- `control_lote(L, R)`: no tiene DFs no triviales salvo las que se siguen de su clave `{L, R}` (todo el esquema ya es la clave); no hay determinante que no sea superclave.

Dos consecuencias de diseño (las dos FKs `ON DELETE RESTRICT` preservan la trazabilidad del control de calidad): (1) `control_lote.responsable_control_id` referencia a `responsable_deposito` (no a `usuario`), de modo que todo responsable usado en un control tiene depósito asignado; (2) ambas tablas usan el **mismo nombre de columna** `responsable_control_id` para que la reunión natural opere exactamente por el atributo común.

Las anomalías del punto d) desaparecen: el hecho "el responsable pertenece a un depósito" se guarda **una sola vez** (se puede dar de alta un responsable sin lotes; borrar un control no borra la asignación; un traslado modifica una sola fila). Se verifica en `TP4/tests/test_fnbc_descomposicion.sql` (801 en el depósito 31 rechazado por PK, responsable sin depósito rechazado por FK, borrados `RESTRICT`).

Extracto del script (`TP4/tp_fnbc_control_lote.sql`, sección 2):

```sql
CREATE TABLE responsable_deposito (
    responsable_control_id BIGINT NOT NULL,
    deposito_id            BIGINT NOT NULL,
    CONSTRAINT pk_responsable_deposito PRIMARY KEY (responsable_control_id),
    CONSTRAINT fk_rd_responsable FOREIGN KEY (responsable_control_id) REFERENCES usuario (id)  ON DELETE RESTRICT,
    CONSTRAINT fk_rd_deposito    FOREIGN KEY (deposito_id)            REFERENCES deposito (id) ON DELETE RESTRICT
);

CREATE TABLE control_lote (
    lote_id                BIGINT NOT NULL,
    responsable_control_id BIGINT NOT NULL,
    CONSTRAINT pk_control_lote PRIMARY KEY (lote_id, responsable_control_id),
    CONSTRAINT fk_cl_lote        FOREIGN KEY (lote_id)                REFERENCES lote (id)                                    ON DELETE RESTRICT,
    CONSTRAINT fk_cl_responsable FOREIGN KEY (responsable_control_id) REFERENCES responsable_deposito (responsable_control_id) ON DELETE RESTRICT
);
```

## f) Vista de compatibilidad, reunión sin pérdida y costo de la descomposición

**Migración y vista** (script, sección 3): se verifica antes la DF (`GROUP BY responsable_control_id HAVING count(DISTINCT deposito_id) > 1` → 0 filas), se migra con `INSERT ... SELECT DISTINCT` a `responsable_deposito` (2 filas: 801→30, 802→31) e `INSERT ... SELECT` a `control_lote` (3 filas) y se crea la vista:

```sql
CREATE VIEW v_control_lote_almacen AS
SELECT lote_id, deposito_id, responsable_control_id
FROM   control_lote NATURAL JOIN responsable_deposito;
```

**Unión sin pérdida.** Para una descomposición binaria `{R1, R2}` de `S` el criterio es que `R1 ∩ R2 → R1` o `R1 ∩ R2 → R2`. Aquí `R1 ∩ R2 = {R}` y `R → D` implica `R → {R, D} = R1`: el atributo común es **superclave (clave) de `responsable_deposito`**. Por eso cada fila de `control_lote` se une con exactamente una fila de `responsable_deposito` y la reunión no produce filas espurias ni pierde ninguna (la FK garantiza además que el responsable siempre existe en R1).

**Evidencia.** `control_lote_almacen EXCEPT v_control_lote_almacen` y `v_control_lote_almacen EXCEPT control_lote_almacen` devuelven **0 filas** y ambos conteos son 3. Verificado de forma automática en `TP4/tests/test_fnbc_vista_migracion.sql`.

**Costo: dependencia no preservada.** La DF `{L, D} → R` ya no es una restricción local: sus atributos quedaron en tablas distintas (`L` en `control_lote`, `D` en `responsable_deposito`), por lo que ninguna PK/UNIQUE puede imponerla. Demostración reproducible (script, final de la sección 3, dentro de una transacción revertida): se agrega el responsable 803 al depósito 30 y se inserta el control `(501, 803)`; el esquema lo **acepta** y la vista muestra dos responsables para `(501, 30)`, algo que la PK `(L, D)` del esquema original impedía. Mitigaciones posibles: (i) un disparador de verificación en `control_lote`/`responsable_deposito` que rechace un segundo responsable para el mismo `(L, D)`; (ii) conservar `deposito_id` en `control_lote` con una FK compuesta hacia `responsable_deposito(responsable_control_id, deposito_id)` más `UNIQUE (lote_id, deposito_id)`, lo que reintroduce una redundancia controlada. **Decisión del equipo: no se implementa ninguna de las dos; la pérdida se documenta y demuestra** (es el trade-off clásico de FNBC frente a 3FN, que siempre preserva dependencias).
