# Diseño de Arquitectura - Tablet Offline y Cierre de Capa de Datos (TP8)

## 1. Visión General de la Arquitectura
El sistema implementa una arquitectura **Offline-First** para terminales móviles (tablets de preventistas y vendedores de campo).

La arquitectura se compone de dos capas de persistencia conectadas de manera asíncrona:
1. **Base Central (PostgreSQL)**: Fuente de la verdad transaccional (Single Source of Truth). Gestiona el catálogo de productos, niveles de stock en tiempo real, histórico de pedidos y políticas comerciales.
2. **Base Local de Tablet (SQLite)**: Base de datos embebida ligera que almacena un subconjunto de trabajo (cache local de clientes y productos) y permite la captura autónoma de pedidos borrador sin conexión a red.

```
+--------------------------------------------------------+
|               Servidor Central (PostgreSQL)           |
|  - Catalogo maestro de productos                       |
|  - Control de stock y reservas                         |
|  - Resolucion definitiva transaccional (ACID)          |
+---------------------------+----------------------------+
                            |
           [Exportacion Snapshot via CSV / ETL]
                            |
                            v
+--------------------------------------------------------+
|                Tablet Movil (SQLite 3)                 |
|  - Tablas STRICT (clientes, productos, pedidos, etc.)  |
|  - Snapshot tipado (snapshot_servidor)                 |
|  - Evaluacion local Offline (Semaforo SQL determinista)|
|  - Captura autonoma de borradores                      |
+--------------------------------------------------------+
```

---

## 2. Componentes de la Base Local (SQLite)

### 2.1 Esquema Tipado STRICT
Para prevenir los problemas de coerción de tipos dinámicos típicos de SQLite (donde campos textuales pueden provocar comparaciones léxicas erróneas como `'5' > '48'`), todas las tablas locales se definen con el modificador `STRICT`:
- `clientes`: Datos de contacto, saldo actual y límite de crédito.
- `productos`: Catálogo local offline con precio unitario, stock local y flag de sincronización (`sincronizado_servidor`).
- `pedidos`: Cabeceras de pedidos generados en la tablet, con fecha, estado local (`BORRADOR`, `PENDIENTE_SYNC`, `APROBADO`, `RECHAZADO`, `CONFLICTO`) y tracking de sincronización.
- `items_pedido`: Detalle de productos, cantidades y precios capturados en el momento de la preventa.
- `snapshot_servidor`: Tabla temporal o persistente de importación con tipado estricto que recibe el volcado CSV del servidor central.

### 2.2 Política de Claves Foráneas
SQLite no habilita claves foráneas por defecto; la arquitectura requiere la ejecución obligatoria de `PRAGMA foreign_keys = ON;` en cada sesión de conexión del cliente móvil para garantizar integridad referencial estricta.

---

## 3. Modelo de Sincronización y Resolución de Conflictos

### 3.1 Flujo de Exportación / Importación (Snapshot)
1. **En PostgreSQL**: La vista `v_snapshot_movil` proyecta las columnas clave de productos y clientes aptos para movilidad. Un script exporta los datos a formato CSV estándar con cabecera.
2. **En SQLite**: Se utiliza la tabla intermedia tipada `snapshot_servidor`. El script `importar_snapshot.sql` realiza un **UPSERT** idempotente:
   - Nuevos registros son insertados.
   - Registros modificados son actualizados.
   - Los registros locales existentes que no hayan sido sincronizados con el servidor conservan sus flags y modificaciones (respeto a tumbstones y estados locales).

### 3.2 Lógica del Semáforo Offline (Consigna 2.b)
El semáforo se implementa exclusivamente en SQL declarativo dentro de SQLite (`movil/semaforo.sql`):
- Evalúa los pedidos en estado `BORRADOR`.
- Compara la cantidad pedida contra el stock disponible en la instantánea.
- Compara el precio acordado en el borrador contra el precio vigente en el snapshot.
- Regla de negocio determinista (`CASE`):
  1. Si `n_items = 0` o existen ítems sin stock suficiente (`n_rojo > 0`) -> **`RECHAZADO`**.
  2. Si hay stock pero existen variaciones de precio en perjuicio del cliente (`n_amarillo > 0`) -> **`CONFLICTO`**.
  3. Si todos los ítems tienen stock y el precio no aumentó -> **`SIMULADO_APROBADO`**.

---

## 4. Nota de Desviación de Herramientas (Kiro / OpenCode -> Claude Code + OpenSpec)
De acuerdo a lo documentado en la Bitácora de IA y en la DUIA:
- La cátedra sugirió originalmente el uso de Kiro y OpenCode.
- El equipo técnico adoptó **Claude Code** asistido por la metodología de especificación formal **OpenSpec (OPSX)**.
- Esta decisión permitió un control de versiones más granular, integración fluida con la terminal Git Bash en Windows y una trazabilidad estricta de cada requisito EARS y caso de prueba C1-C7 mediante suites automáticas en bash.
