# Declaración de Uso de IA (DUIA) — Parte 3 (TP2)

| Campo | Completar |
|---|---|
| **Herramienta** | OpenCode (modelo `google/gemini-3.5-flash-lite`) |
| **Spec o prompt utilizado** | Analizar críticamente los scripts provistos en la consigna (Script 1 sin WHERE y Script 2 con NOT IN vulnerable a NULLs) y redactar el análisis de impacto y su corrección para el archivo `ejercicio_lectura_critica.md`. |
| **Qué generó** | La explicación detallada de por qué el Script 1 afecta a toda la tabla por falta de WHERE y por qué el Script 2 falla debido al comportamiento de NULLs con el operador NOT IN, junto con las alternativas usando NOT EXISTS. |
| **Qué se aceptó** | Todo el análisis teórico y las propuestas de corrección con `NOT EXISTS` y `IS NOT NULL`. |
| **Qué se modificó o descartó, y por qué** | Ninguna modificación requerida; el análisis lógico es riguroso y coincide con las directivas de seguridad de la cátedra. |
| **Verificación realizada** | Validación conceptual mediante teoría de bases de datos relacionales sobre el comportamiento tri-valorado de SQL (`TRUE`, `FALSE`, `UNKNOWN`) ante valores `NULL` en operadores `NOT IN`. |
