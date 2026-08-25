# Declaración de Uso de IA (DUIA) — Parte 3 (TP2)

| Campo | Completar |
|---|---|
| **Herramienta** | OpenCode (modelo `google/gemini-3.5-flash-lite`) |
| **Spec o prompt utilizado** | Analizar críticamente los scripts provistos en la consigna del TP2 (actualización masiva sin WHERE y eliminación con NOT IN vulnerable a NULLs), identificar sus fallas reales y redactar el documento `ejercicio_lectura_critica.md` con las correcciones correspondientes. |
| **Qué generó** | La explicación detallada del impacto de omitir la cláusula `WHERE` en sentencias `UPDATE` y el comportamiento de la lógica trivaluada de SQL con `NOT IN` frente a valores `NULL` en sentencias `DELETE`. |
| **Qué se aceptó** | La argumentación técnica sobre el impacto de ejecución masiva y el uso de subconsultas correlacionadas con `NOT EXISTS` como solución robusta. |
| **Qué se modificó o descartó, y por qué** | Se adaptó el contexto del Script 1 al dominio del proyecto Food Store para mantener la coherencia con el esquema de base de datos desarrollado. |
| **Verificación realizada** | Revisión conceptual y teórica de la semántica de operadores SQL en PostgreSQL, confirmando que `NOT IN` con `NULL` anula el filtro y que un `UPDATE` sin `WHERE` afecta a toda la tabla. |
