# Desglose de Tareas de Implementación - TP8

## Fase 1: Entorno, Línea Base y Esquema Móvil SQLite
- [x] **TASK-01**: Configurar atributos de fin de línea en `.gitattributes` para compatibilidad LF/CRLF entre Git Bash y Windows.
- [x] **TASK-02**: Diseñar y crear `movil/schema_sqlite.sql` con tablas STRICT (`clientes`, `productos`, `pedidos`, `items_pedido` y `snapshot_servidor`) y activación de `PRAGMA foreign_keys = ON`.
- [x] **TASK-03**: Redactar suite de verificación de tipos `tests/test_esquema_sqlite.sh` demostrando rechazo de coerción errónea.

## Fase 2: Snapshot e Integración Asimétrica Servidor-Tablet
- [x] **TASK-04**: Crear en PostgreSQL la vista `sql/01_v_snapshot_movil.sql` y el script de exportación CSV `sql/02_exportar_snapshot.sql`.
- [x] **TASK-05**: Implementar `movil/importar_snapshot.sql` con lógica de UPSERT e idempotencia conservando flags locales.
- [x] **TASK-06**: Diseñar pruebas automáticas de importación `tests/test_importacion.sh` y verificación de cache `tests/test_carga_cache.sh`.

## Fase 3: Pruebas Unitarias de Integridad en SQLite
- [x] **TASK-07**: Implementar `movil/pruebas_sqlite.sql` para forzar violaciones de CHECK, UNIQUE, NOT NULL y FOREIGN KEY.
- [x] **TASK-08**: Automatizar suite `tests/test_pruebas_sqlite.sh` validando código de salida e integridad.

## Fase 4: Semáforo Offline y Casos de Prueba C1 a C7
- [x] **TASK-09**: Desarrollar `movil/semaforo.sql` implementando la lógica declarativa de priorización `CASE` (Verde, Amarillo, Rojo).
- [x] **TASK-10**: Desarrollar suite de prueba sintética `tests/test_semaforo.sh` validando las 9 combinaciones posibles.
- [x] **TASK-11**: Escribir scripts SQL para cada caso de simulación (`movil/casos/caso_c[2-6].sql`).
- [x] **TASK-12**: Escribir scripts SQL de preparación y restauración en PostgreSQL (`sql/casos/`).
- [x] **TASK-13**: Integrar el orquestador general `scripts/correr_casos.sh` y la suite de validación `tests/test_casos.sh`.

## Fase 5: Operaciones, Mantenimiento y Code Review con IA
- [x] **TASK-14**: Diseñar el plan de mantenimiento preventivo y de recuperación ante desastres `docs/plan_mantenimiento_tp8.md` con procedimiento de respaldo en caliente vía `VACUUM INTO`.
- [x] **TASK-15**: Completar las secciones 3.a y 3.b en `informe/informe.html`.
- [x] **TASK-16**: Desplegar subagente de IA de solo lectura para auditoría técnica de los 107 scripts de la cursada.
- [x] **TASK-17**: Analizar hallazgos, registrar aceptaciones y justificar descartes (CORR-01 y CORR-03) en `docs/code_review_ia.md` y `docs/bitacora_ia.md`.

## Fase 6: Documentación Formal, Requisitos EARS y DUIA
- [x] **TASK-18**: Exportar especificación formal en formato EARS en `docs/kiro/requirements.md` vinculada a casos C1-C7.
- [x] **TASK-19**: Documentar arquitectura técnica en `docs/kiro/design.md` y desglose en `docs/kiro/tasks.md`.
- [x] **TASK-20**: Elaborar la Declaración de Uso de Inteligencia Artificial en `docs/DUIA.md`.
- [x] **TASK-21**: Redactar `tests/test_docs.sh` para validación automática de requisitos de documentación.

## Fase 7: Reproducibilidad, Informe PDF y Cierre
- [ ] **TASK-22**: Documentar flujo de reproducción paso a paso de punta a punta en `README.md`.
- [ ] **TASK-23**: Implementar generador de informe PDF `informe/generar_pdf.sh` respetando límite de 6 páginas.
- [ ] **TASK-24**: Validación final integral de todas las suites de prueba en `tests/`.
