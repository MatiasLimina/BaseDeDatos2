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
