# Handoff: segunda entrega del TPI (Unidades 4 a 8)

Estado al 12/11/2026. Rama `main`, sincronizada con `origin/main` (último commit `269d133`).

## Contexto

- La consigna de la segunda entrega pide evidencia verificable de cada objetivo de U4 a U8, más un informe técnico. **Si falta evidencia de un punto, la entrega cuenta como incompleta.**
- **No hay defensa oral** en esta entrega: el informe tiene que alcanzar solo.
- **Acuerdos con el profesor (aprobados en clase):** el ciclo OPSX/OpenSpec reemplaza a los specs de Kiro, y Claude Code reemplaza a OpenCode. Está documentado en la §6.1 del informe consolidado.
- El trabajo de cada unidad vive en su carpeta (`TP4/` a `TP8/`). `Proyecto_Integrador/` no copia archivos: el informe enlaza a esas carpetas con rutas relativas (`../../TP5/...`).
- TP7 y TP8 se importaron desde el repo `nicolasmonjelardi/BaseDeDatos2-TP7-NoSQL` (commits `d63197e`, `6e0c183` y la reorganización `399929e`). Se verificó que `TP8/` es idéntica al último commit de ese repo.

## Qué se hizo en esta sesión

| Commit | Contenido |
|---|---|
| `18d7005` | Informe consolidado extendido a U4–U8: matriz de trazabilidad §1.2 (14 filas, una por punto de la consigna), §6.1 herramientas sustitutas, filas de DUIA de TP4 a TP8, §8.6 y §9 a §12 por unidad, conclusiones con limitaciones conocidas. |
| `9ae8d8d` | TP6: tareas programadas en el Programador de tareas de Windows (`registrar_tareas.ps1`, `ejecutar_sql.ps1`), parámetro `-Origen` en `restore_test.ps1`. |
| `269d133` | TP6: verificación semanal de integridad con `amcheck` (`integrity_check.sql`, `tests/test_integrity.sh`). U6 pasa a **Cumplido** en la matriz. |

### Plan de mantenimiento del TP6 (estado actual)

5 tareas en `\FoodStore\` del Programador, registradas en la PC de Matias contra `food_store_copia` (ahí no existe `foodstore`):

| Tarea | Horario |
|---|---|
| Respaldo (`backup_foodstore.ps1`) | diaria 02:00 |
| Chequeo de salud (`health_check.sql`) | diaria 02:30 |
| Mantenimiento (`maintenance.sql`) | domingo 03:00 |
| Restauración de prueba (`restore_test.ps1`) | domingo 03:30 |
| Integridad (`integrity_check.sql`) | domingo 04:00 |

Las 5 corrieron desde el Programador con resultado 0 (evidencia en `TP6/evidencias/parte2_tareas_programadas*.txt` y `parte3_integridad.txt`). Para registrarlas en otra PC (PowerShell, desde `TP6\`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\registrar_tareas.ps1 -Database <base> -ProbarAhora
Get-Content .\logs\tareas_programadas.log -Tail 1     # debe decir OK
```

Requisito: `%APPDATA%\postgresql\pgpass.conf` con una línea `localhost:5432:*:postgres:<contraseña>`, guardado en ASCII o UTF-8 **sin BOM**. Para quitar las tareas: `.\registrar_tareas.ps1 -Quitar`.

## Avance de la sesión siguiente (12/11/2026, sin commitear al escribir esto)

- Pendiente 1 resuelto: `Proyecto_Integrador/documentos/DUIA_U4_U8.md`, enlazado desde la §6 del consolidado. Declara como brechas: U4 sin log de prompts (se usa el change OPSX) y U7 sin prompts registrados salvo la consulta de la consigna 6.
- Pendiente 2 resuelto: 71 rutas corregidas en `TP8/docs/code_review_ia.md`, más la prosa de `TP8/README.md`. Quedan a propósito sin tocar el change archivado de `TP8/openspec/` y la salida capturada de `psql` en las evidencias, porque son registro histórico.
- Pendiente 3 resuelto: la §3.1 ya no dice 16.2 (dice 16+ como referencia, más las versiones efectivas 18.6 y 17.11), y se corrigió la limitación «Integración pendiente» en `TP4/informe_tp4.md` y en su copia `Proyecto_Integrador/documentos/informe_tp4.md`.
- Siguen abiertos: el pendiente 4 (salvedades, decisión del equipo) y el pendiente 5 (PDF).

## Pendientes, por prioridad

1. **DUIA unificado de U4 a U8.** Hoy hay DUIA sólo en TP2, TP3 y TP8; bitácoras sueltas en TP5 (`BITACORA.md`), TP6 (`BITACORA.md`) y TP7 (`docs/ia/`). **TP4 no tiene bitácora de prompts**: lo declarado sale del change OPSX (`openspec/changes/archive/2026-10-18-tp4-fnbc-desnormalizacion/`). La consigna exige herramienta, finalidad y prompts o specs usados.
2. **73 rutas al repo viejo en TP8.** `TP8/docs/code_review_ia.md` (y evidencias `c2_preparar_pg.txt`, `c4_preparar_pg.txt`, `restaurar_casos.txt`) usan `../../BaseDeDatos2/...` y mencionan el repositorio «BasesNoRelacionales». Ahora todo está en este repo: las rutas no resuelven. `TP8/README.md` también dice que el TP8 vive en el repo del TP7.
3. **Inconsistencias del informe consolidado:**
   - Versión de PostgreSQL: la §3.1 dice 16.2, el TP4 usó 18.6 y TP5–TP7 usaron 17.11.
   - `TP4/informe_tp4.md` dice en "Limitaciones" que los scripts no están integrados a `Proyecto_Integrador/`, pero la §8 del consolidado ya los integró.
4. **Salvedades que siguen abiertas** (documentadas en la §1.2 y §7 del informe; decidir si se cierran o quedan declaradas):
   - U4: prueba manual 27 (concurrencia) sólo corrida en vivo en la variante 1; los `tp4_*.sql` integrados nunca se corrieron completos con `psql -f`.
   - U4/U5: `tp4_fnbc_control_lote.sql` hace `DROP TABLE usuario CASCADE` y pisa la tabla `usuario` del TP5.
   - U6: vista materializada `mv_facturacion_categoria_mes` desactualizada en `foodstore` (1 fila contra 13 en la restaurada).
5. **`TP4/TP_U4_FNBC_Desnormalizacion_FoodStore.pdf`** sin trackear (es la consigna del TP4): commitearlo o ignorarlo.

## Archivos clave

- `Proyecto_Integrador/documentos/TPI_FoodStore_Informe_Tecnico_Consolidado.md`: informe de las dos entregas. Empezar por la §1.2 (matriz) y sus salvedades.
- `TP6/SPEC_U6.md`, `TP6/registrar_tareas.ps1`, `TP6/integrity_check.sql`: plan de mantenimiento.
- `openspec/changes/archive/2026-10-18-tp4-fnbc-desnormalizacion/design.md`: spec de la migración del TP4 con el plan de reversión.
- `TP8/docs/code_review_ia.md`: code review de toda la cursada (rutas a corregir).

## Avisos

- No hacer push de `.engram/`: el repo es público y hoy no versiona la memoria.
- En la PC de Matias, PostgreSQL está en `D:\DevTools\PosgresSQL\bin` (18.6). Bases útiles: `food_store_copia` (copia de trabajo, 621 201 detalles), `tp4_foodstore` (esquema del TP4), `foodstore_restore_test` (la recrea la restauración de prueba).
- Se acordó trabajar directo en `main`, sin ramas.
