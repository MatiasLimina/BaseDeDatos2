# Verificación de equivalencia — usuario_anon (Unidad 5, Parte D)

## 1. La tabla anonimizada (D.1)

`sql/usuario_anon.sql` reconstruye `usuario_anon` con el patrón de enmascaramiento estático de la Clase 2:

| Columna | En `usuario_anon` | Criterio |
|---|---|---|
| `id` | igual que en `usuario` | Se conserva: identifica la fila sin identificar a la persona. |
| `nombre`, `apellido` | `'Usuario ' \|\| id`, `'Apellido ' \|\| id` | Deterministas y únicos, sin relación con la persona. |
| `mail` | `'usuario' \|\| id \|\| '@ejemplo.test'` | Único, preserva la selectividad del índice. Mismo criterio que la anonimización del log de la Parte C. |
| `celular` | `NULL` | Descartado. |
| `contrasena` | `'hash_no_valido'` | No es un hash bcrypt: ninguna clave lo valida. |
| `rol`, `activo`, `created_at` | iguales | Son lo que el análisis agregado necesita. |

La única diferencia con la clase es la baja lógica por `activo` en lugar de `eliminado` (regla R7 del proyecto). `sql/test_usuario_anon.sql` verifica que no sobreviva ningún mail, nombre, apellido, celular ni hash real; que la copia sea determinista y tenga la misma cardinalidad; y que no quede legible para los roles de la aplicación. Se probó con mutaciones: un mail real infiltrado y un `GRANT SELECT` a `rol_reportes` hacen fallar el test.

## 2. Las dos consultas (D.2)

Especificación de la agregación: cantidad de cuentas por rol y por mes de alta. Una fila por grupo con al menos una cuenta, con `total_cuentas` (activas y dadas de baja) y `cuentas_activas`, ordenada por mes y rol.

El mes de alta se calcula en `America/Argentina/Buenos_Aires`. `created_at` es `TIMESTAMPTZ`, así que un `date_trunc('month', created_at)` sin zona depende de la zona horaria de la sesión: una cuenta creada el 31 a las 22:00 en Argentina ya es día 1 en UTC y cambiaría de mes según quién ejecute la consulta.

> **Sobre el uso de IA en este punto.** La consigna pide especificarle esta consulta a OpenCode. Se le envió la especificación (`gemini-3.5-flash`, sesión `ses_e7c20665…`, en una carpeta aislada y sin acceso a la base). A los 10 minutos no había respuesta y el equipo decidió cancelar y escribir las dos consultas con Claude Code a partir de la misma especificación. Después se comprobó en el registro de la sesión que la causa no era la demora: el proveedor había rechazado el pedido con *"You exceeded your current quota"* (cuota agotada de la API de Google). Ver `BITACORA.md`, D-1.

Sobre `usuario_anon`:

```sql
SELECT date_trunc('month', created_at AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS mes_alta,
       rol,
       count(*)                       AS total_cuentas,
       count(*) FILTER (WHERE activo) AS cuentas_activas
FROM usuario_anon
GROUP BY 1, 2
ORDER BY 1, 2;
```

Equivalente sobre la tabla real `usuario` (solo cambia la tabla de origen):

```sql
SELECT date_trunc('month', created_at AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS mes_alta,
       rol,
       count(*)                       AS total_cuentas,
       count(*) FILTER (WHERE activo) AS cuentas_activas
FROM usuario
GROUP BY 1, 2
ORDER BY 1, 2;
```

## 3. Resultados y demostración de equivalencia (D.3)

`sql/equivalencia_usuario_anon.sql` ejecuta las dos consultas, las pone lado a lado y **demuestra** la equivalencia en lugar de afirmarla: calcula la diferencia simétrica (`anon EXCEPT real` y `real EXCEPT anon`) y falla con `ASSERT` si no es vacía. Repite el cálculo con tres zonas horarias de sesión distintas para probar que el resultado no depende de quién lo ejecuta.

Salida completa, sin editar (base `foodstore_tp5`, PostgreSQL 17):

```text
=== 1. usuario_anon ===
  mes_alta  |   rol   | total_cuentas | cuentas_activas 
------------+---------+---------------+-----------------
 2026-01-01 | ADMIN   |             1 |               1
 2026-01-01 | USUARIO |             3 |               3
 2026-02-01 | USUARIO |             4 |               3
 2026-03-01 | USUARIO |             5 |               4
 2026-04-01 | USUARIO |             4 |               3
 2026-05-01 | USUARIO |             4 |               3
 2026-06-01 | USUARIO |             5 |               4
 2026-07-01 | USUARIO |             4 |               3
(8 filas)

=== 2. usuario ===
  mes_alta  |   rol   | total_cuentas | cuentas_activas 
------------+---------+---------------+-----------------
 2026-01-01 | ADMIN   |             1 |               1
 2026-01-01 | USUARIO |             3 |               3
 2026-02-01 | USUARIO |             4 |               3
 2026-03-01 | USUARIO |             5 |               4
 2026-04-01 | USUARIO |             4 |               3
 2026-05-01 | USUARIO |             4 |               3
 2026-06-01 | USUARIO |             5 |               4
 2026-07-01 | USUARIO |             4 |               3
(8 filas)

=== 3. Lado a lado ===
  mes_alta  |   rol   | anon_total | real_total | anon_activas | real_activas | comparacion 
------------+---------+------------+------------+--------------+--------------+-------------
 2026-01-01 | ADMIN   |          1 |          1 |            1 |            1 | igual
 2026-01-01 | USUARIO |          3 |          3 |            3 |            3 | igual
 2026-02-01 | USUARIO |          4 |          4 |            3 |            3 | igual
 2026-03-01 | USUARIO |          5 |          5 |            4 |            4 | igual
 2026-04-01 | USUARIO |          4 |          4 |            3 |            3 | igual
 2026-05-01 | USUARIO |          4 |          4 |            3 |            3 | igual
 2026-06-01 | USUARIO |          5 |          5 |            4 |            4 | igual
 2026-07-01 | USUARIO |          4 |          4 |            3 |            3 | igual
(8 filas)

CREATE TABLE
DO
=== 4. Diferencia simétrica por zona horaria de la sesión ===
              zona              | grupos | solo_anon | solo_real 
--------------------------------+--------+-----------+-----------
 America/Argentina/Buenos_Aires |      8 |         0 |         0
 UTC                            |      8 |         0 |         0
 Asia/Tokyo                     |      8 |         0 |         0
(3 filas)

equivalencia_usuario_anon: OK
```

Resultado: **8 grupos idénticos**, con los mismos totales y activas, **0 filas** en cada lado de la diferencia simétrica y la misma respuesta con la sesión en Buenos Aires, UTC y Tokio.

**La verificación detecta diferencias.** Se alteró a propósito una fila (`UPDATE usuario_anon SET rol = 'ADMIN' WHERE id = 2`): el lado a lado mostró dos grupos `DISTINTO` (ADMIN de enero 2 contra 1, USUARIO de enero 2 contra 3) y el script terminó con `ERROR: ... 2 grupos solo en usuario_anon, 2 solo en usuario`. Al reconstruir `usuario_anon`, volvió a pasar.

## 4. Qué no debe salir nunca hacia una IA sin anonimizar (D.4)

Nunca debe salir hacia un asistente de IA, sin pasar antes por este proceso, ningún dato que identifique a una persona: nombre, apellido, mail, celular o teléfono de `usuario` y `cliente`, sus hashes de contraseña y los pedidos vinculados a un cliente identificable (qué compró, cuándo y cómo pagó). Tampoco deben salir los logs del servidor, que repiten esos datos en los `INSERT` y en los intentos de inicio de sesión, ni los volcados o copias de la base, ni las credenciales y cadenas de conexión de `app_web` y `admin_datos`. Incluso `usuario_anon` conserva `id` y `created_at` exactos: no debe compartirse junto con datos reales que permitan volver a vincular cada fila con su persona.
