# Declaración de Uso de Inteligencia Artificial (DUIA)

**Asignatura**: Bases de Datos II  
**Trabajo Práctico**: TP8 - "La base de la tablet (SQLite) y el cierre de la capa de datos"  
**Carrera**: Licenciatura / Tecnicatura en Informática - Universidad  

---

## 1. Identificación de Herramientas y Desviación Metodológica

Para el desarrollo del presente Trabajo Práctico, el equipo ha utilizado la herramienta de asistencia técnica:
- **Claude Code** (asistente de ingeniería por línea de comandos) asistido por el estándar de especificación formal **OpenSpec (OPSX)**.

### Declaración de Desvío respecto de Kiro / OpenCode
La consigna de la cátedra sugería originalmente el uso de **Kiro** y **OpenCode** para la generación de especificaciones y asistencia. 
El equipo optó formalmente por utilizar **Claude Code** junto con **OpenSpec** debido a las siguientes razones técnicas:
1. **Compatibilidad con el entorno de trabajo**: Claude Code ofrece integración directa con terminales Windows y entornos emulados (Git Bash / PowerShell), permitiendo la ejecución y validación de suites de pruebas automáticas en tiempo real.
2. **Control de versiones y granularidad**: OpenSpec permite mantener artefactos versionables en texto plano alineados con el repositorio Git.
3. **Generación equivalente de artefactos**: Para cumplir fielmente con los requisitos pedagógicos de la cátedra, todos los requisitos EARS, diseño de arquitectura y desglose de tareas han sido estructurados y exportados en el directorio `docs/kiro/` (`requirements.md`, `design.md`, `tasks.md`), garantizando completa compatibilidad con lo solicitado.

---

## 2. Ámbitos de Aplicación de la IA en el TP8

La inteligencia artificial fue empleada en las siguientes tareas específicas:
1. **Generación de andamiajes de código SQL y Bash**:
   - Estructuración de esquemas tipados SQLite (`schema_sqlite.sql`) con modificador `STRICT`.
   - Consulta CTE para el semáforo de sincronización offline con lógica declarativa `CASE`.
   - Scripts de prueba automatizada bajo enfoque TDD estricto en la carpeta `tests/`.
2. **Revisión estática de código (Code Review)**:
   - Despliegue de un subagente de análisis estático en modo de solo lectura para auditar los 107 scripts del repositorio (TP1 a TP8).
   - Generación de informe inicial de hallazgos sobre integridad, idempotencia y seguridad.
3. **Estructuración de documentación y requisitos**:
   - Formulación de requisitos en sintaxis formal EARS (*Easy Approach to Requirements Syntax*).
   - Redacción de planes de mantenimiento preventivo y contingencia.

---

## 3. Rol Humano: Supervisión Crítica (Modelo CASE)

De acuerdo a las pautas éticas y académicas de la cátedra, el equipo humano mantuvo el control absoluto de las decisiones de diseño, actuando bajo el modelo **CASE** (*Control, Análisis, Supervisión y Evaluación*).

La intervención de la IA nunca fue aceptada acríticamente. Como evidencia de supervisión humana efectiva, se destacan los siguientes descartes técnicos fundamentados:
- **Descarte de CORR-01 (Aprobación fantasma de stock)**: La IA sugirió erróneamente que la tablet no podía emitir `SIMULADO_APROBADO` sin decrementar stock. El criterio humano prevaleció: en una arquitectura *offline-first*, la tablet únicamente simula la factibilidad sobre su instantánea local; la verdadera reserva atómica y bloqueo transaccional concurrente ocurren en PostgreSQL durante la sincronización definitiva.
- **Descarte de CORR-03 (Falso positivo en ruta de instalación)**: La IA detectó una supuesta errata léxica en la ruta `PosgresSQL`. La inspección física del sistema de archivos demostró que la carpeta real de instalación del motor en el host del usuario se denomina literalmente `D:\DevTools\PosgresSQL`. Modificar el script según la sugerencia de la IA hubiera provocado la falla catastrófica de los comandos `psql`.
- **Descarte de importación no tipada**: La sugerencia de dejar que SQLite creara la tabla dinámicamente con `.import` fue descartada al comprobarse empíricamente que la coerción léxica provocaba fallos lógicos en consultas de agregación y ordenamiento numérico.

---

## 4. Confidencialidad y Protección de Datos

El equipo certifica que:
- No se han compartido con los modelos de IA datos personales reales de usuarios, clientes o personal de la institución.
- Todos los conjuntos de datos empleados en clientes, pedidos y productos corresponden a datos sintéticos generados para fines académicos.
- No se han expuesto credenciales reales ni cadenas de conexión con privilegios de producción.
