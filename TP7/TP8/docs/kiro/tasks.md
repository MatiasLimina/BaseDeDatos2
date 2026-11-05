# Tareas: tablet con SQLite y sincronización simulada (TP8)

> Nota: estos documentos se derivan de OpenSpec (`openspec/changes/archive/2026-11-01-tp8-tablet-sqlite-sync/`) porque el equipo no usó Kiro. Mantienen el formato de tres archivos de Kiro. Las tareas reflejan los grupos de `tasks.md` de ese change.

## 1. Preparación
- [x] Spec de OpenSpec commiteada antes del código.
- [x] Herramientas verificadas y productos de los casos elegidos (`evidencias/productos_casos.txt`).

## 2. Esquema SQLite
- [x] `movil/schema_sqlite.sql` con tablas STRICT (`tests/test_esquema_sqlite.sh`).

## 3. Vista e instantánea en PostgreSQL
- [x] `sql/linea_base.sql` y `evidencias/linea_base.txt`.
- [x] `sql/01_v_snapshot_movil.sql` (`tests/test_vista_snapshot.sh`).
- [x] `sql/02_exportar_snapshot.sql`: CSV de S0.

## 4. Importación
- [x] `movil/importar_snapshot.sql` con guarda de filas (`tests/test_importacion.sh`).
- [x] Upsert al caché y lápida (`tests/test_carga_cache.sh`).
- [x] Importación real de S0 (`evidencias/importacion_s0.txt`).

## 5. Pruebas de la tablet (C1, C7)
- [x] `movil/pruebas_sqlite.sql` (`tests/test_pruebas_sqlite.sh`).
- [x] Salida guardada en `evidencias/c1_c7_pruebas_sqlite.txt`.

## 6. Semáforo
- [x] `movil/semaforo.sql` (`tests/test_semaforo.sh`).
- [x] `CASE` escrito por una persona del equipo y revisado.

## 7. Casos C2 a C6
- [x] Scripts SQLite: `movil/casos/c2_borrador.sql`, `c2_aceptar.sql`, `c3_borrador.sql`, `c4_borrador.sql`, `c5_c6.sql`.
- [x] Scripts PostgreSQL en `sql/casos/` y `sql/verificacion_final.sql`.
- [x] `scripts/correr_casos.sh` y evidencias de C2 a C6 (`tests/test_casos.sh`).
- [x] PostgreSQL igual que la línea base (`evidencias/verificacion_final_diff.txt`).

## 8. Mapa de motores y mantenimiento
- [x] Sección 3.a del informe.
- [x] `docs/plan_mantenimiento_tp8.md` y prueba de respaldo (`evidencias/respaldo_sqlite.txt`).

## 9. Code review con IA
- [x] Inventario, revisión y hallazgos en `docs/code_review_ia.md`.
- [x] Comprobaciones en `evidencias/code_review_1.txt`, `code_review_2.txt` y `code_review_3.txt`.

## 10. Spec exportada, bitácora y DUIA
- [x] `docs/kiro/requirements.md`, `design.md` y `tasks.md` (`tests/test_docs.sh`).
- [x] `docs/bitacora_ia.md` y `docs/DUIA.md`.

## 11. README e informe
- [x] `README.md` reproducible.
- [x] `informe/informe.html` y `informe/generar_pdf.sh` (máximo 6 páginas).

## 12. Integración y cierre
- [x] Reconstrucción desde cero y todos los tests en OK.
- [x] PostgreSQL en la línea base; sin datos personales en el `.db`.
- [ ] Revisión final del advisor (FINAL_DIFF).
- [x] `openspec validate --strict`.
- [ ] Etiqueta `tp8` y push, con confirmación del usuario.
