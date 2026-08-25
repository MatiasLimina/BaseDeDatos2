# Declaración de Uso de IA (DUIA) — Parte 2 (TP2)

| Campo | Completar |
|---|---|
| **Herramienta** | OpenCode (modelo `google/gemini-3.5-flash-lite`) |
| **Spec o prompt utilizado** | Generar la estructura y redacción técnica para el archivo `informe_concurrencia.md` documentando la reproducción de tres escenarios de concurrencia: Espera por bloqueo (Lock Waiting), Lectura no repetible (Non-repeatable Read) y Lectura fantasma (Phantom Read) sobre el esquema Food Store en PostgreSQL. |
| **Qué generó** | La estructura completa del informe de concurrencia, incluyendo los comandos SQL exactos para ambas sesiones (Sesión A y Sesión B) en cada escenario, las explicaciones teóricas de la IA, y las conclusiones de verificación en el motor. |
| **Qué se aceptó** | La estructura de bloques por escenario, los scripts SQL orientados a las tablas `producto` y `pedido` de nuestro proyecto, y las explicaciones de MVCC y bloqueos a nivel de fila. |
| **Qué se modificó o descartó, y por qué** | Se ajustaron los IDs y nombres de los productos utilizados en los ejemplos (`id = 1`, `categoria_id = 1`) para que coincidan exactamente con los datos de prueba definidos en nuestro archivo `seed.sql`. |
| **Verificación realizada** | Se ejecutaron los scripts concurrentemente en dos pestañas de DBeaver contra `foodstore_copia`, confirmando que los bloqueos de fila, las lecturas no repetibles y las lecturas fantasma se comportaron exactamente como se documentó en el informe. |
