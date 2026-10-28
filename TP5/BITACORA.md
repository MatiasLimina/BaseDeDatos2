# Bitácora de uso de IA — TP Unidad 5 (Food Store)

Integrantes: Matias Limina - Nicolas Monjelardi - Lautaro Aguero

Formato pedido por la consigna: **Prompt enviado a la IA**, **Respuesta relevante recibida** (resumida) y **Validación o corrección humana aplicada**. Cada registro indica la herramienta usada.

> **Herramientas.** La consigna pide OpenCode como asistente principal. Los registros marcados *Claude Code* se hicieron con Claude Code (modelo Claude Opus 5.5) en la terminal del repositorio. Los marcados **PENDIENTE** los completa el equipo con la interacción real; no se completan con contenido supuesto.

---

## Parte A — Roles y permisos de mínimo privilegio

| # | Prompt enviado a la IA | Respuesta relevante recibida | Validación o corrección humana aplicada |
|---|---|---|---|
| A-0 | **PENDIENTE (equipo).** Prompts con los que se generaron la especificación de Kiro (`docs/kiro_roles_spec/`) y la primera versión de `sql/roles.sql` (commits `b1d5f1f` y `988ee44`). | — | — |
| A-1 | *Claude Code.* "Realizá un análisis del repositorio para saber en qué estado se encuentra el proyecto" (antes de arrancar el TP5). | Detectó que `roles.sql` daba por existentes la tabla `usuario` (con `mail`, `contrasena`, `rol`) y `fn_autenticar`, pero que ningún script del repositorio las creaba: la primera verificación se había corrido en un clúster aislado (`foodstore_fresh`) que ya no existe. También señaló que `tp4_fnbc_control_lote.sql` define **otra** tabla `usuario` y la borra con `DROP TABLE usuario CASCADE`. | Se confirmó con `grep` sobre todo el repositorio. Siguiendo la consigna ("si esos artefactos no se conservaron ... reconstruirlos"), se decidió reconstruirlos en `sql/usuario_autenticacion.sql` y advertir en su encabezado que no debe ejecutarse el script FNBC de TP4 sobre la misma base. |
| A-2 | *Claude Code.* "Arranquemos por terminar la Parte A y una vez realizada hacer el commit (commits atómicos)". | Reconstruyó `usuario` y `fn_autenticar` a partir del material de la Clase 2, con estos cambios: baja lógica por `activo` (regla R7) en lugar de `eliminado`, `CHECK` de formato bcrypt sobre `contrasena`, `contrasena` nullable para altas pendientes de activación y `fn_autenticar` en SQL parametrizado. | Se verificó ejecutando el script dos veces (idempotencia) sobre un clúster nuevo: 30 cuentas, autenticación correcta con la clave buena, 0 filas con la clave mala, 0 filas con la cuenta dada de baja y 0 filas con la inyección `' OR '1'='1' --` de la Clase 2. |
| A-3 | *Claude Code* (mismo pedido). Corregir los riesgos R2 y R10 que la verificación había dejado documentados pero abiertos. | Propuso quitarle a `admin_datos` `INSERT/UPDATE (rol)`, `INSERT (contrasena)` y `EXECUTE fn_resetear_password`, y revocar `crypt`/`gen_salt` de `PUBLIC`. Escribió primero `sql/test_roles.sql`, que falló contra la versión vigente (RED), y después corrigió `roles.sql` (GREEN). | Antes de aceptar el test se comprobó que detecta los defectos: se reintrodujo cada uno por separado (`crypt` a `PUBLIC`, `fn_resetear_password` a `admin_datos`, `INSERT (contrasena)` a `admin_datos`, `admin_datos` a `app_web` con `ADMIN OPTION`) y el test falló en los cuatro casos. La cadena de escalamiento de `verificacion_permisos.md` §5.5 se re-ejecutó a mano y ahora se corta en el primer paso (`permission denied`). |
| A-4 | *Claude Code* (mismo pedido). Recapturar la salida de `verificacion_roles.sql`. | Generó la nueva salida con `psql > archivo`. | **Error detectado:** al revisar el `git diff` de la salida aparecieron mensajes de psql desfigurados por la consola de Windows (`usar?`, `Replicacin`), es decir, la evidencia tenía texto alterado. Se corrigieron solo esas dos cadenas propias de psql (los datos del servidor llegaban bien en UTF-8), se validó que el archivo fuera UTF-8 válido y quedó anotado en `verificacion_permisos.md` §2. |
| A-5 | **PENDIENTE (equipo) — consigna A.4, con OpenCode.** Prompt sugerido: *"Auditá este archivo roles.sql de PostgreSQL 16 para Food Store. Proponé mejoras o correcciones de seguridad y de mantenimiento, indicando para cada propuesta la sentencia SQL exacta."* (adjuntar `sql/roles.sql`). | Resumir lo que proponga OpenCode. | Registrar al menos una propuesta **más amplia de lo necesario** (por ejemplo `GRANT ALL`, `GRANT ... ON ALL TABLES IN SCHEMA` o `CREATEROLE` para `admin_datos`) y por qué no se aplicó tal cual. Cada propuesta aceptada debe pasar `sql/test_roles.sql` y la recaptura de `verificacion_roles.sql`. |

---

## Parte B — Auditoría

*(pendiente)*

## Parte C — Simulacro de incidente

*(pendiente)*

## Parte D — Anonimización

*(pendiente)*

## Parte E — Cierre

*(pendiente: caso más significativo de error de la IA y revisión del historial de Git)*
