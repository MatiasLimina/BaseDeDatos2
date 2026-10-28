# Reconstrucción del incidente con OpenCode (consigna C.4)

| Dato | Valor |
|---|---|
| Herramienta | OpenCode CLI 1.18.18, agente `plan` (solo lectura) |
| Modelo | `google/gemini-3.5-flash` |
| Sesión | `ses_e7c3d2502ffeRtmOrf4RxNAxNE` |
| Fecha | 2026-10-28, 15:25:45 a 15:26:20 |
| Entrada | `docs/log_simulacro_anonimizado.txt` (corrida `20261028T152428`), copiado como `log.txt` |

## Sin contexto adicional

La consigna pide entregar el log "sin agregar contexto adicional al que el log ofrece". Por eso:

- OpenCode corrió en una carpeta vacía que solo contenía `log.txt` y un `opencode.json` que desactiva los MCP `engram` (memoria del proyecto) y `context7`. No tuvo acceso al repositorio, a los scripts ni a la memoria de sesiones anteriores. Las únicas herramientas que usó fueron dos `glob` sobre esa carpeta.
- El prompt no menciona Food Store, el TP, el simulacro ni lo ejecutado:

```text
Reconstruí qué ocurrió en este log y proponé una hipótesis de contención.
```

Comando, desde la carpeta aislada:

```bash
opencode run "Reconstruí qué ocurrió en este log y proponé una hipótesis de contención." -m google/gemini-3.5-flash --agent plan -f log.txt
```

El contraste con lo que el equipo ejecutó está en `docs/informe_incidente.md`.

---

## Respuesta completa de la IA (sin editar)

### 1. Reconstrucción de los Hechos (Línea de Tiempo y Análisis)

* **Fecha y Hora:** `2026-10-28 15:24:28` (Duración total de la sesión: 87 ms).
* **Origen y Contexto:** Conexión desde `::1` (localhost IPv6) usando el usuario de base de datos `app_web` sobre la base `foodstore_tp5` mediante el cliente `psql` (PID `27520`, Sesión `6ae23ddc.6b80`).

#### Secuencia de Eventos:
1. **Conexión y Autenticación a la BD (15:24:28.181 - 15:24:28.193):**
   * El cliente se conecta exitosamente a PostgreSQL como el usuario de sistema/aplicación `app_web` mediante el método `scram-sha-256`.

2. **Ataque de Fuerza Bruta / Adivinación de Credenciales (15:24:28.205 - 15:24:28.218):**
   * En un lapso de 13 milisegundos, se registran **5 intentos fallidos** consecutivos de ejecución de la función de catálogo/autenticación `fn_autenticar(text, text)` para la cuenta `usuario7@ejemplo.test`.

3. **Autenticación Exitosa en la Aplicación (15:24:28.221):**
   * Al 6.º intento, la función `fn_autenticar` retorna éxito para `usuario_id=7` (`usuario7@ejemplo.test`).

4. **Intento de Reconocimiento y Extracción de Datos (15:24:28.221 - 15:24:28.222):**
   * Inmediatamente después de validar la clave, el atacante intenta consultar la tabla `usuario` directamente vía SQL (`SELECT * FROM usuario;` y `SELECT id, nombre, apellido, mail, celular FROM usuario;`).
   * **Resultado:** Falló (`permission denied for table usuario`). El usuario `app_web` no posee permisos de lectura directa sobre la tabla.

5. **Intento de Escalada de Privilegios a Nivel de Base de Datos (15:24:28.222):**
   * El atacante intenta otorgarse el rol administrativo de la base de datos: `GRANT admin_datos TO app_web;`.
   * **Resultado:** Falló (`permission denied to grant role "admin_datos"`).
   * El atacante intenta asumir el rol: `SET ROLE admin_datos;`.
   * **Resultado:** Falló (`permission denied to set role "admin_datos"`).

6. **Intento de Escalada de Privilegios a Nivel de Aplicación (15:24:28.222):**
   * El atacante intenta modificar el rol del usuario directamente en la base de datos: `UPDATE usuario SET rol = 'ADMIN' WHERE mail = 'usuario7@ejemplo.test';`.
   * **Resultado:** Falló (`permission denied for table usuario`).

7. **Desconexión (15:24:28.261):**
   * La sesión finaliza tras 87 ms de actividad.

---

### 2. Diagnóstico y Estado de Seguridad

* **Ataque Exitoso a Nivel de Aplicación:** Se comprometieron las credenciales de la cuenta `usuario7@ejemplo.test` por fuerza bruta.
* **Ataque Fallido a Nivel de Base de Datos:** Los controles de acceso (principio de mínimo privilegio / RBAC) funcionaron adecuadamente a nivel de motor de base de datos. El usuario de conexión `app_web` no tenía permisos de `SELECT`, `UPDATE` ni administración de roles sobre la tabla `usuario`.

---

### 3. Propuesta de Hipótesis de Contención y Mitigación

#### A. Acciones Inmediatas de Contención (Corto Plazo)
1. **Bloqueo y Invalidación de Credenciales:**
   * Inhabilitar temporalmente la cuenta `usuario7@ejemplo.test` y forzar el reseteo de su contraseña.
   * Invalidar cualquier token o sesión activa asociada al `usuario_id=7`.
2. **Rotación de Credenciales de BD:**
   * Rotar la contraseña del usuario de base de datos `app_web`.
3. **Auditoría de Sesiones:**
   * Revisar en `pg_stat_activity` y en los logs si existen otras sesiones activas o previas provenientes del mismo origen o involucrando al usuario `usuario7@ejemplo.test`.
4. **Restricción de Acceso a Clientes de Consola (`psql`):**
   * Investigar cómo el atacante ejecutó la conexión mediante `psql` (posible acceso a consola/shell local, o credenciales expuestas en repositorios/configuración). Restringir permisos de ejecución de herramientas de cliente SQL en el servidor de aplicación.

#### B. Medidas de Mitigación Definitivas (Mediano/Largo Plazo)
1. **Protección contra Fuerza Bruta en `fn_autenticar`:**
   * Implementar un mecanismo de retardo exponencial (*rate limiting*) o bloqueo temporal de cuenta tras $N$ intentos fallidos dentro de la función PL/pgSQL o en la capa de aplicación.
2. **Política de Contraseñas Robustas:**
   * Exigir mayor complejidad y longitud en las contraseñas de los usuarios finales para evitar que sean adivinadas en pocos intentos.
3. **Monitoreo y Alertas Automatizadas:**
   * Configurar alertas en el sistema de monitoreo/SIEM ante ráfagas de advertencias `fn_autenticar: intento fallido` o errores repetidos de `permission denied`.
