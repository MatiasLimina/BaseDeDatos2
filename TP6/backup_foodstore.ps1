<#
.SYNOPSIS
    Respaldo diario de foodstore en formato custom (SPEC_U6.md, Parte 2).

.DESCRIPTION
    1. Registra los conteos de las tablas validadas en la restauracion
       (backups\foodstore_<fecha>_<hora>.counts.csv), inmediatamente antes del respaldo.
    2. Ejecuta pg_dump -Fc hacia backups\foodstore_<fecha>_<hora>.dump.
    3. Comprueba que el archivo exista, no este vacio y que pg_restore --list lo lea.
    4. Agrega una linea OK o ERROR a logs\backup_foodstore.log.

    Termina con codigo 0 si todo salio bien y con 1 ante cualquier fallo; en ese caso
    borra el .dump y el .counts.csv parciales para que no se confundan con una copia valida.

    La contrasena NO se escribe aqui: sale de %APPDATA%\postgresql\pgpass.conf. Los clientes
    se invocan con -w (nunca preguntar), asi que si falta la credencial el script falla en
    lugar de quedar esperando.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\backup_foodstore.ps1
#>
[CmdletBinding()]
param(
    [string]$DbHost    = 'localhost',
    [int]   $Port      = 5432,
    [string]$User      = 'postgres',
    [string]$Database  = 'foodstore',
    # Un respaldo programado no debe quedar colgado si otra sesion bloquea una tabla.
    [string]$LockWaitTimeout = '60s',
    [string]$BackupDir,
    [string]$LogDir
)

$ErrorActionPreference = 'Stop'

# En PowerShell 5.1 $PSScriptRoot todavia esta vacio al evaluar los valores por defecto
# de param(), asi que las carpetas se resuelven aca.
if (-not $BackupDir) { $BackupDir = Join-Path $PSScriptRoot 'backups' }
if (-not $LogDir)    { $LogDir    = Join-Path $PSScriptRoot 'logs' }

# Tablas cuyos conteos se comparan despues de restaurar (SPEC_U6.md, "Validacion").
$ConteosSql = @"
SELECT 'categoria', COUNT(*) FROM categoria
UNION ALL SELECT 'cliente', COUNT(*) FROM cliente
UNION ALL SELECT 'producto', COUNT(*) FROM producto
UNION ALL SELECT 'pedido', COUNT(*) FROM pedido
UNION ALL SELECT 'pedido_detalle', COUNT(*) FROM pedido_detalle;
"@

$LogFile = Join-Path $LogDir 'backup_foodstore.log'

# Los clientes escriben sus mensajes en la pagina de codigos ANSI y PowerShell los lee como
# OEM, lo que desfigura los acentos del log. Se piden los mensajes del cliente en ingles y
# los del servidor en UTF-8, y la salida se decodifica como UTF-8.
$env:LC_MESSAGES      = 'C'
$env:PGCLIENTENCODING = 'UTF8'
# [Console]::OutputEncoding se fija dentro del try: sin consola (tarea programada) puede fallar.

# Si otra sesion bloquea una tabla, tanto el COUNT(*) como pg_dump esperan sin limite.
# Para psql alcanza con lock_timeout. pg_dump lo pone en 0 al conectarse, asi que se limita
# con --lock-wait-timeout, que solo cubre su LOCK TABLE inicial: una vista materializada
# bloqueada lo sigue haciendo esperar (probado). Ese caso lo corta el limite de duracion
# de la tarea programada (SPEC_U6.md).
$env:PGOPTIONS = "-c lock_timeout=$LockWaitTimeout"

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

New-Item -ItemType Directory -Force -Path $BackupDir, $LogDir | Out-Null

$marca      = Get-Date -Format 'yyyyMMdd_HHmmss'
$dumpFile   = Join-Path $BackupDir ("{0}_{1}.dump" -f $Database, $marca)
$countsFile = Join-Path $BackupDir ("{0}_{1}.counts.csv" -f $Database, $marca)
$conexion   = @('-h', $DbHost, '-p', "$Port", '-U', $User, '-w')

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false

    foreach ($programa in 'psql', 'pg_dump', 'pg_restore') {
        if (-not (Get-Command $programa -ErrorAction SilentlyContinue)) {
            throw "$programa no esta en el PATH"
        }
    }

    $conteos = Invoke-Cliente 'psql' ($conexion + @('-X', '-d', $Database, '-v', 'ON_ERROR_STOP=1',
                                                    '-At', '-F', ';', '-c', $ConteosSql))
    if ($conteos.Codigo -ne 0) {
        throw "psql (conteos) termino con codigo $($conteos.Codigo): $($conteos.Salida -join ' | ')"
    }
    # La salida mezcla stdout y stderr: un WARNING o NOTICE de una corrida exitosa no debe
    # terminar en el archivo de conteos, porque romperia la comparacion de la restauracion.
    $filas = @($conteos.Salida | Where-Object { $_ -match '^\w+;\d+$' })
    if ($filas.Count -ne 5) {
        throw "se esperaban 5 conteos y llegaron $($filas.Count): $($conteos.Salida -join ' | ')"
    }
    Set-Content -Path $countsFile -Value (@('tabla;filas') + $filas) -Encoding UTF8

    $inicio = Get-Date
    $dump = Invoke-Cliente 'pg_dump' ($conexion + @('-d', $Database, '-Fc',
                                                  "--lock-wait-timeout=$LockWaitTimeout", '-f', $dumpFile))
    $segundos = ((Get-Date) - $inicio).TotalSeconds
    if ($dump.Codigo -ne 0) {
        throw "pg_dump termino con codigo $($dump.Codigo): $($dump.Salida -join ' | ')"
    }

    if (-not (Test-Path $dumpFile) -or (Get-Item $dumpFile).Length -eq 0) {
        throw "pg_dump termino bien pero $dumpFile no existe o esta vacio"
    }
    $lista = Invoke-Cliente 'pg_restore' @('--list', $dumpFile)
    if ($lista.Codigo -ne 0) {
        throw "pg_restore --list no pudo leer el respaldo: $($lista.Salida -join ' | ')"
    }

    $mb = (Get-Item $dumpFile).Length / 1MB
    Write-Log 'OK' ('{0} {1:N1} MB en {2:N1} s; conteos en {3}' -f `
        (Split-Path $dumpFile -Leaf), $mb, $segundos, (Split-Path $countsFile -Leaf))
    exit 0
}
catch {
    Remove-Item -Path $dumpFile, $countsFile -Force -ErrorAction SilentlyContinue
    Write-Log 'ERROR' ("respaldo de {0} fallido: {1}" -f $Database, $_.Exception.Message)
    exit 1
}
