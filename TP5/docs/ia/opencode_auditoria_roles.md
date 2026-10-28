# Auditoría de `roles.sql` con OpenCode (consigna A.4)

| Dato | Valor |
|---|---|
| Herramienta | OpenCode CLI 1.18.18, agente `plan` (solo lectura) |
| Modelo | `google/gemini-3.5-flash` |
| Sesión | `ses_e7c6ff880ffelppib4BK8ZNo2i` |
| Fecha | 2026-10-28, 14:30 a 14:48 |
| Archivo auditado | `TP5/sql/roles.sql` del commit `e6d5d8f` (con R2 y R10 ya corregidos) |

## Intentos

| # | Modelo / sesión | Resultado |
|---|---|---|
| 1 | `google/gemini-3.8-flash`, `ses_e7ca7949affeVMj1AU41e9SXiv` (13:29) | Leyó `roles.sql` y `usuario_autenticacion.sql` y falló: *"This model is currently experiencing high demand."* |
| 2 | La misma sesión, continuada (13:43) | Falló a los ~20 min: *"Deadline expired before operation could complete."* |
| 3 | `google/gemini-3.5-flash`, `ses_e7c6ff880ffelppib4BK8ZNo2i` (14:30) | Exploró el repositorio (`schema.sql`, `procedures.sql`, `verificacion_permisos.md`) y se cortó por el límite de 15 min que pusimos al comando. Sin respuesta. |
| 4 | La misma sesión, continuada (14:45) | Respuesta completa (abajo). |

Comando del intento 3 (desde la raíz del repositorio):

```bash
opencode run "Auditá este archivo roles.sql de PostgreSQL 16 para Food Store. Proponé mejoras o correcciones de seguridad y de mantenimiento, indicando para cada propuesta la sentencia SQL exacta. No modifiques archivos."   -m google/gemini-3.5-flash --agent plan -f TP5/sql/roles.sql
```

Prompt del intento 4 (`-s ses_e7c6ff880ffelppib4BK8ZNo2i`):

```text
Ya tenés el contexto necesario. Sin leer más archivos, entregá ahora la auditoría de roles.sql: cada propuesta de mejora o corrección con su sentencia SQL exacta. No modifiques archivos.
```

La evaluación del equipo sobre cada propuesta está en `TP5/BITACORA.md` (registro A-5).

---

## Respuesta de la IA (sin editar)

### Informe de Auditoría de Seguridad y Mantenibilidad: `TP5/sql/roles.sql`

**Motor Target:** PostgreSQL 16+  
**Estatus de Modificaciones:** Solo lectura / No se modificaron archivos en el repositorio.

---

#### Resumen Ejecutivo

El archivo `TP5/sql/roles.sql` presenta una implementación sólida del **Principio de Mínimo Privilegio**, aplicando separación de roles de conexión (`LOGIN`) y roles de grupo (`NOLOGIN`), vistas seguras, privilegios por columna y hardening de rutinas mediante `SECURITY DEFINER` y `search_path` explícito (`public, pg_temp`).

Sin embargo, tras la auditoría del código SQL se identifican **7 oportunidades de mejora y correcciones** en materia de seguridad, idempotencia y mantenibilidad. A continuación se detalla cada propuesta junto con su fundamento técnico y su **sentencia SQL exacta**.

---

#### Hallazgos y Propuestas de Mejora

##### 1. Eliminación de Privilegio `CREATE` Innecesario a `rol_owner_codigo`
* **Categoría:** Seguridad / Mínimo Privilegio
* **Diagnóstico:** En la Sección 3 (línea 131) se ejecuta `GRANT CREATE ON SCHEMA public TO rol_owner_codigo;` y luego en la Sección 15 (línea 518) se revoca. `rol_owner_codigo` es un rol técnico `NOLOGIN` diseñado únicamente para ser propietario de las rutinas `SECURITY DEFINER`. Puesto que el script lo ejecuta el DBA/superusuario, es el propio DBA quien crea o reemplaza las rutinas y transfiere la propiedad mediante `ALTER ... OWNER TO rol_owner_codigo`. Otorgar permisos de creación DDL a un rol técnico (aunque sea temporalmente durante la ejecución del script) es innecesario y contraviene el mínimo privilegio.
* **Sentencia SQL exacta:**
  ```sql
  -- En la Sección 3, eliminar la concesión del privilegio CREATE:
  -- (Reemplazar la línea 131 por la revocación explícita preventiva)
  REVOKE CREATE ON SCHEMA public FROM rol_owner_codigo;

  -- En la Sección 15, la revocación explícita se mantiene como salvaguarda:
  REVOKE CREATE ON SCHEMA public FROM rol_owner_codigo;
  ```

---

##### 2. Revocación Sanitizadora Masiva sobre el Esquema `public`
* **Categoría:** Mantenibilidad / Resiliencia
* **Diagnóstico:** En la Sección 4 (líneas 138-161), se revocan privilegios heredados enumerando manualmente cada tabla, vista y secuencia (`public.categoria`, `public.producto`, etc.). Si en el futuro se agregan nuevas tablas o secuencias al esquema `public`, esta lista explícita no revocaría los permisos por defecto de `PUBLIC` sobre los nuevos objetos si se ejecutan DDLs fuera de las políticas predeterminadas.
* **Sentencia SQL exacta:**
  ```sql
  -- Reemplazar la enumeración manual de tablas, vistas y secuencias por sanitización masiva a nivel de esquema:
  REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
  REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
  REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;
  ```

---

##### 3. Unificación de Endurecimiento Dinámico para Sobrecargas de `fn_autenticar`
* **Categoría:** Mantenibilidad / Calidad de Código
* **Diagnóstico:** Existe duplicación de código en dos bloques `DO $$` independientes: en la Sección 4 (líneas 169-184) y en la Sección 11.b (líneas 391-419). En ambos bloques se itera sobre `pg_proc` para realizar `REVOKE` y `GRANT` sobre `fn_autenticar`. Conviene unificar toda la configuración de la función en un único bloque dinámico.
* **Sentencia SQL exacta:**
  ```sql
  -- Unificar Sección 4 y Sección 11.b en un solo bloque idempotente:
  DO $$
  DECLARE
      r RECORD;
  BEGIN
      FOR r IN
          SELECT p.oid::regprocedure AS sig
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public'
            AND p.proname = 'fn_autenticar'
      LOOP
          EXECUTE format('ALTER FUNCTION %s SECURITY DEFINER', r.sig);
          EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', r.sig);
          EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.sig);
          EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO rol_app_lectura', r.sig);
          EXECUTE format('ALTER FUNCTION %s OWNER TO rol_owner_codigo', r.sig);
      END LOOP;
  END
  $$;
  ```

---

##### 4. Cobertura Completa de Sobrecargas para Funciones de Criptografía (`pgcrypto`)
* **Categoría:** Seguridad / Invocación de Funciones
* **Diagnóstico:** En la Sección 9 (líneas 293-300), se revoca `EXECUTE` sobre `gen_salt(TEXT)` y `gen_salt(TEXT, INTEGER)`, pero solo se concede `GRANT EXECUTE` a `rol_owner_codigo` para `gen_salt(TEXT)`. Si en el futuro una rutina requiere especificar el número de rondas explícito para bcrypt (ej. `gen_salt('bf', 10)`), la ejecución fallará por falta de privilegios sobre la sobrecarga `(TEXT, INTEGER)`.
* **Sentencia SQL exacta:**
  ```sql
  -- Revocar ejecución a PUBLIC sobre todas las firmas conocidas de pgcrypto usadas:
  REVOKE EXECUTE ON FUNCTION public.crypt(TEXT, TEXT) FROM PUBLIC;
  REVOKE EXECUTE ON FUNCTION public.gen_salt(TEXT) FROM PUBLIC;
  REVOKE EXECUTE ON FUNCTION public.gen_salt(TEXT, INTEGER) FROM PUBLIC;

  -- Otorgar ejecución explícita al rol técnico para ambas sobrecargas:
  GRANT EXECUTE ON FUNCTION public.crypt(TEXT, TEXT) TO rol_owner_codigo;
  GRANT EXECUTE ON FUNCTION public.gen_salt(TEXT) TO rol_owner_codigo;
  GRANT EXECUTE ON FUNCTION public.gen_salt(TEXT, INTEGER) TO rol_owner_codigo;
  ```

---

##### 5. Limpieza Preventiva de Default Privileges en la Reejecución (Idempotencia)
* **Categoría:** Idempotencia / Gestión de Clúster
* **Diagnóstico:** En la Sección 0 (líneas 41-61), el script realiza `REASSIGN OWNED BY` y `DROP OWNED BY` para garantizar la idempotencia antes de hacer `DROP ROLE`. Sin embargo, si en corridas anteriores se definieron `ALTER DEFAULT PRIVILEGES FOR ROLE ...`, `DROP OWNED BY` no siempre elimina las entradas de privilegios predeterminados cruzados, lo que podría ocasionar un error de dependencia al ejecutar `DROP ROLE`.
* **Sentencia SQL exacta:**
  ```sql
  -- Mejorar la Sección 0 agregando la revocación explícita de privilegios predeterminados de cada rol antes de eliminarlo:
  DO $$
  DECLARE
      r TEXT;
  BEGIN
      FOREACH r IN ARRAY ARRAY[
          'app_web',
          'admin_datos',
          'rol_app_lectura',
          'rol_app_escritura',
          'rol_soporte',
          'rol_reportes',
          'rol_owner_codigo'
      ]
      LOOP
          IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
              EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC', r);
              EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC', r);
              EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I REVOKE ALL ON FUNCTIONS FROM PUBLIC', r);
              EXECUTE format('REASSIGN OWNED BY %I TO CURRENT_USER', r);
              EXECUTE format('DROP OWNED BY %I', r);
          END IF;
      END LOOP;
  END
  $$;
  ```

---

##### 6. Bloqueo Temporal de Cuentas de Conexión en Creación (`VALID UNTIL`)
* **Categoría:** Seguridad en Despliegue
* **Diagnóstico:** En la Sección 2 (líneas 105-115), las cuentas `app_web` y `admin_datos` se crean con `PASSWORD NULL`. Si la aprovisionación de claves no ocurre inmediatamente por algún fallo en el pipeline de CI/CD o despliegue, la cuenta queda en un estado ambiguo. Se recomienda explicitar la invalidez de la contraseña hasta su provisión.
* **Sentencia SQL exacta:**
  ```sql
  -- Forzar la caducidad de la credencial nula hasta que el administrador o gestor de secretos asigne la contraseña real:
  CREATE ROLE app_web
      LOGIN PASSWORD NULL VALID UNTIL '1970-01-01'
      NOSUPERUSER NOCREATEDB NOCREATEROLE
      NOREPLICATION NOBYPASSRLS
      CONNECTION LIMIT 20;

  CREATE ROLE admin_datos
      LOGIN PASSWORD NULL VALID UNTIL '1970-01-01'
      NOSUPERUSER NOCREATEDB NOCREATEROLE
      NOREPLICATION NOBYPASSRLS
      CONNECTION LIMIT 5;
  ```

---

##### 7. Cualificación Explícita de Funciones y Castings en `fn_resetear_password`
* **Categoría:** Seguridad y Robustez de Código PL/pgSQL
* **Diagnóstico:** En la Sección 11 (líneas 363-367), las llamadas a `crypt()` y `gen_salt()` dentro del cuerpo de `fn_resetear_password` no incluyen el esquema explícito `public.crypt()` ni `public.gen_salt()`. Aunque `search_path` está fijado en la función (`SET search_path = public, pg_temp`), cualificar explícitamente los llamados a funciones de extensiones refuerza la protección contra ataques de suplantación.
* **Sentencia SQL exacta:**
  ```sql
  CREATE OR REPLACE FUNCTION public.fn_resetear_password(
      p_usuario_id BIGINT,
      p_nueva TEXT
  )
  RETURNS VOID
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  AS $$
  DECLARE
      v_filas INTEGER;
  BEGIN
      IF p_usuario_id IS NULL THEN
          RAISE EXCEPTION 'El id de usuario no puede ser nulo.';
      END IF;

      IF p_nueva IS NULL OR btrim(p_nueva) = '' THEN
          RAISE EXCEPTION 'La nueva contraseña no puede ser nula ni vacía.';
      END IF;

      -- Actualización con cualificación explícita del esquema para funciones de pgcrypto
      UPDATE public.usuario
         SET contrasena = public.crypt(p_nueva, public.gen_salt('bf'))
       WHERE id = p_usuario_id
         AND activo = TRUE
         AND rol <> 'ADMIN'::rol_usuario_enum;

      GET DIAGNOSTICS v_filas = ROW_COUNT;

      IF v_filas = 0 THEN
          RAISE EXCEPTION
              'No existe un usuario activo con id % o la cuenta es ADMIN y no puede resetearse por esta vía.',
              p_usuario_id;
      END IF;
  END;
  $$;
  ```
