# TP8 - La Base de la Tablet (SQLite) y el Cierre de la Capa de Datos

**Asignatura**: Bases de Datos II  
**Repositorio**: `BasesNoRelacionales/TP8`  
**Rama de trabajo**: `tp8`  

---

## 1. Descripción del Proyecto
Este trabajo práctico concluye la arquitectura de datos del sistema comercial implementando la capa móvil para terminales de preventistas y vendedores de campo (tablets) bajo una filosofía **Offline-First**.

### Objetivos Principales:
1. **Esquema SQLite tipado (`STRICT`)**: Prevenir la coerción de tipos dinámicos y garantizar la coherencia relacional en clientes móviles.
2. **Sincronización asimétrica de instantáneas (Snapshot)**: Exportar un subconjunto de trabajo desde PostgreSQL (`v_snapshot_movil`) e importarlo en SQLite con lógica de `UPSERT` e idempotencia.
3. **Semáforo offline determinista**: Evaluación de viabilidad de pedidos borrador en SQL declarativo (`SIMULADO_APROBADO`, `CONFLICTO`, `RECHAZADO`).
4. **Matriz de Casos de Sincronización (C1 a C7)**: Simulación y resolución de conflictos de concurrencia, stock insuficiente y cambios de precios entre la tablet y el servidor central.
5. **Mantenimiento y Respaldo**: Estrategia de backup en caliente con `VACUUM INTO` y plan de contingencia ante fallos.
6. **Code Review asistido por IA y Especificación EARS**: Auditoría estática de 107 scripts de la cursada y formalización de requisitos EARS en `docs/kiro/`.

---

## 2. Requisitos Previos y Entorno

- **Sistema Operativo**: Windows 10/11 con Git Bash (`bash.exe`).
- **PostgreSQL**: Versión 14 o superior (con `psql` disponible en `PATH` o `D:\DevTools\PosgresSQL\bin`).
- **SQLite**: Versión 3.37.0 o superior (con soporte para tablas `STRICT`).
- **Python**: Versión 3.9 o superior con la librería `pypdf` instalada (`pip install pypdf`).
- **Navegador Headless**: Google Chrome o Microsoft Edge para compilar el informe HTML a PDF.

---

## 3. Estructura del Repositorio

```text
TP8/
├── docs/
│   ├── DUIA.md                      # Declaración de Uso de Inteligencia Artificial
│   ├── bitacora_ia.md               # Bitácora de pedidos, aceptaciones y descartes a la IA
│   ├── code_review_ia.md            # Informe de revisión técnica de los 107 scripts de la cursada
│   ├── plan_mantenimiento_tp8.md    # Políticas de mantenimiento y respaldo para SQLite
│   ├── informe.pdf                  # Informe consolidado (máx. 6 páginas)
│   └── kiro/                        # Especificación exportada
│       ├── requirements.md          # Requisitos EARS (REQ-01 a REQ-07 vinculados a C1-C7)
│       ├── design.md                # Arquitectura técnica y nota de desviación
│       └── tasks.md                 # Desglose estructurado de tareas
├── evidencias/                      # Logs de pruebas, casos C1-C7 y respaldos SQLite
├── informe/
│   ├── informe.html                 # Informe técnico fuente para entrega
│   └── generar_pdf.sh               # Compilador Headless de informe.html a PDF con validación pypdf
├── movil/
│   ├── schema_sqlite.sql            # Definición DDL con 4 tablas STRICT + snapshot_servidor
│   ├── importar_snapshot.sql        # Lógica de UPSERT idempotente para el catálogo móvil
│   ├── semaforo.sql                 # Evaluación declarativa de estados offline (CASE)
│   ├── pruebas_sqlite.sql           # Pruebas de integridad referencial y de dominio
│   └── casos/                       # Borradores de pedidos para simulación offline (C2 a C6)
├── scripts/
│   └── correr_casos.sh              # Orquestador general end-to-end de casos C1 a C7
├── sql/
│   ├── linea_base.sql               # Restauración del estado inicial en PostgreSQL
│   ├── 01_v_snapshot_movil.sql      # Vista exportadora central en PostgreSQL
│   ├── 02_exportar_snapshot.sql     # Volcado a CSV mediante comando \copy
│   ├── verificacion_final.sql       # Consultas de consistencia post-sincronización
│   └── casos/                       # Scripts PG de preparación y restauración para C2 y C4
└── tests/                           # Suites de pruebas automáticas (Strict TDD)
    ├── test_esquema_sqlite.sh       # Validación de tablas STRICT y tipos
    ├── test_importacion.sh          # Validación de UPSERT e idempotencia
    ├── test_carga_cache.sh          # Integración exportación PG -> importación SQLite
    ├── test_pruebas_sqlite.sh       # Validación de violaciones de integridad en SQLite
    ├── test_semaforo.sh             # Validación de 9 combinaciones sintéticas del semáforo
    ├── test_casos.sh                # Verificación de ejecución completa de C1-C7
    └── test_docs.sh                 # Validación de EARS, bitácora, DUIA y PDF
```

---

## 4. Guía de Ejecución Paso a Paso (Flujo Reproducible)

### Paso 1: Configuración de Conexión a PostgreSQL
Asegúrese de contar con acceso al servidor PostgreSQL configurando las credenciales (por ejemplo, en `%APPDATA%\postgresql\pgpass.conf` o variables de entorno):
```bash
export PGHOST=localhost
export PGPORT=5432
export PGDATABASE=comercial
export PGUSER=postgres
# export PGPASSWORD=secret
```

### Paso 2: Cargar Línea Base en PostgreSQL
Restaura el estado original de tablas, clientes, productos y pedidos:
```bash
psql -h $PGHOST -U $PGUSER -d $PGDATABASE -f sql/linea_base.sql
```

### Paso 3: Crear Vista Snapshot y Exportar Catálogo Móvil
Crea la vista con los campos requeridos por la tablet y exporta el archivo `movil/snapshot_servidor.csv`:
```bash
psql -h $PGHOST -U $PGUSER -d $PGDATABASE -f sql/01_v_snapshot_movil.sql
psql -h $PGHOST -U $PGUSER -d $PGDATABASE -f sql/02_exportar_snapshot.sql
```

### Paso 4: Inicializar la Base de Datos Móvil SQLite
Crea la base local de la tablet con tablas `STRICT` y claves foráneas activadas:
```bash
rm -f movil/tablet.db
sqlite3 movil/tablet.db < movil/schema_sqlite.sql
```

### Paso 5: Importar Snapshot en SQLite
Carga el catálogo de productos y clientes en la tablet:
```bash
sqlite3 movil/tablet.db < movil/importar_snapshot.sql
```

### Paso 6: Ejecutar Pruebas Unitarias Locales (SQLite)
Valida tipos estrictos, integridad de dominio e importación:
```bash
bash tests/test_esquema_sqlite.sh
bash tests/test_importacion.sh
bash tests/test_pruebas_sqlite.sh
bash tests/test_semaforo.sh
```

### Paso 7: Ejecutar Orquestador de Casos C1 a C7
Ejecuta la matriz de pruebas de concurrencia y discrepancias entre la tablet y el servidor central:
```bash
bash scripts/correr_casos.sh
bash tests/test_casos.sh
```

### Paso 8: Verificación Final en Servidor Central
Comprueba que los estados finales en PostgreSQL coincidan exactamente con la matriz de resultados esperados:
```bash
psql -h $PGHOST -U $PGUSER -d $PGDATABASE -f sql/verificacion_final.sql
```

### Paso 9: Compilar Informe en PDF
Genera el informe técnico final a partir de `informe/informe.html` y valida que no supere 6 páginas:
```bash
bash informe/generar_pdf.sh
bash tests/test_docs.sh
```

---

## 5. Declaración de Herramientas e IA

El desarrollo de este trabajo práctico se apoyó en **Claude Code** y especificación formal **OpenSpec (OPSX)**. Todas las sugerencias de la IA fueron auditadas bajo supervisión humana crítica (modelo CASE), habiéndose descartado falsos positivos como la supuesta reserva fantasma en SQLite (CORR-01) y la errata de ruta del motor local (CORR-03).
Para más detalles, consulte [docs/DUIA.md](file:///D:/A_Universidad/Tercer%20semestre/Base%20de%20Datos%202/BasesNoRelacionales/TP8/docs/DUIA.md) y [docs/bitacora_ia.md](file:///D:/A_Universidad/Tercer%20semestre/Base%20de%20Datos%202/BasesNoRelacionales/TP8/docs/bitacora_ia.md).
