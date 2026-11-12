<#
.SYNOPSIS
    Ejecuta health_check.sql, maintenance.sql o integrity_check.sql desde una tarea programada (SPEC_U6.md).

.DESCRIPTION
    El Programador de tareas no puede armar por si solo un nombre de archivo con la fecha,
    asi que este envoltorio:
    1. Corre psql -X -w -v ON_ERROR_STOP=1 -f <Script> contra la base indicada.
    2. Deja la salida en logs\<Prefijo>_AAAAMMDD_HHMMSS.txt.
    3. Agrega una linea OK o ERROR a logs\tareas_programadas.log.
    4. Termina con el mismo codigo de salida que psql, que queda en el historial de la tarea.

    La contrasena sale de %APPDATA%\postgresql\pgpass.conf (-w: nunca preguntar).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\ejecutar_sql.ps1 -Script health_check.sql -Prefijo health
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('health_check.sql', 'maintenance.sql', 'integrity_check.sql')]
    [string]$Script,
    [Parameter(Mandatory)][string]$Prefijo,
    [string]$DbHost   = 'localhost',
    [int]   $Port     = 5432,
    [string]$User     = 'postgres',
    [string]$Database = 'foodstore',
    [string]$LogDir
)

$ErrorActionPreference = 'Stop'
if (-not $LogDir) { $LogDir = Join-Path $PSScriptRoot 'logs' }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$env:LC_MESSAGES      = 'C'
$env:PGCLIENTENCODING = 'UTF8'

$sello   = Get-Date -Format 'yyyyMMdd_HHmmss'
$salida  = Join-Path $LogDir "${Prefijo}_$sello.txt"
$log     = Join-Path $LogDir 'tareas_programadas.log'
$sqlPath = Join-Path $PSScriptRoot $Script
$inicio  = Get-Date

$psqlArgs = @('-X', '-w', '-h', $DbHost, '-p', $Port, '-U', $User, '-d', $Database,
              '-v', 'ON_ERROR_STOP=1', '-f', $sqlPath, '-o', $salida)
# Los errores de psql van a stderr; se guardan para que el log diga por que fallo.
# En PowerShell 5.1, con 'Stop', cada linea de stderr de un programa externo se vuelve un
# error terminante y el script se cortaria antes de escribir el log (mismo patron que
# Invoke-Cliente en backup_foodstore.ps1).
$ErrorActionPreference = 'Continue'
$errores = & psql @psqlArgs 2>&1 | ForEach-Object { "$_" }
$codigo  = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
$segundos = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)

if ($codigo -eq 0) {
    $linea = "{0} OK    {1} -> {2} ({3} s)" -f (Get-Date -Format s), $Script, (Split-Path $salida -Leaf), $segundos
} else {
    $detalle = ($errores -join ' | ')
    $linea = "{0} ERROR {1} codigo {2} ({3} s): {4}" -f (Get-Date -Format s), $Script, $codigo, $segundos, $detalle
}
Add-Content -Path $log -Value $linea -Encoding UTF8
exit $codigo
