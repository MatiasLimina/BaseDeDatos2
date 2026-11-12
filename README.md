# Base de Datos II · Trabajo Práctico Integrador «Food Store»

**Integrantes:** Matias Limina, Nicolas Monjelardi y Lautaro Aguero.
UTN · Tecnicatura Universitaria en Programación · Base de Datos II.

Este repositorio contiene toda la capa de datos de Food Store, construida a lo largo de la cursada: el modelo relacional en PostgreSQL, su administración y mantenimiento, un modelo documental en MongoDB y la base local de una tablet en SQLite. Cada unidad tiene su carpeta (`TP1/` a `TP8/`), y `Proyecto_Integrador/` reúne el informe técnico de las dos entregas.

## Por dónde empezar

| Qué | Dónde |
|---|---|
| **Informe técnico consolidado** (primera y segunda entrega) | [`Proyecto_Integrador/documentos/TPI_FoodStore_Informe_Tecnico_Consolidado.md`](Proyecto_Integrador/documentos/TPI_FoodStore_Informe_Tecnico_Consolidado.md) |
| **Matriz de trazabilidad**: cada punto de la consigna, con su estado y su evidencia | §1.1 (Unidades 1 a 3) y §1.2 (Unidades 4 a 8) del informe, con las salvedades debajo de la tabla |
| **Declaración de Uso de IA (DUIA)** de la segunda entrega | [`Proyecto_Integrador/documentos/DUIA_U4_U8.md`](Proyecto_Integrador/documentos/DUIA_U4_U8.md) (la de la primera entrega está en la §6 del informe) |
| Herramientas que reemplazan a las de la consigna, con acuerdo de la cátedra | §6.1 del informe: el ciclo OPSX/OpenSpec en lugar de Kiro y Claude Code en lugar de OpenCode |

El informe no copia los trabajos de cada unidad: enlaza a sus carpetas con rutas relativas, así que cada afirmación se puede seguir hasta el script, el test o la evidencia que la respalda.

## Qué se entrega

### Primera entrega (Unidades 1 a 3)

| Unidad | Tema | Carpeta | Entregable principal |
|---|---|---|---|
| U1 | Modelo ER, normalización y DDL | [`TP1/`](TP1/) | [`TP1_FoodStore_ModeloER_Normalizacion_DDL.pdf`](TP1/TP1_FoodStore_ModeloER_Normalizacion_DDL.pdf), [`schema.sql`](TP1/schema.sql) |
| U2 | Restricciones, transacciones y concurrencia | [`TP2/`](TP2/) | [`TP2_Consolidado.md`](TP2/TP2_Consolidado.md), [`informe_concurrencia.md`](TP2/informe_concurrencia.md) |
| U3 | Índices, vistas y vistas materializadas | [`TP3/`](TP3/) | [`informe_mediciones.md`](TP3/informe_mediciones.md), [`README.md`](TP3/README.md) |
| Integrador | Esquema, datos, procedimientos, triggers y consultas | [`Proyecto_Integrador/database/`](Proyecto_Integrador/database/) | [`schema.sql`](Proyecto_Integrador/database/schema.sql), [`seed.sql`](Proyecto_Integrador/database/seed.sql), [`procedures.sql`](Proyecto_Integrador/database/procedures.sql), [`triggers.sql`](Proyecto_Integrador/database/triggers.sql) |

### Segunda entrega (Unidades 4 a 8)

| Unidad | Tema | Carpeta | Entregable principal |
|---|---|---|---|
| U4 | FNBC y desnormalización controlada | [`TP4/`](TP4/) y el change de OpenSpec [`2026-10-18-tp4-fnbc-desnormalizacion`](openspec/changes/archive/2026-10-18-tp4-fnbc-desnormalizacion/) | [`informe_tp4.md`](TP4/informe_tp4.md) ([PDF](TP4/informe_tp4.pdf)), [`tests/`](TP4/tests/), [`pruebas_manuales.md`](TP4/pruebas_manuales.md) |
| U5 | Usuarios, roles, auditoría, simulacro de incidente y anonimización | [`TP5/`](TP5/) | [`README.md`](TP5/README.md), [`sql/`](TP5/sql/), [`docs/`](TP5/docs/), [`BITACORA.md`](TP5/BITACORA.md) |
| U6 | Mantenimiento, respaldo y recuperación | [`TP6/`](TP6/) | [`SPEC_U6.md`](TP6/SPEC_U6.md), [`informe_u6.pdf`](TP6/informe_u6.pdf), scripts del plan y [`evidencias/`](TP6/evidencias/) |
| U7 | Modelo documental en MongoDB frente a PostgreSQL | [`TP7/`](TP7/) | [`informe_tp7.pdf`](TP7/informe_tp7.pdf), [`docs/modelo_documental.md`](TP7/docs/modelo_documental.md), [`consultas_mongodb.js`](TP7/consultas_mongodb.js) |
| U8 | Base SQLite de la tablet, sincronización simulada y cierre de la capa de datos | [`TP8/`](TP8/) | [`docs/informe.pdf`](TP8/docs/informe.pdf), [`movil/`](TP8/movil/), [`docs/code_review_ia.md`](TP8/docs/code_review_ia.md), [`docs/plan_mantenimiento_tp8.md`](TP8/docs/plan_mantenimiento_tp8.md) |

Cada carpeta de la segunda entrega tiene su propio `README.md` (o su informe) con el detalle y con cómo ejecutar sus scripts.

## Estructura del repositorio

```text
.
├── Proyecto_Integrador/
│   ├── documentos/   informe consolidado, DUIA U4–U8, protocolo de seguridad, informe del TP4 integrado
│   ├── database/     esquema, datos, procedimientos, triggers, vistas y scripts del TP4 integrados
│   └── specs/        specs de la primera entrega
├── TP1/ … TP8/       trabajo de cada unidad: consigna, scripts, tests, evidencias e informe
├── openspec/         specs vigentes y changes archivados del ciclo OPSX (TP4)
└── AGENTS.md         reglas de negocio y directivas de DDL que siguen los agentes de IA
```

## Entorno

- **PostgreSQL**: versión mínima de referencia 16. Se usó la 18.6 en el TP4 y la 17.11 del TP5 al TP7.
- **MongoDB** (TP7) y **SQLite** (TP8).
- Los scripts PowerShell del TP6 se programan con el Programador de tareas de Windows. Cómo registrarlos está en [`TP6/README.md`](TP6/README.md).

Los datos son sintéticos. Las bases de trabajo y sus volúmenes se detallan en la §7 del informe consolidado.

## Uso de inteligencia artificial

Todo uso de IA está declarado: herramienta, finalidad, prompts o specs, qué se aceptó o se corrigió y cómo se verificó. En la primera entrega está en la §6 del informe y en las DUIA de [`TP2/`](TP2/) y [`TP3/`](TP3/duia.md); en la segunda, en [`DUIA_U4_U8.md`](Proyecto_Integrador/documentos/DUIA_U4_U8.md), que enlaza a las bitácoras de cada unidad. Donde no quedó registro de los prompts, la DUIA lo dice de forma explícita.
