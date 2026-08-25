# Declaración de Uso de IA (DUIA) — Parte 2 (TP2)

| Campo | Completar |
|---|---|
| **Herramienta** | OpenCode (modelo `google/gemini-3.5-flash-lite`) |
| **Spec o prompt utilizado** | Generar la estructura y redacción detallada para el `informe_concurrencia.md` reproduciendo los escenarios de Lectura No Repetible, Espera por Bloqueo (`FOR UPDATE`) y Lectura Fantasma sobre las tablas del proyecto Food Store en PostgreSQL. |
| **Qué generó** | La estructura completa del informe de concurrencia con los comandos exactos de Sesión A y Sesión B, explicaciones técnicas de los niveles de aislamiento y la verificación en el motor. |
| **Qué se aceptó** | La estructura metodológica, los bloques de comandos SQL específicos para las tablas `producto` y `pedido` de Food Store, y las explicaciones sobre MVCC y bloqueos en PostgreSQL. |
| **Qué se modificó o descartó, y por qué** | Se ajustaron los ejemplos de valores y sentencias SQL para que coincidan exactamente con los datos de carga inicial (`seed.sql`) del proyecto Food Store. |
| **Verificación realizada** | Ejecución práctica en dos sesiones paralelas de `psql` / DBeaver, confirmando el comportamiento de `READ COMMITTED` vs `REPEATABLE READ` y la retención de bloqueos con `FOR UPDATE`. |
