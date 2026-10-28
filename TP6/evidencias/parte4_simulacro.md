# Parte 4 — Simulacro de desastre contra reloj

El simulacro se hizo el 28/10/2026 a las 18:57:38, con `restore_test.ps1` sobre PostgreSQL 17.11 (`localhost:5432`).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\restore_test.ps1
```

## Procedimiento

1. **Respaldo usado:** el último que se generó, `backups/foodstore_20261028_181449.dump` (3,7 MB, creado a las 18:14:49 por `backup_foodstore.ps1`). Junto con él se usó `foodstore_20261028_181449.counts.csv`, con los conteos que el script tomó justo antes de `pg_dump`.
2. **Preparación (fuera del cronómetro):** se borró la `foodstore_restore_test` que había quedado de las pruebas.
3. **Inicio del cronómetro**, inmediatamente antes de `createdb foodstore_restore_test`.
4. **Restauración:** `pg_restore --no-owner --no-privileges --exit-on-error`.
5. **Validaciones mínimas** de la consigna, sobre `foodstore_restore_test`. La tabla de detalle se llama `pedido_detalle`.
6. **Fin del cronómetro**, cuando las validaciones terminaron bien.
7. **Fuera del cronómetro:** `ANALYZE`. `pg_restore` no restaura las estadísticas del planificador (ver la Parte 3).

`foodstore` no se tocó: tenía el mismo OID (24580) y los mismos conteos antes y después del simulacro ([`parte4_foodstore_intacta.txt`](parte4_foodstore_intacta.txt)). Si se hubiera borrado y recreado, el OID habría cambiado.

## Resultados

Detalle en [`parte4_simulacro_detalle.txt`](parte4_simulacro_detalle.txt). Línea del log: [`parte4_restore_test.log`](parte4_restore_test.log).

| Validación | Antes del respaldo | Restaurado | Resultado |
|---|---|---|---|
| categoria | 3 | 3 | ✅ |
| cliente | 20 003 | 20 003 | ✅ |
| producto | 50 005 | 50 005 | ✅ |
| pedido | 200 001 | 200 001 | ✅ |
| pedido_detalle | 621 853 | 621 853 | ✅ |
| Productos inválidos (`precio < 0 OR stock < 0`) | 0 | 0 | ✅ |
| Detalles inválidos (`cantidad <= 0 OR precio_unitario < 0`) | 0 | 0 | ✅ |

**Tiempos:** RTO de 13,0 s en total. `createdb` tardó 1,1 s, `pg_restore` 11,5 s y las validaciones 0,4 s. El `ANALYZE` posterior tardó 3,1 s más.

Además de las validaciones mínimas, se compararon los objetos de las dos bases ([`parte4_objetos_restaurados.txt`](parte4_objetos_restaurados.txt)) y coinciden todos:

| Objeto | Cantidad en ambas bases |
|---|---|
| Tablas | 5 |
| Vistas | 3 |
| Vistas materializadas | 1 |
| Funciones y procedimientos | 5 |
| Triggers | 2 |
| Índices | 12 |
| Restricciones | 16 |
| Tipos enum | 1 |

`health_check.sql` también corrió sin errores sobre la base restaurada ([`parte4_health_check_restore_test.txt`](parte4_health_check_restore_test.txt)).

## RPO y RTO

| | Previsto (`SPEC_U6.md`) | Observado |
|---|---|---|
| **RPO**: datos que se pueden perder, medidos como la antigüedad del último respaldo | 24 h (respaldo diario) | **42 min 49 s** |
| **RTO**: tiempo hasta tener la base restaurada y validada | 10 min | **13,0 s** |

- **RPO.** Si `foodstore` se hubiera perdido al comenzar el simulacro, se habría perdido todo lo escrito en los 42 min 49 s posteriores al respaldo de las 18:14:49. En este caso no se habrían perdido filas: los cinco conteos de `foodstore` antes del simulacro coinciden con los del respaldo. Entre medio hubo trabajo sobre la base (la Parte 3: chequeos, el `ANALYZE` de `maintenance.sql` y copias con `createdb -T`), pero nada que cambiara filas en esas tablas. Sí se habrían perdido las estadísticas del `ANALYZE`, aunque se regeneran. Ese número es la ventana de exposición.

El RPO se calcula con la hora del nombre del archivo, que es la del inicio del script de respaldo, unos segundos antes de que `pg_dump` tome su instantánea. Por eso queda apenas sobreestimado, que es el lado seguro. Las dos horas son locales. Si hubiera un cambio de horario de verano entre el respaldo y el simulacro, el RPO se correría una hora (hoy no aplica en Argentina). Con un respaldo diario a las 02:00, el peor caso es un desastre a las 01:59, con casi 24 h perdidas. El RPO observado es bajo porque el respaldo era reciente, no porque el plan lo garantice. Bajarlo de forma permanente exige respaldos más frecuentes o archivado de WAL (recuperación a un punto en el tiempo), que la SPEC deja fuera de alcance.
- **RTO.** 13,0 s está muy por debajo del objetivo de 10 min. Con 100 MB, casi todo el tiempo (88 %) se lo lleva `pg_restore`, que recrea los índices y las restricciones después de cargar los datos. El tiempo crece con el volumen. Para una base más grande, el primer ajuste sería `pg_restore -j` (en paralelo, posible con el formato custom).

## Problema real encontrado: la vista materializada

En la base restaurada, `mv_facturacion_categoria_mes` tiene **13 filas**, pero en `foodstore` tiene **1**. El respaldo no guarda el contenido de una vista materializada: guarda una entrada `MATERIALIZED VIEW DATA` que `pg_restore` ejecuta como `REFRESH`, así que la vista se recalcula con los datos restaurados. En `foodstore` se creó (`materializadas.sql`) **antes** de que `generar_registros_adaptado.sql` cargara los 200 000 pedidos, y no se volvió a refrescar desde entonces. **La vista de la base principal está desactualizada**, y la restaurada muestra la versión correcta.

Consecuencias:
- Comparar fila por fila la vista materializada entre el original y la copia daría una "diferencia" que no es un error del respaldo. Por eso no está en las validaciones.
- Los reportes que leen esa vista en `foodstore` muestran datos viejos. La mejora propuesta es agregar un `REFRESH MATERIALIZED VIEW CONCURRENTLY` periódico al plan. Para usar `CONCURRENTLY` hace falta un índice único: `idx_mv_facturacion_categoria_mes`.

## Pruebas del script

[`../tests/test_restore.sh`](../tests/test_restore.sh) trabaja con una carpeta temporal de respaldos y comprueba estos casos:
- rechaza restaurar sobre otra base: una base canario descartable, que queda intacta, y `FOODSTORE_RESTORE_TEST`, con mayúsculas;
- falla sin archivo de conteos;
- falla con un respaldo truncado, en `pg_restore`;
- falla si los conteos no coinciden y dice qué tabla difiere;
- restaura bien un respaldo sano;
- `foodstore` no cambia.

Ciclo seguido:
- **RED:** el test falló porque el script no existía.
- **Defectos que aparecieron al llevarlo a GREEN:**
  - `"$countsFile:"` no compila en PowerShell, que lo lee como una variable con unidad (`$unidad:nombre`).
  - `$detalle.Add("..." -f a, b)` fallaba en tiempo de ejecución: dentro de los paréntesis de un método, la coma separa argumentos del método y no de `-f`.
- **Defecto del test:** con ese error de formato, los casos de "sin conteos" y "respaldo truncado" pasaban **por otro motivo**. El script fallaba en la línea de formato antes de llegar a `pg_restore`. Desde entonces, cada caso verifica la causa concreta del fallo y no solo el código de salida.
- **Mutaciones:** "no comparar conteos" e "ignorar el código de `pg_restore`" hacen fallar el test.

**Revisión antes del commit.** Un agente revisor de solo lectura encontró tres problemas:
1. **El propio test ponía en riesgo `foodstore`.** El caso 1 usaba `-Target foodstore`: si el control se rompía, el test borraba y restauraba la base principal. Ahora usa una base canario descartable con una fila de marca y verifica que no cambie. Por la misma razón, el control nunca se probó con una mutación.
2. **El control no distinguía mayúsculas** (`-ne`). Con `-Target FOODSTORE_RESTORE_TEST` el script lo aceptaba y **creaba y restauraba otra base** con ese nombre, como se comprobó al agregar el caso al test (RED). Se cambió a `-cne` y el test pasa (GREEN). `foodstore` nunca estuvo expuesta: `dropdb` y `createdb` respetan las mayúsculas del nombre.
3. **El detalle de una corrida fallida incluía un "RTO"**, cuando el RTO solo existe si las validaciones pasan. Se registra después de comprobarlas.

El simulacro se hizo con la versión anterior a estos tres arreglos. Ninguno cambia lo que hace una corrida exitosa, y el caso 5 del test restaura y valida el mismo respaldo con la versión final.

**Límite documentado.** El "último respaldo" se elige por nombre. Si `backup_foodstore.ps1` está escribiendo en ese momento, o dejó un archivo parcial, el simulacro toma ese archivo y falla en `pg_restore` sin volver solo al respaldo anterior. Falla del lado seguro, y por eso las dos tareas no se programan a la misma hora.
