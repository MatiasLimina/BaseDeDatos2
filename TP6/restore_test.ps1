<#
.SYNOPSIS
    Restauracion de prueba semanal del ultimo respaldo (SPEC_U6.md, Parte 4).

.DESCRIPTION
    1. Toma el ultimo backups\foodstore_<fecha>_<hora>.dump y su .counts.csv.
    2. Calcula el RPO observado: antiguedad del respaldo al comenzar el simulacro.
    3. Borra foodstore_restore_test si existe (fuera del cronometro).
    4. Cronometro: createdb + pg_restore --no-owner --no-privileges + validaciones
       (conteos contra el .counts.csv, productos y detalles invalidos = 0).
       El tiempo hasta que las validaciones terminan bien es el RTO observado.
    5. Despues del cronometro ejecuta ANALYZE: pg_restore no trae estadisticas
       del planificador. Se informa aparte.
    6. Agrega una linea OK o ERROR a logs\restore_test.log y deja el detalle en
       logs\restore_test_<fecha>_<hora>.txt.

    Solo acepta como destino foodstore_restore_test: foodstore nunca se borra,
    reemplaza ni restaura. La contrasena sale de %APPDATA%\postgresql\pgpass.conf (-w).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\restore_test.ps1
#>
[CmdletBinding()]
param(
    [string]$DbHost    = 'localhost',
    [int]   $Port      = 5432,
    [string]$User      = 'postgres',
    [string]$Target    = 'foodstore_restore_test',
    [string]$BackupDir,
    [string]$LogDir
)

$ErrorActionPreference = 'Stop'

# Unico destino permitido (SPEC_U6.md, regla 2).
$DestinoPermitido = 'foodstore_restore_test'

# En PowerShell 5.1 $PSScriptRoot todavia esta vacio al evaluar los valores por defecto
# de param(), asi que las carpetas se resuelven aca.
if (-not $BackupDir) { $BackupDir = Join-Path $PSScriptRoot 'backups' }
if (-not $LogDir)    { $LogDir    = Join-Path $PSScriptRoot 'logs' }

# Mismas tablas que backup_foodstore.ps1 registra en el .counts.csv, y los dos controles
# de restricciones logicas de la consigna (en el esquema, la tabla es pedido_detalle).
$ValidacionSql = @"
SELECT 'categoria', COUNT(*) FROM categoria
UNION ALL SELECT 'cliente', COUNT(*) FROM cliente
UNION ALL SELECT 'producto', COUNT(*) FROM producto
UNION ALL SELECT 'pedido', COUNT(*) FROM pedido
UNION ALL SELECT 'pedido_detalle', COUNT(*) FROM pedido_detalle
UNION ALL SELECT 'productos_invalidos', COUNT(*) FROM producto WHERE precio < 0 OR stock < 0
UNION ALL SELECT 'detalles_invalidos', COUNT(*) FROM pedido_detalle
          WHERE cantidad <= 0 OR precio_unitario < 0;
"@

$LogFile = Join-Path $LogDir 'restore_test.log'

# Los clientes escriben sus mensajes en la pagina de codigos ANSI y PowerShell los lee como
# OEM, lo que desfigura los acentos del log. Se piden los mensajes del cliente en ingles y
# los del servidor en UTF-8, y la salida se decodifica como UTF-8.
$env:LC_MESSAGES      = 'C'
$env:PGCLIENTENCODING = 'UTF8'
# [Console]::OutputEncoding se fija dentro del try: sin consola (tarea programada) puede fallar.

function Write-Log([string]$Nivel, [string]$Mensaje) {
    $linea = '{0} {1} {2}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'), $Nivel, $Mensaje
    Add-Content -Path $LogFile -Value $linea -Encoding UTF8
    Write-Host $linea
}

# Ejecuta un cliente de PostgreSQL y devuelve su codigo de salida y su salida (stdout + stderr).
# En PowerShell 5.1, con ErrorActionPreference = 'Stop', redirigir el stderr de un programa
# nativo lanza una excepcion en la primera linea; por eso se relaja solo durante la llamada.
function Invoke-Cliente([string]$Programa, [string[]]$Argumentos) {
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $salida = & $Programa @Argumentos 2>&1 | ForEach-Object { "$_" }
        return @{ Codigo = $LASTEXITCODE; Salida = @($salida) }
    } finally {
        $ErrorActionPreference = $anterior
    }
}

function Format-Duracion([TimeSpan]$t) {
    '{0}d {1:00}:{2:00}:{3:00}' -f $t.Days, $t.Hours, $t.Minutes, $t.Seconds
}

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$conexion = @('-h', $DbHost, '-p', "$Port", '-U', $User, '-w')
$informe  = Join-Path $LogDir ("restore_test_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$detalle  = New-Object System.Collections.Generic.List[string]

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

    # -cne: los nombres de base distinguen mayusculas y -ne no (FOODSTORE_RESTORE_TEST
    # seria otra base y pasaria el control; probado).
    if ($Target -cne $DestinoPermitido) {
        throw "destino '$Target' rechazado: solo se restaura sobre $DestinoPermitido"
    }
    foreach ($programa in 'psql', 'createdb', 'dropdb', 'pg_restore') {
        if (-not (Get-Command $programa -ErrorAction SilentlyContinue)) {
            throw "$programa no esta en el PATH"
        }
    }

    # 1. Ultimo respaldo: el nombre lleva fecha y hora, asi que el orden alfabetico es el
    #    cronologico. Si backup_foodstore.ps1 esta escribiendo en ese momento (o dejo un
    #    parcial), se toma ese archivo y pg_restore falla: el simulacro termina en ERROR y
    #    no vuelve solo al respaldo anterior. No hay que programarlo junto con el respaldo.
    $dump = Get-ChildItem -Path $BackupDir -Filter 'foodstore_*.dump' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
    if (-not $dump) { throw "no hay respaldos foodstore_*.dump en $BackupDir" }
    if ($dump.Name -notmatch '_(\d{8}_\d{6})\.dump$') {
        throw "$($dump.Name) no tiene fecha y hora en el nombre"
    }
    $fechaRespaldo = [datetime]::ParseExact($Matches[1], 'yyyyMMdd_HHmmss', $null)
    $countsFile = Join-Path $BackupDir ($dump.BaseName + '.counts.csv')
    if (-not (Test-Path $countsFile)) {
        throw "falta ${countsFile}: sin los conteos previos no se puede validar"
    }
    $esperado = @{}
    foreach ($linea in Get-Content -Path $countsFile -Encoding UTF8) {
        if ($linea -match '^(\w+);(\d+)$') { $esperado[$Matches[1]] = [long]$Matches[2] }
    }
    if ($esperado.Count -ne 5) {
        throw "$countsFile deberia tener 5 conteos y tiene $($esperado.Count)"
    }

    # 2. RPO observado.
    $inicio = Get-Date
    $rpo = $inicio - $fechaRespaldo
    # Doble parentesis: dentro de .Add(...) la coma separaria argumentos del metodo, no de -f.
    $detalle.Add(("Respaldo:   $($dump.Name) ({0:N1} MB), creado {1:yyyy-MM-dd HH:mm:ss}" -f
                  ($dump.Length / 1MB), $fechaRespaldo))
    $detalle.Add(("Simulacro:  {0:yyyy-MM-dd HH:mm:ss}" -f $inicio))
    $detalle.Add("RPO observado (antiguedad del respaldo): $(Format-Duracion $rpo)")

    # 3. Base de prueba anterior: se borra fuera del cronometro. --force cierra las
    #    sesiones abiertas sobre ESA base (PostgreSQL 13+); el nombre ya se valido arriba.
    $borrado = Invoke-Cliente 'dropdb' ($conexion + @('--if-exists', '--force', $Target))
    if ($borrado.Codigo -ne 0) { throw "dropdb $Target fallo: $($borrado.Salida -join ' | ')" }

    # 4. Cronometro: crear, restaurar y validar.
    $reloj = [Diagnostics.Stopwatch]::StartNew()

    $creada = Invoke-Cliente 'createdb' ($conexion + @($Target))
    if ($creada.Codigo -ne 0) { throw "createdb $Target fallo: $($creada.Salida -join ' | ')" }
    $tCreate = $reloj.Elapsed.TotalSeconds

    $restaurada = Invoke-Cliente 'pg_restore' ($conexion + @('-d', $Target, '--no-owner',
                                                             '--no-privileges', '--exit-on-error',
                                                             $dump.FullName))
    if ($restaurada.Codigo -ne 0) {
        throw "pg_restore fallo (codigo $($restaurada.Codigo)): $($restaurada.Salida -join ' | ')"
    }
    $tRestore = $reloj.Elapsed.TotalSeconds

    $validacion = Invoke-Cliente 'psql' ($conexion + @('-X', '-d', $Target, '-v', 'ON_ERROR_STOP=1',
                                                       '-At', '-F', ';', '-c', $ValidacionSql))
    if ($validacion.Codigo -ne 0) {
        throw "la validacion fallo: $($validacion.Salida -join ' | ')"
    }
    $obtenido = @{}
    foreach ($linea in $validacion.Salida) {
        if ($linea -match '^(\w+);(\d+)$') { $obtenido[$Matches[1]] = [long]$Matches[2] }
    }
    $reloj.Stop()
    $rto = $reloj.Elapsed

    $errores = New-Object System.Collections.Generic.List[string]
    $detalle.Add('')
    $detalle.Add('Validacion           esperado    restaurado')
    foreach ($tabla in 'categoria', 'cliente', 'producto', 'pedido', 'pedido_detalle') {
        $marca = if ($obtenido[$tabla] -eq $esperado[$tabla]) { 'OK' } else { 'DIFIERE' }
        $detalle.Add(('{0,-18} {1,10} {2,13}  {3}' -f $tabla, $esperado[$tabla], $obtenido[$tabla], $marca))
        if ($marca -ne 'OK') {
            $errores.Add("$tabla tiene $($obtenido[$tabla]) filas y se esperaban $($esperado[$tabla])")
        }
    }
    foreach ($control in 'productos_invalidos', 'detalles_invalidos') {
        $marca = if ($obtenido[$control] -eq 0) { 'OK' } else { 'DISTINTO DE 0' }
        $detalle.Add(('{0,-18} {1,10} {2,13}  {3}' -f $control, 0, $obtenido[$control], $marca))
        if ($marca -ne 'OK') { $errores.Add("$control = $($obtenido[$control])") }
    }

    # El RTO solo existe si las validaciones pasan: se registra despues de comprobarlo.
    if ($errores.Count -gt 0) {
        throw "validacion con diferencias: $($errores -join '; ')"
    }

    $detalle.Add('')
    $detalle.Add(('RTO observado: {0:N1} s (createdb {1:N1} s, pg_restore {2:N1} s, validacion {3:N1} s)' -f
                  $rto.TotalSeconds, $tCreate, ($tRestore - $tCreate), ($rto.TotalSeconds - $tRestore)))

    # 5. Estadisticas del planificador (fuera del cronometro).
    $relojAnalyze = [Diagnostics.Stopwatch]::StartNew()
    $analyze = Invoke-Cliente 'psql' ($conexion + @('-X', '-d', $Target, '-v', 'ON_ERROR_STOP=1',
                                                    '-q', '-c', 'ANALYZE'))
    if ($analyze.Codigo -ne 0) { throw "ANALYZE fallo: $($analyze.Salida -join ' | ')" }
    $detalle.Add(('ANALYZE posterior (fuera del RTO): {0:N1} s' -f $relojAnalyze.Elapsed.TotalSeconds))

    Set-Content -Path $informe -Value $detalle -Encoding UTF8
    Write-Log 'OK' ('{0} restaurado en {1}; RPO {2}; RTO {3:N1} s; 5/5 conteos, 0 invalidos; detalle en {4}' -f
        $dump.Name, $Target, (Format-Duracion $rpo), $rto.TotalSeconds, (Split-Path $informe -Leaf))
    $detalle | ForEach-Object { Write-Host $_ }
    exit 0
}
catch {
    if ($detalle.Count -gt 0) { Set-Content -Path $informe -Value $detalle -Encoding UTF8 }
    $detalle | ForEach-Object { Write-Host $_ }
    Write-Log 'ERROR' ("restauracion de prueba fallida: {0}" -f $_.Exception.Message)
    exit 1
}
