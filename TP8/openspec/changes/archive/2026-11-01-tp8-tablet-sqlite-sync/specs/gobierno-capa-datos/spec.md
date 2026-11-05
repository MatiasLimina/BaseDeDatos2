# Spec Delta

## Purpose

Cerrar la capa de datos de Food Store: dejar documentado quién manda sobre cada dato en los tres motores, cómo se mantiene y recupera el conjunto con las tablets, qué encontró una revisión con IA de todos los scripts y cómo se reconstruye todo desde cero, con trazabilidad de requisitos a casos.

## ADDED Requirements

### Requirement: Qué datos viajan a la tablet
El informe SHALL incluir una tabla con las columnas de producto que viajan a la tablet y las que no (por ejemplo, datos de clientes y usuarios, costos internos, fechas de auditoría), y dos o tres oraciones que expliquen por qué y que PostgreSQL es la fuente de verdad.

#### Scenario: Tabla de datos que viajan
- **WHEN** se lee la sección 1.a del informe
- **THEN** cada columna listada en la vista `v_snapshot_movil` figura como "viaja" y al menos una columna o tabla con datos personales figura como "no viaja", con su motivo

### Requirement: Mapa de los tres motores
El informe SHALL incluir un mapa de PostgreSQL, la colección MongoDB de la Unidad 7 y SQLite en forma de tabla, con una fila por dato y una columna por motor (PostgreSQL / MongoDB U7 / SQLite tablet), donde cada celda dice "manda", "copia (solo lectura)" o "no está", de modo que por columna se lea qué guarda cada motor y por fila quién manda. Las filas SHALL incluir al menos: catálogo y precio, stock, pedidos confirmados (ventas), estado del pedido, clientes y datos personales, `snapshot_servidor`, borradores, solicitudes (`cola_sync`) y resultado del semáforo. El mapa SHALL ir acompañado de una nota que diga de qué copia sale cada dato y de un dibujo chico del flujo entre motores.

#### Scenario: Cada dato tiene un dueño
- **WHEN** se lee el mapa
- **THEN** cada dato listado tiene exactamente una celda "manda", y PostgreSQL figura como dueño de precio, stock, ventas y estado del pedido

#### Scenario: Datos personales y simulación
- **WHEN** se leen las filas de clientes y del resultado del semáforo
- **THEN** los datos personales figuran solo en PostgreSQL (con un subconjunto esencial copiado dentro de los pedidos de MongoDB) y "no está" en la tablet, y el resultado del semáforo figura en SQLite como una simulación que nunca es una venta

#### Scenario: Origen de cada copia
- **WHEN** se lee la nota que acompaña al mapa
- **THEN** dice que MongoDB tiene 9 pedidos / 31 líneas migrados desde `foodstore` (TP7, con `estado`) y que la tablet trabaja sobre `food_store_copia`, copia de pruebas sin `estado`

#### Scenario: Flujo entre motores
- **WHEN** se mira el dibujo del flujo
- **THEN** muestra PostgreSQL → CSV (`v_snapshot_movil`) → SQLite, PostgreSQL (`foodstore`) → `insertMany` → MongoDB, y que de SQLite no vuelve nada al servidor porque `cola_sync` solo se simula

### Requirement: Agregado al plan de mantenimiento con las tablets
El plan de mantenimiento de la Unidad 6 (respaldo diario de PostgreSQL y prueba de restauración semanal) SHALL recibir un agregado, escrito en el TP8 sin modificar el TP6, que responda: qué se respalda y cómo se prueba la restauración; qué hacen las tablets si se restaura un respaldo viejo de PostgreSQL; y cada cuánto y quién revisa las solicitudes en CONFLICTO o RECHAZADO.

#### Scenario: Restauración de un respaldo viejo
- **WHEN** se lee la respuesta sobre un respaldo viejo
- **THEN** indica que las tablets no confían en su caché ni en sus resultados simulados previos, recargan una instantánea nueva del servidor restaurado antes de evaluar, y que las solicitudes pendientes se evalúan contra esa instantánea

#### Scenario: Revisión periódica con responsable
- **WHEN** se lee la respuesta sobre CONFLICTO y RECHAZADO
- **THEN** nombra una frecuencia concreta y un rol responsable

### Requirement: Code review con IA con decisión por hallazgo
La revisión con IA SHALL cubrir todos los scripts de la cursada: TP1–TP6 y `Proyecto_Integrador/database/` (otro repo de la materia, leído solo como entrada), el TP7 y el TP8. Cada hallazgo SHALL tener una decisión (aceptado, corregido o descartado) y un motivo. Los hallazgos de TP1–TP6 SHALL registrarse con su decisión sin corregirse desde este repo. Al menos tres hallazgos de al menos dos unidades (TP7 y TP8) SHALL desarrollarse con la comprobación hecha en la base, y al menos uno SHALL estar descartado con fundamento.

#### Scenario: Hallazgos desarrollados y verificados
- **WHEN** se lee la sección 3.c
- **THEN** hay al menos tres hallazgos desarrollados de al menos dos unidades distintas (TP7 y TP8), cada uno con la consulta o prueba que lo comprobó y su salida en evidencias

#### Scenario: Hallazgo descartado
- **WHEN** se filtra la tabla por decisión
- **THEN** al menos un hallazgo figura como descartado con un fundamento comprobable

#### Scenario: Herramienta declarada con honestidad
- **WHEN** se lee la sección 3.c, la bitácora o la DUIA
- **THEN** dicen que la revisión la hizo un agente de Claude de solo lectura y no el agente Plan de OpenCode

### Requirement: Requisitos EARS trazados a casos
La documentación de especificación SHALL contener al menos cuatro requisitos en notación EARS (`WHEN ... THE SYSTEM SHALL ...`), cada uno con la línea "Se prueba con: Cx" que apunta a un caso C1–C7 existente, junto con un diseño y una lista de tareas breves derivados de este change.

#### Scenario: Cada requisito con su caso
- **WHEN** se lee `TP8/docs/kiro/requirements.md`
- **THEN** hay al menos cuatro requisitos EARS y cada uno nombra un caso cuya evidencia existe en `TP8/evidencias/`

### Requirement: Bitácora de IA y DUIA
La bitácora SHALL tener al menos tres entradas con qué se pidió a la IA, qué se aceptó, qué se descartó y por qué, incluyendo al menos un descarte. La DUIA SHALL declarar las herramientas efectivamente usadas (Claude Code y OpenSpec en lugar de Kiro y OpenCode) y que no se compartieron datos personales reales.

#### Scenario: Entrada con descarte
- **WHEN** se lee la bitácora
- **THEN** al menos una entrada describe algo propuesto por la IA que se descartó y la comprobación que llevó a descartarlo

### Requirement: README reproducible desde cero
El README del TP8 SHALL dar el orden completo de comandos para crear todo desde cero (vista y exportación en PostgreSQL, base SQLite, importación, pruebas, casos, restauración y verificación final), con la salida esperada de cada test.

#### Scenario: Reconstrucción desde cero
- **WHEN** se borra `foodstore_movil.db` y se siguen los comandos del README en orden
- **THEN** todos los tests imprimen OK, los casos C1–C7 dan el resultado esperado y la verificación final de PostgreSQL coincide con la línea base

### Requirement: Informe acotado
El informe SHALL entregarse en PDF, con un máximo de seis páginas, y cubrir 1.a, 2.c, 3.a, 3.b y 3.c.

#### Scenario: Límite de páginas
- **WHEN** se genera el PDF del informe
- **THEN** tiene seis páginas o menos y contiene las cinco secciones pedidas
