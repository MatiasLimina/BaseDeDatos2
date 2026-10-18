# control-lote-almacen Specification

## Purpose

Registrar qué responsable controla cada fracción de un lote en cada depósito de la operación mayorista de Food Store, con un esquema en FNBC que elimina las anomalías del esquema original y una vista que reconstruye la relación original sin pérdida.

## Requirements

### Requirement: Esquema original con instancia de ejemplo
El script de la Parte 1 SHALL crear las tablas maestras mínimas `lote`, `deposito` y `usuario` y la tabla `control_lote_almacen(lote_id, deposito_id, responsable_control_id)` con PK `(lote_id, deposito_id)` y FKs a esas maestras, cargada exactamente con la instancia `(501,30,801)`, `(502,30,801)`, `(503,31,802)`. El script SHALL poder ejecutarse más de una vez sobre la misma base sin error.

#### Scenario: Instancia de ejemplo cargada
- **WHEN** se ejecuta el script de la Parte 1 sobre una base limpia
- **THEN** `control_lote_almacen` contiene exactamente 3 filas: `(501,30,801)`, `(502,30,801)` y `(503,31,802)`

#### Scenario: PK original rechaza duplicado de lote y depósito
- **WHEN** se intenta insertar `(501,30,802)` en `control_lote_almacen`
- **THEN** la base rechaza la fila por violación de clave primaria

#### Scenario: Re-ejecución idempotente
- **WHEN** el script de la Parte 1 se ejecuta dos veces seguidas
- **THEN** la segunda ejecución termina sin errores y deja el mismo estado final

### Requirement: Análisis formal de dependencias y FNBC documentado
El informe SHALL enunciar en notación formal las DFs `{LoteID, DepositoID} → ResponsableControlID` y `ResponsableControlID → DepositoID`, calcular las clausuras de los subconjuntos candidatos, listar las claves candidatas `{LoteID, DepositoID}` y `{LoteID, ResponsableControlID}`, indicar que los tres atributos son primos, y demostrar con la definición de FNBC que el esquema no la cumple.

#### Scenario: Violación de FNBC identificada
- **WHEN** se lee la sección de la Parte 1 del informe
- **THEN** identifica `ResponsableControlID → DepositoID` como DF violatoria, muestra que `ResponsableControlID⁺ = {ResponsableControlID, DepositoID}` no incluye `LoteID` y concluye que su determinante no es superclave

#### Scenario: Anomalías sobre la instancia
- **WHEN** se lee la sección de anomalías
- **THEN** hay un párrafo por cada anomalía (inserción, borrado, actualización) con un escenario concreto sobre las filas 501/502/503, depósitos 30/31 y responsables 801/802

### Requirement: Descomposición sin pérdida en FNBC
El script SHALL crear `responsable_deposito(responsable_control_id, deposito_id)` con PK `responsable_control_id`, y `control_lote(lote_id, responsable_control_id)` con PK compuesta, con FKs explícitas `ON DELETE RESTRICT` hacia `usuario`, `deposito`, `lote` y `responsable_deposito`. Ambas relaciones SHALL estar en FNBC.

#### Scenario: Un responsable pertenece a un único depósito
- **WHEN** se intenta registrar al responsable 801 en el depósito 31 teniendo ya asignado el depósito 30
- **THEN** la base rechaza la fila por violación de clave primaria de `responsable_deposito`

#### Scenario: Control de lote exige responsable con depósito asignado
- **WHEN** se inserta en `control_lote` un responsable que no existe en `responsable_deposito`
- **THEN** la base rechaza la fila por violación de clave foránea

#### Scenario: Cambio de depósito de un responsable en un solo lugar
- **WHEN** se actualiza el depósito del responsable 801 en `responsable_deposito`
- **THEN** la vista de compatibilidad refleja el nuevo depósito para los lotes 501 y 502 con una única fila modificada

### Requirement: Vista de compatibilidad y migración verificada
El script SHALL crear la vista `v_control_lote_almacen` que reconstruye `(lote_id, deposito_id, responsable_control_id)` mediante `NATURAL JOIN` de las dos tablas descompuestas, migrar la instancia desde `control_lote_almacen` y verificar la equivalencia con `EXCEPT` en ambos sentidos.

#### Scenario: Equivalencia en ambos sentidos
- **WHEN** se ejecuta `control_lote_almacen EXCEPT v_control_lote_almacen` y `v_control_lote_almacen EXCEPT control_lote_almacen` después de la migración
- **THEN** ambas consultas devuelven 0 filas y la vista tiene la misma cantidad de filas que la tabla original

#### Scenario: Justificación de unión sin pérdida
- **WHEN** se lee el informe de la Parte 1
- **THEN** justifica que la reunión es sin pérdida porque el atributo común `ResponsableControlID` es superclave de `responsable_deposito`

### Requirement: Costo de preservación de dependencias documentado
El informe SHALL explicar que la DF `{LoteID, DepositoID} → ResponsableControlID` no se impone localmente en el esquema descompuesto, y SHALL demostrarlo con un caso reproducible ejecutado dentro de una transacción revertida.

#### Scenario: DF no preservada demostrada
- **WHEN** se registra un segundo responsable del depósito 30 para el lote 501 dentro de una transacción revertida
- **THEN** la inserción es aceptada por el esquema descompuesto y la vista muestra dos responsables para `(501,30)`, evidencia de la dependencia no preservada
