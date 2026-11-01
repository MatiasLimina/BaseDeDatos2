# Bitácora de uso de IA - TP8

Integrantes: (completar con los integrantes del equipo)

Herramienta: Claude Code + OpenSpec (OPSX), en lugar de Kiro/OpenCode que pedía la consigna.

| # | Pedido | Respuesta relevante | Qué se aceptó | Qué se descartó y por qué | Verificación |
|---|--------|---------------------|---------------|---------------------------|--------------|
| 1 | Cómo cargar el CSV del servidor en SQLite sin perder los tipos | Propuesta de crear `snapshot_servidor` STRICT antes del `.import` (en `schema_sqlite.sql`), con las columnas de la vista | Crear la tabla tipada antes: `.import` convierte `'123'` en `123` y rechaza `t`/`f` o `12.50` en columnas enteras | Dejar que `.import` cree la tabla (todas las columnas TEXT). Se comprobó que con TEXT las comparaciones con expresiones, `max(stock)` y `ORDER BY stock` dan resultados de texto (`max(stock)` = 7, no 48; `5 > '48'` verdadero). Ojo: la comparación directa columna contra columna sí funcionaba, así que la afirmación de que "siempre es falso" era exagerada | `evidencias/importacion_sin_tabla_previa.txt` y `bash tests/test_importacion.sh` (CSV con `t`/`f` falla y deja la instantánea anterior) |
