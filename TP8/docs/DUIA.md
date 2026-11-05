# Declaración de Uso de Inteligencia Artificial (DUIA)

**Asignatura**: Bases de Datos II  
**Trabajo Práctico**: TP8 - "La base de la tablet (SQLite) y el cierre de la capa de datos"  
**Carrera**: Tecnicatura Universitaria en Programación – UTN  

---

## 1. Identificación de Herramientas y Desviación Metodológica

Para el desarrollo del presente Trabajo Práctico, el equipo ha utilizado la herramienta de asistencia técnica:
- **Claude Code** (asistente de ingeniería por línea de comandos) junto con la herramienta de especificación **OpenSpec (OPSX)**.

### Declaración de Desvío respecto de Kiro / OpenCode
La consigna pide usar **Kiro** (especificaciones) y **OpenCode** (asistencia y code review). El equipo no los usó: trabajó con **Claude Code** y **OpenSpec**, y lo declara como desvío. Los motivos:
1. **Compatibilidad con el entorno de trabajo**: Claude Code ofrece integración directa con terminales Windows y entornos emulados (Git Bash / PowerShell), permitiendo la ejecución y validación de suites de pruebas automáticas en tiempo real.
2. **Control de versiones y granularidad**: OpenSpec permite mantener artefactos versionables en texto plano alineados con el repositorio Git.
3. **Generación equivalente de artefactos**: Para cumplir fielmente con los requisitos pedagógicos de la cátedra, todos los requisitos EARS, diseño de arquitectura y desglose de tareas han sido estructurados y exportados en el directorio `docs/kiro/` (`requirements.md`, `design.md`, `tasks.md`). Se derivan de los artefactos de OpenSpec y mantienen el formato de tres archivos de Kiro.

---

## 2. Ámbitos de Aplicación de la IA en el TP8

La inteligencia artificial fue empleada en las siguientes tareas específicas:
1. **Generación de andamiajes de código SQL y Bash**:
   - Estructuración de esquemas tipados SQLite (`schema_sqlite.sql`) con modificador `STRICT`.
   - `UPDATE … FROM (subconsulta)` del semáforo de sincronización, con una expresión `CASE`.
   - Scripts de prueba automatizada bajo enfoque TDD estricto en la carpeta `tests/`.
2. **Revisión estática de código (Code Review)**:
   - Despliegue de un subagente de análisis estático en modo de solo lectura para auditar los 107 scripts del repositorio (TP1 a TP8).
   - Generación de informe inicial de hallazgos sobre integridad, idempotencia y seguridad.
3. **Estructuración de documentación y requisitos**:
   - Formulación de requisitos en sintaxis formal EARS (*Easy Approach to Requirements Syntax*).
   - Redacción de planes de mantenimiento preventivo y contingencia.

---

## 3. Rol Humano: qué hizo el equipo

El equipo tomó las decisiones de diseño (dónde vive el TP, cómo se derivan `disponible` y `eliminado`, el alcance del code review, qué filas lleva el mapa) y aprobó cada cambio sobre la copia del servidor antes de ejecutarlo. La expresión `CASE` del semáforo (`movil/semaforo.sql`: rojo, amarillo, verde) la escribió el integrante humano; la IA dejó el andamiaje y el test, y después solo la revisó.

La intervención de la IA nunca fue aceptada acríticamente. Como evidencia de supervisión humana efectiva, se destacan los siguientes descartes técnicos fundamentados:
- **Descarte de CORR-01 (Aprobación fantasma de stock)**: La IA señaló que dos solicitudes de 2 unidades frente a un stock de 3 salen las dos `SIMULADO_APROBADO`. Se comprobó que es así y se descartó como error: `SIMULADO_APROBADO` no es una venta ni una reserva; cada solicitud se compara contra la instantánea, sin descontar nada. Controlar el stock entre varias ventas le corresponde al servidor cuando la venta se confirme, y eso queda fuera del TP8.
- **Descarte de CORR-03 (Falso positivo en ruta de instalación)**: La IA detectó una supuesta errata léxica en la ruta `PosgresSQL`. La inspección física del sistema de archivos demostró que la carpeta real de instalación del motor en el host del usuario se denomina literalmente `D:\DevTools\PosgresSQL`. Cambiar la ruta como sugería la IA habría dejado al script sin encontrar `psql` en esta máquina. Se dejaron las dos rutas en el `PATH`.
- **Descarte de importación no tipada**: La sugerencia de dejar que SQLite creara la tabla dinámicamente con `.import` fue descartada al comprobarse empíricamente que la coerción léxica provocaba fallos lógicos en consultas de agregación y ordenamiento numérico.

---

## 4. Confidencialidad y Protección de Datos

El equipo certifica que:
- No se han compartido con los modelos de IA datos personales reales de usuarios, clientes o personal de la institución.
- Todos los conjuntos de datos empleados en clientes, pedidos y productos corresponden a datos sintéticos generados para fines académicos.
- No se han expuesto credenciales reales ni cadenas de conexión con privilegios de producción.
