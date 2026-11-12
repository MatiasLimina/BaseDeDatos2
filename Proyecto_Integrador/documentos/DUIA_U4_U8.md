# Declaración de Uso de Inteligencia Artificial (DUIA) unificada, Unidades 4 a 8

**Asignatura**: Bases de Datos II
**Proyecto**: Trabajo Práctico Integrador "Food Store", segunda entrega (U4 a U8)
**Carrera**: Tecnicatura Universitaria en Programación, UTN
**Integrantes**: Matias Limina, Nicolas Monjelardi y Lautaro Aguero

Este documento reúne en un solo lugar el uso de IA de las unidades 4, 5, 6, 7 y 8. No reemplaza los registros de cada unidad: los resume y los enlaza. Donde la fuente tiene el prompt literal, se cita o se enlaza; donde no lo tiene, se dice. Cada afirmación sale de los archivos enlazados.

---

## 1. Alcance, herramientas y sustituciones autorizadas

### 1.1 Herramientas efectivamente usadas

| Herramienta | Dónde se usó |
|---|---|
| **Claude Code** (Claude Opus 5.5 según las bitácoras de TP5 y TP6) en la terminal del repositorio | U4 (junto con OPSX y el MCP `postgres`), parte de U5, U6, U7 y U8 |
| **OPSX / OpenSpec** (`propose`, `apply`, `archive`) | U4 y U8 (specs versionadas) |
| **MCP `postgres`** (herramienta de Claude Code para ejecutar SQL sobre la base de trabajo) | U4 |
| **OpenCode** con `deepseek-v4.1-flash-free` (generación) y `gemini-3.8-flash` / `gemini-3.5-flash` (planificación y auditoría) | U5 (partes A, C y D) |
| Agente de IA aislado (Claude Sonnet), lanzado desde Claude Code, sin herramientas | U7 (consigna 6) |
| Agentes revisores de solo lectura de Claude (subagentes de Claude Code) | U6 (revisión del diff antes de cada commit) y U8 (code review de 107 scripts) |

### 1.2 Sustituciones autorizadas por la cátedra

La consigna de la segunda entrega pide specs de **Kiro** y scripts generados con **OpenCode**. El equipo consultó al profesor en clase y obtuvo su aprobación para dos reemplazos, documentados en la sección 6.1 del [Informe Técnico Consolidado](TPI_FoodStore_Informe_Tecnico_Consolidado.md):

| Exigido por la consigna | Usado | Consecuencia en este documento |
|---|---|---|
| Specs de Kiro | Ciclo OPSX/OpenSpec: propuesta, diseño, specs delta y tareas versionadas en Git | En U4 y U8 las "specs usadas" son los artefactos de OpenSpec. En U8 además se exportaron al formato de tres archivos de Kiro (`docs/kiro/`). |
| Scripts con OpenCode | Claude Code | U6, U7 y U8 se hicieron con Claude Code. En U5 sí se usó OpenCode como asistente principal en las partes A, C y D, y Claude Code en el resto. |

Dos precisiones para no sobredeclarar: (a) en U5 la carpeta `docs/kiro_roles_spec/` tiene nombre de Kiro pero la generó OpenCode con DeepSeek, no Kiro; (b) el equipo no usó Kiro en ninguna de las unidades 4 a 8.

### 1.3 Regla común de trabajo

Ningún script ni comando propuesto por una IA se aceptó sin leerlo y sin ejecutarlo o probarlo en una base de copia, en una base descartable o dentro de una transacción revertida. Los detalles de cada unidad están en las secciones 3 a 7.

---

## 2. Resumen por unidad

| Unidad | Herramienta(s) | Finalidad | Fuente de prompts / specs | Verificación |
|---|---|---|---|---|
| **U4** FNBC y desnormalización | Claude Code + OPSX + MCP `postgres` | Descomposición a FNBC de `control_lote_almacen`; tabla de totales por categoría y día mantenida con disparadores; tests | **No hay registro de prompts.** Las "specs" son los artefactos del change OPSX archivado | 14 tests `DO $$ ... ASSERT`, auditoría de 0 filas, pruebas manuales ejecutadas por el autor, reversión probada |
| **U5** Roles, auditoría, simulacro, anonimización | OpenCode (DeepSeek, Gemini) y Claude Code | `roles.sql` de mínimo privilegio, auditoría del script, configuración de logs, reconstrucción de un incidente, anonimización | Prompts en la bitácora; texto literal de OpenCode en `docs/ia/` | Tests escritos antes, mutaciones, lectura del log crudo, pruebas en un clúster de ensayo |
| **U6** Mantenimiento y recuperación | Claude Code + agente revisor de solo lectura | Respaldo, chequeo de salud, mantenimiento, restauración de prueba, integridad, programación de tareas | Bitácora de 11 registros y `SPEC_U6.md` | Tests sobre bases descartables, mutaciones, revisión del diff antes de cada commit |
| **U7** NoSQL | Claude Code (todo el TP) y un agente aislado (Claude Sonnet) para la consulta | Modelo documental y migración a MongoDB; consulta comparativa a una IA | Prompt literal de la consulta en `docs/ia/consulta_ia.md`. **Los prompts del resto del trabajo con Claude Code no están registrados** | Tests de migración y de consultas, contraste con documentación oficial y con el laboratorio |
| **U8** SQLite y cierre | Claude Code + OPSX (en lugar de Kiro y OpenCode) | Esquema SQLite, semáforo, code review de 107 scripts, plan de mantenimiento | Change OPSX archivado, `docs/kiro/`, bitácora y DUIA propia | 8 scripts de test, evidencias por hallazgo, descartes con prueba |

---

## 3. Unidad 4: FNBC y desnormalización controlada

### 3.1 Herramientas y finalidad

- **Herramientas**: Claude Code con OPSX y el MCP `postgres`. El informe consolidado las declara como herramientas autorizadas (§6.1).
- **Finalidad**: diseñar la descomposición en FNBC de la extensión mayorista `control_lote_almacen` y la desnormalización controlada del reporte "top 5 de categorías del día", escribir los scripts SQL y los tests, y ejecutarlos sobre la base de trabajo `tp4_foodstore` (clon descartable de `food_store_copia`).

### 3.2 Prompts o specs usados

**Declaración explícita: la Unidad 4 no tiene bitácora ni log de prompts.** Los mensajes enviados a Claude Code en esta unidad no se guardaron, y este documento no los reconstruye. Lo que sí existe, y es lo que aquí se declara como especificación entregada a la IA, es el change de OPSX archivado:

| Artefacto | Contenido | Enlace |
|---|---|---|
| Propuesta | Por qué y qué cambia: consigna del TP, partes 1 y 2, capacidades nuevas, impacto y entorno | [`proposal.md`](../../openspec/changes/archive/2026-10-18-tp4-fnbc-desnormalizacion/proposal.md) |
| Diseño | 15 decisiones numeradas (tablas maestras mínimas, descomposición FNBC, dependencia no preservada, tabla de totales con disparadores en lugar de vista materializada, estrategia de tests, concurrencia con `FOR SHARE`, checkpoint 8.9), riesgos y **plan de migración y reversión** | [`design.md`](../../openspec/changes/archive/2026-10-18-tp4-fnbc-desnormalizacion/design.md) |
| Tareas | Lista de tareas por grupos con el ciclo RED, GREEN, TRIANGULATE y REFACTOR; las 59 tareas figuran marcadas como hechas y ninguna queda pendiente | [`tasks.md`](../../openspec/changes/archive/2026-10-18-tp4-fnbc-desnormalizacion/tasks.md) |
| Specs delta | Requisitos y escenarios de las dos capacidades | [`control-lote-almacen/spec.md`](../../openspec/changes/archive/2026-10-18-tp4-fnbc-desnormalizacion/specs/control-lote-almacen/spec.md), [`ventas-diarias-categoria/spec.md`](../../openspec/changes/archive/2026-10-18-tp4-fnbc-desnormalizacion/specs/ventas-diarias-categoria/spec.md) |
| Specs vigentes | Las mismas capacidades ya sincronizadas | [`openspec/specs/control-lote-almacen/spec.md`](../../openspec/specs/control-lote-almacen/spec.md), [`openspec/specs/ventas-diarias-categoria/spec.md`](../../openspec/specs/ventas-diarias-categoria/spec.md) |

Reglas que esos artefactos le impusieron a la IA (en `tasks.md` y `design.md`): base de trabajo solo `tp4_foodstore`, nunca `food_store` ni `food_store_copia`; Strict TDD con el RED validado por la razón esperada; commits atómicos por grupo y sin `push`; gobernanza MEDIUM, con puntos de control en los que se detiene y se expone al usuario toda decisión no obvia; no tocar `Proyecto_Integrador/` sin confirmación explícita.

### 3.3 Qué se aceptó, rechazó o corrigió

Fuentes: [`design.md`](../../openspec/changes/archive/2026-10-18-tp4-fnbc-desnormalizacion/design.md) (decisiones 3 y 15, preguntas abiertas) e [`informe_tp4.md`](../../TP4/informe_tp4.md) (conclusiones y sección de defectos).

- **Decisión humana, dependencia no preservada.** El diseño planteó dos mitigaciones posibles (disparador de verificación, o `deposito_id` redundante con FK compuesta). El usuario decidió no implementar ninguna: la dependencia `{Lote, Depósito} → Responsable` que la FNBC no preserva solo se documenta y se demuestra en una transacción revertida.
- **Decisiones humanas del checkpoint 8.9** (decisión 15 del diseño): categoría no congelada a la fecha de venta; `NUMERIC(14,2)` para el total agregado, como excepción a la regla de montos del proyecto; borrado de la fila al llegar a 0 líneas; fila caliente y deadlock aceptados como riesgos documentados; `TRUNCATE` bloqueado con un disparador `BEFORE TRUNCATE`.
- **Corregido, falso positivo de un test.** `test_concurrencia.sql` buscaba el texto del bloqueo también en los comentarios de la función, por lo que pasaba sin que el bloqueo estuviera; ahora ignora los comentarios (commit `46d3da5`). Lo detectó la ejecución manual.
- **Corregido, codificación en Windows.** `psql` leía el script con la codificación de la consola y duplicaba categorías con acentos; el script de la parte 2 empieza ahora con `SET client_encoding = 'UTF8'` (commit `7417b2d`). Lo detectó la ejecución manual.
- **Corregido, bloqueo omitido.** El diseño registra que una versión anterior de `fn_vdc_linea` filtraba `NOT p.eliminado` en el `WHERE`, de modo que un pedido eliminado no tomaba bloqueo; se corrigió tras la segunda revisión.
- **Acotado en el alcance.** No se impuso con disparador la dependencia perdida (ver arriba). La reactivación concurrente (variantes 3 y 4 de la prueba 27) no se ejecutó en vivo, y así lo declara el informe.

El informe de TP4 no tiene una tabla "propuesta de la IA / decisión" por interacción, porque no hubo registro de interacciones. Lo anterior es lo que los documentos de la unidad permiten atribuir con certeza.

### 3.4 Verificación

- **Strict TDD**: 14 archivos de test en [`TP4/tests/`](../../TP4/tests/), bloques `DO $$ ... ASSERT ... $$`. El informe declara que los 14 se ejecutaron contra `tp4_foodstore` a través del MCP `postgres` (una sentencia por llamada) y que la base quedó como antes de empezar.
- **Auditoría de consistencia**: la tabla de totales se compara contra la fuente y devuelve 0 filas ([`auditoria.txt`](../../TP4/evidencias/auditoria.txt)); `test_auditoria.sql` comprueba además que detecta alteraciones provocadas.
- **Medición con `EXPLAIN (ANALYZE, BUFFERS)`** antes y después: [`explain_antes.txt`](../../TP4/evidencias/explain_antes.txt) y [`explain_despues.txt`](../../TP4/evidencias/explain_despues.txt).
- **Ejecución humana independiente**: el autor ejecutó a mano los dos scripts completos con `psql -v ON_ERROR_STOP=1 -f`, su re-ejecución y las pruebas de [`pruebas_manuales.md`](../../TP4/pruebas_manuales.md) (la 27 solo en su variante 1; la 28, de reversión, completa), y repitió las mediciones en DBeaver.
- **Reversión**: [`test_reversibilidad.sql`](../../TP4/tests/test_reversibilidad.sql) y prueba manual 28.

### 3.5 Limitaciones de la evidencia de U4

- No hay prompts guardados (ver 3.2).
- La verificación automatizada solo pudo enviar una sentencia por llamada; lo que exige dos sesiones (concurrencia) se cubrió parcialmente con ejecución manual.

---

## 4. Unidad 5: usuarios, roles, auditoría, simulacro y anonimización

### 4.1 Herramientas y finalidad

| Parte | Herramienta y modelo | Finalidad |
|---|---|---|
| A, planificación | OpenCode, `gemini-3.8-flash` | Hacer de "orquestador": planificar y redactar el prompt de la sesión de generación |
| A, generación | OpenCode, `deepseek-v4.1-flash-free`, 174 turnos autónomos | Especificación, `roles.sql` de mínimo privilegio y consultas de verificación |
| A, auditoría (consigna A.4) | OpenCode, `gemini-3.5-flash`, agente `plan` de solo lectura | Auditar `roles.sql` y proponer mejoras |
| A (reconstrucción y correcciones), B, C, D | Claude Code (Claude Opus 5.5) | Reconstruir `usuario` y `fn_autenticar`, corregir riesgos, configurar la auditoría, simulacro de incidente, anonimización |
| C, reconstrucción del incidente | OpenCode, `gemini-3.5-flash`, en una carpeta aislada con solo el log anonimizado | Reconstruir lo ocurrido y proponer contención |
| D | OpenCode, `gemini-3.5-flash` | Intento sin respuesta por cuota agotada; el punto se hizo con Claude Code |

### 4.2 Prompts o specs usados

La bitácora [`TP5/BITACORA.md`](../../TP5/BITACORA.md) registra 17 interacciones (A-0a a A-5, B-1 a B-3, C-1 a C-5, D-1 y D-2), cada una con prompt, respuesta y validación humana. La evidencia literal de las sesiones de OpenCode, extraída de su base local, está en:

- [`opencode_parte_a_generacion.md`](../../TP5/docs/ia/opencode_parte_a_generacion.md): prompt completo de la generación de la parte A (empieza con "Actuá como un Administrador de Base de Datos (DBA) senior y especialista en seguridad para PostgreSQL 16+") e ids de sesión.
- [`opencode_auditoria_roles.md`](../../TP5/docs/ia/opencode_auditoria_roles.md): consigna A.4 ("Auditá este archivo roles.sql de PostgreSQL 16 para Food Store. Proponé mejoras o correcciones de seguridad y de mantenimiento, indicando para cada propuesta la sentencia SQL exacta. No modifiques archivos.") y las siete propuestas completas.
- [`opencode_reconstruccion_incidente.md`](../../TP5/docs/ia/opencode_reconstruccion_incidente.md): prompt ("Reconstruí qué ocurrió en este log y proponé una hipótesis de contención.") y respuesta.

Los pedidos a Claude Code (A-1 a A-4, B, C-1, C-2, C-4, C-5, D-2) figuran en la bitácora como pedido textual breve (por ejemplo, "Seguir con Parte B", o "Arranquemos por terminar la Parte A y una vez realizada hacer el commit (commits atómicos)"). No hay un archivo con la conversación completa de Claude Code.

Spec: [`requirements.md`](../../TP5/docs/kiro_roles_spec/requirements.md) y [`design.md`](../../TP5/docs/kiro_roles_spec/design.md) de `TP5/docs/kiro_roles_spec/`, generados por OpenCode en la parte A (formato Kiro, sin Kiro). La unidad 5 no pasó por un change de OpenSpec.

### 4.3 Qué se aceptó, rechazó o corrigió

Fuente: [`TP5/BITACORA.md`](../../TP5/BITACORA.md), con la consolidación de su parte E.1.

**Corregido por el equipo (la IA propuso algo inseguro, incorrecto o de más):**

- **A-0b.** DeepSeek le dio a `admin_datos` permisos que permitían escalar a `ADMIN` (`EXECUTE` sobre `fn_resetear_password`, `INSERT (contrasena)`, `INSERT/UPDATE (rol)`) y, aunque en su razonamiento lo detectó, decidió dejarlo documentado sin corregirlo. El equipo lo encontró al revisar la verificación y lo cerró en el commit `e6d5d8f`, con [`test_roles.sql`](../../TP5/sql/test_roles.sql), que antes se comprobó que falla en los cuatro casos reintroducidos (A-3).
- **A-4.** La captura de evidencia salió con texto desfigurado por la consola de Windows; se detectó en el `git diff` y se corrigió.
- **B-2.** Cuatro defectos del script de prueba de auditoría: variables de psql dentro de `$$` y de `\!`, una precondición que también rechazaba las reglas de replicación y la suposición de que el script seguía tras un `\connect` fallido.
- **C-2.** `RAISE LOG` dejaba las seis claves probadas, incluida la correcta, en texto plano en el log, y el test de la IA no lo veía. Se detectó leyendo el log crudo antes de anonimizarlo y entregarlo a otra IA. Se cambió a `RAISE WARNING`, con un test que usa la clave literal (commit `bf5edf0`).
- **C-3.** Gemini invirtió causa y consecuencia en la reconstrucción del incidente y afirmó lo que el log no puede ver (que no hubo extracción de datos; que el origen era un "servidor de aplicación"). La decisión de contención la tomó el equipo ([`informe_incidente.md`](../../TP5/docs/informe_incidente.md), secciones 5 y 6).
- **C-4.** El borrador del informe recomendaba revisar `pg_stat_statements`, que no estaba instalada; se corrigió.
- **C-5.** El anonimizador solo ocultaba rutas de una carpeta llamada `pgdata` (0 rutas reemplazadas); se corrigió con TDD.

**Auditoría de `roles.sql` (A-5), siete propuestas de Gemini.** Se aceptaron la 3 (refactor sin cambio de privilegios, commit `bb0bab2`) y la 7 en parte (esquema explícito, commit `a69bebb`). Se rechazaron la 1, 2, 4, 5 y 6, cada una con una prueba en el clúster de ensayo: la 1 rompe el script con un DBA no superusuario; la 2 parte de un diagnóstico incorrecto; la 4 amplía permisos "por si acaso"; la 5 crea entradas en `pg_default_acl` en lugar de borrarlas; la 6 tiene una premisa falsa.

**D-1.** El pedido a OpenCode no obtuvo respuesta por cuota agotada. La causa real se descubrió después y se corrigió la nota de [`verificacion_equivalencia.md`](../../TP5/docs/verificacion_equivalencia.md).

### 4.4 Verificación

- Tests escritos antes del código y comprobados con mutaciones: [`test_roles.sql`](../../TP5/sql/test_roles.sql), [`test_usuario_anon.sql`](../../TP5/sql/test_usuario_anon.sql), [`auditoria_test.sql`](../../TP5/sql/auditoria_test.sql), [`test_anonimizar_log.py`](../../TP5/scripts/test_anonimizar_log.py).
- Evidencia ejecutable: [`verificacion_permisos.md`](../../TP5/docs/verificacion_permisos.md), [`verificacion_roles_salida.txt`](../../TP5/docs/verificacion_roles_salida.txt), [`log_auditoria_prueba.txt`](../../TP5/docs/log_auditoria_prueba.txt), [`log_simulacro_anonimizado.txt`](../../TP5/docs/log_simulacro_anonimizado.txt), [`informe_auditoria.md`](../../TP5/docs/informe_auditoria.md).
- Las propuestas dudosas de la IA se probaron en un clúster de ensayo antes de aceptarlas o descartarlas.
- Antes de entregar datos a una IA externa, se leyó el log crudo y se lo anonimizó.

### 4.5 Limitaciones de la evidencia de U5

- Las sesiones de Claude Code no tienen volcado literal; solo el pedido resumido en la bitácora.
- La parte E.3 de la bitácora reconoce que el trabajo de DeepSeek del 26/10 se commiteó recién el 28/10, de modo que el historial de Git no muestra cuándo se produjo cada cosa.

---

## 5. Unidad 6: mantenimiento, respaldo y recuperación

### 5.1 Herramientas y finalidad

- **Herramienta**: Claude Code (Claude Opus 5.5) para todo el TP, con un agente revisor de solo lectura que revisó el diff antes de cada commit. La consigna sugiere OpenCode; el reemplazo está autorizado (sección 1.2).
- **Finalidad**: redactar la especificación del plan, el respaldo (`backup_foodstore.ps1`), el chequeo de salud (`health_check.sql`), el mantenimiento (`maintenance.sql`), la restauración de prueba (`restore_test.ps1`), la verificación de integridad con `amcheck` (`integrity_check.sql`), el registro de las tareas programadas y el informe de una página.

### 5.2 Prompts o specs usados

- **Spec**: [`TP6/SPEC_U6.md`](../../TP6/SPEC_U6.md), con la tabla de tareas, condiciones de éxito, reglas de seguridad, validación de la restauración y objetivos RPO/RTO. Su regla 6 establece que los scripts los genera un asistente de IA y que ningún comando se ejecuta sin leerlo antes y probarlo, incluido su caso de error. La SPEC fue el primer producto que se le pidió a la IA (registro 2).
- **Prompts**: [`TP6/BITACORA.md`](../../TP6/BITACORA.md), 11 registros con pedido, respuesta y verificación o corrección. Algunos pedidos están citados (por ejemplo, "Necesito que realicemos el TP6, será necesario analizar el estado actual del proyecto"; "Seguir con Parte 3"; "Seguir con Parte 4"; "Seguir con Parte 5") y otros solo descriptos (registros 2, 4, 6, 8, 10 y 11).

### 5.3 Qué se aceptó, rechazó o corrigió

Fuente: [`TP6/BITACORA.md`](../../TP6/BITACORA.md).

- **Registro 3.** Cuatro defectos del respaldo detectados al ejecutar: `$PSScriptRoot` vacío en PowerShell 5.1 (corregido); acentos desfigurados en el log y respaldos que podían quedar colgados ante un bloqueo (ambos solo **mitigados**, y así se declara); y una prueba de bloqueo que pasaba sin bloquear nada (se rehízo verificando el bloqueo en `pg_locks`).
- **Registro 5.** Tres defectos en el chequeo de salud y el mantenimiento: un cálculo de tamaño que esperaba detrás de los bloqueos que el mismo chequeo debía mostrar, una regla "tiene filas" que no detectaba nada en una base recién restaurada y un test que dependía del estado de `foodstore`. Una mutación "pasó" porque `sed` no había aplicado el cambio, y se rehízo contando los reemplazos. La IA había atribuido el primer problema a su escenario de prueba; el equipo lo descartó consultando desde otra sesión.
- **Registro 6.** El revisor señaló que `maintenance.sql` repetía el defecto ya corregido en `health_check.sql`. El equipo descartó la alternativa del revisor (`relpages`/`reltuples`, que falla justo en las tablas nunca analizadas) y usó su otra propuesta (consultar `pg_locks` primero).
- **Registro 7.** Dos defectos de PowerShell de la IA, detectados por el test, y un defecto del propio test. El equipo aceptó que la IA no mutara el control de la base destino, porque la mutación habría borrado `foodstore`. El simulacro (RPO 42 min 49 s, RTO 13,0 s, 7 de 7 validaciones) dejó ver que la vista materializada de `foodstore` estaba desactualizada (1 fila contra 13).
- **Registro 8 (caso más significativo).** El test de la IA usaba `foodstore` como destino del caso de rechazo, de modo que si el control fallaba el test habría borrado la base principal. No lo detectaron las pruebas sino la revisión del diff. Se pasó a una base canario descartable. Además se agregó un caso de mayúsculas, que falló primero (RED) y expuso que el control no las distinguía (`-ne`); se corrigió con `-cne`.
- **Registro 10 (decisión humana).** Inicio de sesión `Interactive`, para no guardar la contraseña de Windows. Corregido al probar: el envoltorio se cortaba sin escribir el log por cómo PowerShell 5.1 trata el stderr de psql, y `restore_test.ps1` no habría encontrado el respaldo de otra base (se agregaron `-Origen` y `-Database`).
- **Registro 11 (decisión humana).** Verificación de integridad en un script aparte y semanal, porque `health_check.sql` es de solo lectura y `CREATE EXTENSION` escribe.
- **Correcciones de redacción.** En los registros 4 y 9 se cambió "corregidos" por "mitigados" y se corrigió una afirmación imprecisa sobre `lock_timeout`.

### 5.4 Verificación

- Tests en bases descartables, escritos antes que los scripts: [`test_maintenance.sh`](../../TP6/tests/test_maintenance.sh), [`test_restore.sh`](../../TP6/tests/test_restore.sh), [`test_integrity.sh`](../../TP6/tests/test_integrity.sh). Se comprobaron con mutaciones (4 de 4 detectadas en el registro 5; una quinta en el 6; `heapallindexed => false` en el 11).
- Revisión del diff por un agente de solo lectura antes de cada commit (registros 4, 6 y 8).
- Ejecución manual de los casos de éxito y de error, con evidencia en [`TP6/evidencias/`](../../TP6/evidencias/): [`parte2_respaldo.md`](../../TP6/evidencias/parte2_respaldo.md), [`parte3_monitoreo_mantenimiento.md`](../../TP6/evidencias/parte3_monitoreo_mantenimiento.md), [`parte4_simulacro.md`](../../TP6/evidencias/parte4_simulacro.md), [`parte3_integridad.txt`](../../TP6/evidencias/parte3_integridad.txt), [`parte2_tareas_programadas.txt`](../../TP6/evidencias/parte2_tareas_programadas.txt).
- Las cifras del informe se cotejaron con [`parte4_simulacro_detalle.txt`](../../TP6/evidencias/parte4_simulacro_detalle.txt). La sección 7 del [informe de U6](../../TP6/informe/informe_u6.html) repite este resumen de uso de IA.
- Las cinco tareas, lanzadas desde el Programador de tareas de Windows, terminaron con resultado 0 (registro 11).

### 5.5 Limitaciones de la evidencia de U6

- Los pedidos de la bitácora están citados solo en parte; no hay volcado completo de la conversación.
- La SPEC habla de 5 tareas (la quinta, la integridad, se agregó en la segunda entrega); el registro 10 menciona 4 porque describe el estado anterior a ese agregado.

---

## 6. Unidad 7: NoSQL (PostgreSQL frente a MongoDB)

### 6.1 Herramientas y finalidad

- **Claude Code**: según [`TP7/README.md`](../../TP7/README.md), "todo el TP se hizo con Claude Code". Eso abarca el estado del pedido, la selección de pedidos, la migración a MongoDB, el validador de la colección, las consultas en los dos motores, los tests y el informe. **El modelo usado en U7 no está documentado en los archivos de la unidad.**
- **Agente de IA aislado (Claude Sonnet)**, lanzado desde Claude Code el 01/11/2026, sin acceso a la conversación, al repositorio ni a la base, y sin herramientas, para la consigna 6 (consulta a una IA sobre PostgreSQL frente a MongoDB).

### 6.2 Prompts o specs usados

- **Consigna 6, prompt literal**: transcripto completo en [`TP7/docs/ia/consulta_ia.md`](../../TP7/docs/ia/consulta_ia.md). Resumen: describe el modelo relacional de Food Store (pedido, pedido_detalle con precio histórico y clave compuesta, producto, cliente), el acceso más frecuente (leer pedidos completos) y la exigencia de coherencia entre cantidades, precios, subtotal y total; pide comparar ambos motores, cómo modelar en MongoDB y una recomendación, en no más de 700 palabras y sin herramientas. Respuesta literal: [`consulta_ia_respuesta.txt`](../../TP7/docs/ia/consulta_ia_respuesta.txt).
- **Resto del trabajo con Claude Code (modelo documental, migración, consultas, tests)**: **no hay prompts registrados**. U7 no tiene bitácora de IA ni spec de OpenSpec. Lo que existe son los productos y sus pruebas (sección 6.4) y la declaración de uso del README.

### 6.3 Qué se aceptó, rechazó o corrigió

Fuente: [`TP7/docs/contraste_ia.md`](../../TP7/docs/contraste_ia.md).

- **Recomendación final.** La IA recomendó combinar tecnologías (PostgreSQL como fuente de verdad, MongoDB solo como vista de lectura derivada). El equipo llegó a la misma recomendación, "pero por razones corregidas".
- **Afirmación 1, rechazada como incorrecta en lo que importa.** La IA dijo que la coherencia entre precio, subtotal y total en MongoDB queda "solo por código de aplicación" porque `$jsonSchema` no compara campos. El equipo la contrastó con la documentación oficial y con el laboratorio: el validador combina `$jsonSchema` con `$expr` y rechazó con el error 121 un subtotal incoherente, un total que no es la suma de los subtotales y un `updateOne` que intentaba desincronizar el total. El equipo agregó límites que la IA no mencionó (`bypassDocumentValidation` y validación solo por documento).
- **Afirmación 2, aceptada pero incompleta.** Las transacciones multi-documento existen desde la 4.0 y son más costosas, pero la IA omitió que una instalación standalone no las admite. El MongoDB del laboratorio es standalone y respondió `code 20 IllegalOperation`.
- **Afirmación confirmada.** El diferencial de lectura de MongoDB es pequeño a escala de tienda: 0,32 ms en PostgreSQL con cinco índices contra menos de 1 ms en MongoDB.
- **Modelo propuesto por la IA** (colección `pedidos` con cliente y líneas embebidos, `Decimal128`, validador, índices). El modelo final está documentado en [`modelo_documental.md`](../../TP7/docs/modelo_documental.md), pero las fuentes no permiten atribuir qué partes vinieron de la IA y cuáles de decisiones propias; por eso no se declara una atribución.

### 6.4 Verificación

- Tests: [`test_migracion.sh`](../../TP7/tests/test_migracion.sh) (10 violaciones de integridad, cada una rechazada por su propia regla) y [`test_consultas.sh`](../../TP7/tests/test_consultas.sh) (comparación automática de los ids entre los dos motores). Evidencia: [`parte2_tests.txt`](../../TP7/evidencias/parte2_tests.txt).
- Contraste de las afirmaciones de la IA con la documentación oficial de MongoDB (consultada el 01/11/2026) y con el laboratorio: [`parte3_contraste_mongodb.txt`](../../TP7/evidencias/parte3_contraste_mongodb.txt) y [`parte3_lectura_pedido_completo.txt`](../../TP7/evidencias/parte3_lectura_pedido_completo.txt).
- Tabla de verificación de consultas: [`consultas_verificacion.md`](../../TP7/docs/consultas_verificacion.md).

### 6.5 Limitaciones de la evidencia de U7

- **Evidencia delgada**: solo la consulta de la consigna 6 tiene prompt y respuesta literales. El trabajo con Claude Code no deja bitácora; la única constancia es la declaración del README y los scripts con sus tests.
- Los 9 pedidos migrados son una muestra y el MongoDB del laboratorio es standalone (límites declarados en el informe consolidado).

---

## 7. Unidad 8: base SQLite de la tablet y cierre de la capa de datos

### 7.1 Herramientas y finalidad

- **Claude Code con OpenSpec (OPSX)**, en lugar de Kiro y OpenCode. El desvío está declarado en el propio TP ([`DUIA.md`](../../TP8/docs/DUIA.md), sección 1) y en la sección 6.1 del informe consolidado.
- **Finalidad**: andamiaje del esquema SQLite `STRICT`, de la vista y de la importación; andamiaje y test del semáforo de sincronización; scripts de prueba; plan de mantenimiento y requisitos en formato EARS; y la revisión estática (code review) de 107 scripts de TP1 a TP8 mediante un subagente de Claude de solo lectura.

### 7.2 Prompts o specs usados

- **Spec (en lugar de Kiro)**: change de OpenSpec archivado [`2026-11-01-tp8-tablet-sqlite-sync`](../../TP8/openspec/changes/archive/2026-11-01-tp8-tablet-sqlite-sync/) con [`proposal.md`](../../TP8/openspec/changes/archive/2026-11-01-tp8-tablet-sqlite-sync/proposal.md), [`design.md`](../../TP8/openspec/changes/archive/2026-11-01-tp8-tablet-sqlite-sync/design.md), [`tasks.md`](../../TP8/openspec/changes/archive/2026-11-01-tp8-tablet-sqlite-sync/tasks.md) y cuatro specs delta; specs vigentes en [`TP8/openspec/specs/`](../../TP8/openspec/specs/). Según el README del TP8, la spec se escribió y commiteó antes que el código. Los tres documentos en formato Kiro ([`requirements.md`](../../TP8/docs/kiro/requirements.md), [`design.md`](../../TP8/docs/kiro/design.md), [`tasks.md`](../../TP8/docs/kiro/tasks.md)) se derivaron de ese change.
- **Prompt del code review (literal)**: sección 2 de [`code_review_ia.md`](../../TP8/docs/code_review_ia.md) ("Sos un agente de code review de solo lectura...", con cuatro criterios: correctitud, integridad, seguridad, idempotencia y transacciones). La respuesta cruda del agente está en la sección 3 y la tabla de decisiones en la 4.
- **Bitácora**: [`bitacora_ia.md`](../../TP8/docs/bitacora_ia.md), tres registros (importación del CSV, semáforo, code review) con pedido, respuesta, qué se aceptó, qué se descartó y verificación.
- **DUIA propia del TP**: [`TP8/docs/DUIA.md`](../../TP8/docs/DUIA.md), que este documento resume y no duplica. Allí se declaran el desvío de herramientas, los ámbitos de aplicación, el rol humano y la confidencialidad.

### 7.3 Qué se aceptó, rechazó o corrigió

Fuentes: [`bitacora_ia.md`](../../TP8/docs/bitacora_ia.md), [`code_review_ia.md`](../../TP8/docs/code_review_ia.md) (sección 4) y [`DUIA.md`](../../TP8/docs/DUIA.md) (sección 3).

- **Rol humano.** La expresión `CASE` del semáforo ([`semaforo.sql`](../../TP8/movil/semaforo.sql)) la escribió una persona del equipo (modo aprendizaje); la IA dejó el andamiaje y el test y después solo la revisó. Las prioridades (el rechazo prima sobre el conflicto; un borrador vacío se rechaza) son decisión del equipo.
- **Aceptado**: crear la tabla `snapshot_servidor` tipada antes del `.import`; el andamiaje del semáforo; CORR-02 (filtro temprano en la vista temporal de TP7, medido con `EXPLAIN ANALYZE`: de 621.201 filas y 2.621 buffers a 12 filas y 64 buffers); INTEG-01 (`PRAGMA foreign_keys = ON` en cada conexión; comprobado que sin él se acepta un ítem de un producto inexistente).
- **Descartado, con prueba**:
  - Dejar que `.import` cree la tabla: con columnas TEXT, `max(stock)` devolvía 7 en lugar de 48. El equipo además corrigió una exageración de la IA (la comparación directa entre columnas sí funcionaba).
  - Implementar el semáforo en Python: ocultaría la lógica fuera del motor.
  - **CORR-01** ("aprobación fantasma de stock"): el comportamiento existe y se reprodujo, pero `SIMULADO_APROBADO` no es una venta ni una reserva; el control de stock entre ventas le corresponde al servidor ([`code_review_1.txt`](../../TP8/evidencias/code_review_1.txt)).
  - **CORR-03** (supuesta errata `PosgresSQL`): la carpeta del host se llama literalmente así; se dejaron ambas rutas ([`code_review_3.txt`](../../TP8/evidencias/code_review_3.txt)).
- **Cifras de la IA que no coincidían.** En CORR-02 la IA había dado ~24.000 a 18 buffers, ~85 a menos de 0,2 ms y un Index Scan sobre `pk_pedido_detalle` sin ningún `EXPLAIN` que lo respaldara; el plan real usa `idx_detalle_subtotal`. Se reemplazaron por las cifras medidas.
- **Hallazgos aceptados como "histórico"** (INTEG-02 e INTEG-03, sobre TP1 a TP6): se registran, pero no se modificaron los scripts de esas unidades.

### 7.4 Verificación

- Ocho scripts de test en [`TP8/tests/`](../../TP8/tests/) (esquema, importación, carga de caché, pruebas SQLite, semáforo con sus 9 ramas e idempotencia, vista, casos y documentos), que se corren con los comandos del [README](../../TP8/README.md).
- Evidencias por hallazgo del code review: [`code_review_1.txt`](../../TP8/evidencias/code_review_1.txt), [`code_review_2.txt`](../../TP8/evidencias/code_review_2.txt), [`code_review_2_explain.txt`](../../TP8/evidencias/code_review_2_explain.txt), [`code_review_3.txt`](../../TP8/evidencias/code_review_3.txt), [`code_review_integ01.txt`](../../TP8/evidencias/code_review_integ01.txt) e [`importacion_sin_tabla_previa.txt`](../../TP8/evidencias/importacion_sin_tabla_previa.txt).
- Comprobación de que PostgreSQL no cambió (línea base antes y verificación final), con [`linea_base.sql`](../../TP8/sql/linea_base.sql) y [`verificacion_final.sql`](../../TP8/sql/verificacion_final.sql), según el README del TP8.

### 7.5 Limitaciones de la evidencia de U8

- La bitácora tiene tres registros, que resumen decisiones y no cada interacción.
- La nota metodológica de `code_review_ia.md` describe al revisor como "agente de solo lectura de Claude (`research`)"; la sección 3 de ese archivo es su respuesta cruda.

---

## 8. Criterio general de verificación

En las cinco unidades se aplicó el mismo criterio, declarado en el informe consolidado (§6.1) y en la regla 6 de [`SPEC_U6.md`](../../TP6/SPEC_U6.md):

1. **Leer antes de ejecutar.** Ningún script o comando de una IA se ejecutó sin ser leído por una persona del equipo.
2. **Probar donde un error no cuesta.** Bases de copia (`tp4_foodstore`, `food_store_copia`), bases descartables creadas y borradas por los propios tests, clúster de ensayo en U5, o transacciones revertidas.
3. **Tests primero cuando fue posible.** Ciclo RED, GREEN, TRIANGULATE y REFACTOR en U4, y tests previos al script en U5, U6 y U8. Los tests de controles de seguridad se comprobaron con mutaciones (cambios deliberados que el test debe detectar) en U5 y U6.
4. **Contrastar con evidencia externa.** `EXPLAIN (ANALYZE, BUFFERS)` en U4 y U8, el catálogo de PostgreSQL en U5, el estado de `pg_locks` en U6, documentación oficial y laboratorio de MongoDB en U7.
5. **Mirar la evidencia cruda.** Los defectos más graves (la fuga de claves de U5-C2 y el test de U6 que apuntaba a `foodstore`) los detectó la lectura del log o del diff, no un test automático.
6. **Revisión independiente.** Agente revisor de solo lectura antes de cada commit en U6 y subagente de code review en U8; en U4 y U5, ejecución manual del autor.
7. **Descartar con fundamento.** Toda propuesta rechazada tiene su prueba o su motivo escrito (por ejemplo, las propuestas 1, 2, 4, 5 y 6 de U5-A-5, CORR-01 y CORR-03 de U8, y la afirmación 1 de U7).

## 9. Confidencialidad y datos

- Los datos de clientes, pedidos y productos son sintéticos y se generaron con fines académicos (lo declaran el [informe consolidado](TPI_FoodStore_Informe_Tecnico_Consolidado.md) en sus limitaciones y [`TP8/docs/DUIA.md`](../../TP8/docs/DUIA.md) en su sección 4).
- En U5 el log del simulacro se anonimizó (`anonimizar_log.py`) antes de entregárselo a OpenCode, y la sesión corrió en una carpeta aislada con los MCP de memoria desactivados. A la IA aislada de U7 no se le dio acceso al repositorio ni a la base.
- No se versionan contraseñas: en U6 la clave sale de `pgpass.conf` y los clientes se invocan con `-w` (regla 1 de la SPEC de U6); el README de TP8 indica lo mismo.

## 10. Limitaciones de este documento

- **U4 no tiene registro de prompts.** Lo declarado es lo que se puede atribuir con certeza a partir del change OPSX y del informe.
- **U7 no tiene registro de prompts para el trabajo con Claude Code**, salvo la consulta de la consigna 6, y no documenta el modelo usado.
- **U5, U6 y U8 resumen los pedidos a Claude Code**; no hay volcado literal de esas conversaciones. Solo las sesiones de OpenCode de U5 tienen texto literal extraído de su base local.
- Los nombres de modelos son los que declaran las bitácoras de cada unidad; los archivos no registran versiones más precisas.
- Este documento no agrega información que no esté en las bitácoras o en los artefactos enlazados.

**Equipo**: Matias Limina, Nicolas Monjelardi y Lautaro Aguero. Estudiantes de Bases de Datos II, Tecnicatura Universitaria en Programación, UTN.
