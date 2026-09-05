# Protocolo de Seguridad — Food Store (TP2)

Este documento establece el procedimiento estándar y obligatorio para cualquier modificación de esquema o datos sobre las bases de datos del proyecto **Food Store**, garantizando la integridad de los entornos y previniendo pérdida de datos o incidentes operativos.

---

## 1. Copia de Trabajo (Aislamiento de Entorno)
Nunca se trabaja directamente sobre la base de datos principal de producción o datos críticos. Toda experimentación, script generado por IA o prueba estructural se ejecuta sobre una copia de trabajo dedicada (`foodstore_copia`).

- **Comando de creación de copia en PostgreSQL:**
  ```bash
  createdb -U postgres -T foodstore foodstore_copia
  ```
- **Regla:** Si se requiere reiniciar el entorno de pruebas, se elimina la copia y se regenera desde la plantilla base:
  ```bash
  dropdb -U postgres foodstore_copia
  createdb -U postgres -T foodstore foodstore_copia
  ```

---

## 2. Transacción de Prueba (`BEGIN ... ROLLBACK`)
Todo script que modifique datos (DML: `INSERT`, `UPDATE`, `DELETE`) o ejecute operaciones lógicas debe ejecutarse inicialmente dentro de una transacción de prueba.

- **Estructura obligatoria de ejecución:**
  ```sql
  BEGIN;

  -- Ejecución del script propuesto / generado por IA
  -- (Sentencias SQL aquí)

  -- Inspección de resultados (SELECT, conteo de filas afectadas, mensajes)
  SELECT * FROM ...;

  -- Si el resultado es el esperado: COMMIT;
  -- Si hay anomalías o efectos no deseados: ROLLBACK;
  ROLLBACK;
  ```
- **Regla:** Ningún cambio de datos se confirma (`COMMIT`) sin haber inspeccionado previamente el estado intermedio mediante `ROLLBACK` o validación explícita de filas afectadas.

---

## 3. Respaldo Estructural (`pg_dump`)
Antes de aplicar cualquier cambio estructural (DDL: `ALTER TABLE`, `DROP TABLE`, migraciones complejas), se debe generar un respaldo físico independiente de la copia de trabajo para permitir una recuperación rápida ante fallos graves.

- **Comando de respaldo en PostgreSQL:**
  ```bash
  pg_dump -U postgres -d foodstore_copia -F c -b -v -f "backup_foodstore_$(date +%Y%m%d_%H%M%S).backup"
  ```
- **Regla:** Ante cualquier error estructural irreversible, se restaura desde el respaldo generado:
  ```bash
  pg_restore -U postgres -d foodstore_copia -v "backup_foodstore_YYYYMMDD_HHMMSS.backup"
  ```

---
*Aprobado y aplicado para el desarrollo del TP2 - Base de Datos II.*
