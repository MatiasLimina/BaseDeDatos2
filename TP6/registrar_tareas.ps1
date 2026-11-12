<#
.SYNOPSIS
    Registra en el Programador de tareas de Windows las 4 tareas de SPEC_U6.md.

.DESCRIPTION
    Crea (o reemplaza) las tareas dentro de la carpeta \FoodStore\ del Programador:

      Tarea                     Script                 Cuando
      FoodStore-Respaldo        backup_foodstore.ps1   diaria 02:00
      FoodStore-ChequeoSalud    health_check.sql       diaria 02:30 (despues del respaldo)
      FoodStore-Mantenimiento   maintenance.sql        domingo 03:00
      FoodStore-RestorePrueba   restore_test.ps1       domingo 03:30 (despues de la revision)

    Cada tarea se detiene si corre mas de 30 min (SPEC_U6.md, "Programacion prevista").
    Los horarios estan separados 30 min para que una tarea no arranque antes de que la
    anterior haya terminado o haya sido cortada por ese limite.

    Al final deja la configuracion registrada en evidencias\parte2_tareas_programadas.txt.
    No necesita permisos de administrador: registra las tareas para el usuario actual,
    que es quien tiene el pgpass.conf.

.PARAMETER Quitar
    Borra las 4 tareas en lugar de crearlas.

.PARAMETER ProbarAhora
    Despues de registrar, lanza FoodStore-ChequeoSalud una vez (solo lectura) para
    comprobar que la tarea encuentra psql y la credencial.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\registrar_tareas.ps1 -ProbarAhora
#>
[CmdletBinding()]
param(
    # Base sobre la que trabajan las tareas. La SPEC usa foodstore; en un equipo donde
    # la base tiene otro nombre (p. ej. food_store_copia) se indica aca.
    [ValidatePattern('^[a-z_][a-z0-9_]*$')]
    [string]$Database = 'foodstore',
    [switch]$Quitar,
    [switch]$ProbarAhora,
    # Solo regenera la evidencia, sin volver a registrar (re-registrar borra el
    # historial de ultima ejecucion y resultado).
    [switch]$SoloReporte
)

$ErrorActionPreference = 'Stop'
$carpeta = '\FoodStore\'
$tp6     = $PSScriptRoot
$nombres = 'FoodStore-Respaldo', 'FoodStore-ChequeoSalud', 'FoodStore-Mantenimiento', 'FoodStore-RestorePrueba'

if ($Quitar) {
    foreach ($n in $nombres) {
        Unregister-ScheduledTask -TaskPath $carpeta -TaskName $n -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Quitada: $carpeta$n"
    }
    return
}

# Las tareas heredan el PATH del usuario; se verifica ahora para no descubrirlo a las 02:00.
foreach ($programa in 'psql', 'pg_dump', 'pg_restore') {
    if (-not (Get-Command $programa -ErrorAction SilentlyContinue)) {
        throw "$programa no esta en el PATH. Agregar la carpeta bin de PostgreSQL antes de registrar."
    }
}

function New-AccionPs([string]$argumentos) {
    New-ScheduledTaskAction -Execute 'powershell.exe' -WorkingDirectory $tp6 `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File $argumentos"
}

$tareas = @(
    @{ Nombre  = 'FoodStore-Respaldo'
       Accion  = New-AccionPs "`"$tp6\backup_foodstore.ps1`" -Database $Database"
       Disparo = New-ScheduledTaskTrigger -Daily -At '02:00'
       Desc    = "Respaldo diario pg_dump -Fc de $Database (SPEC_U6.md)." },
    @{ Nombre  = 'FoodStore-ChequeoSalud'
       Accion  = New-AccionPs "`"$tp6\ejecutar_sql.ps1`" -Script health_check.sql -Prefijo health -Database $Database"
       Disparo = New-ScheduledTaskTrigger -Daily -At '02:30'
       Desc    = 'Chequeo de salud diario, despues del respaldo (SPEC_U6.md).' },
    @{ Nombre  = 'FoodStore-Mantenimiento'
       Accion  = New-AccionPs "`"$tp6\ejecutar_sql.ps1`" -Script maintenance.sql -Prefijo maintenance -Database $Database"
       Disparo = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '03:00'
       Desc    = 'Revision semanal de mantenimiento: VACUUM/ANALYZE solo si supera el umbral (SPEC_U6.md).' },
    @{ Nombre  = 'FoodStore-RestorePrueba'
       Accion  = New-AccionPs "`"$tp6\restore_test.ps1`" -Origen $Database"
       Disparo = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '03:30'
       Desc    = 'Restauracion de prueba semanal en foodstore_restore_test, con RTO/RPO (SPEC_U6.md).' }
)

# --- Configuracion comun a las 4 tareas: quien las ejecuta y como se comportan ---
# Interactive: corre con la sesion del usuario iniciada. No guarda ninguna contrasena de
# Windows en la tarea (regla 1 de la SPEC) y lee el pgpass.conf del usuario.
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive
# StartWhenAvailable: si el equipo estaba apagado o sin sesion a la hora programada, la
# tarea corre en cuanto se pueda, en lugar de esperar al dia (o domingo) siguiente.
$config    = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -StartWhenAvailable

foreach ($t in $tareas) {
    if ($SoloReporte) { break }
    Register-ScheduledTask -TaskPath $carpeta -TaskName $t.Nombre -Description $t.Desc `
        -Action $t.Accion -Trigger $t.Disparo -Principal $principal -Settings $config -Force | Out-Null
    Write-Host "Registrada: $carpeta$($t.Nombre)"
}

if ($ProbarAhora) {
    Start-ScheduledTask -TaskPath $carpeta -TaskName 'FoodStore-ChequeoSalud'
    # Esperar a que termine (el chequeo tarda segundos; tope de 2 min).
    $limite = (Get-Date).AddMinutes(2)
    do { Start-Sleep -Seconds 2 } while (
        (Get-ScheduledTask -TaskPath $carpeta -TaskName 'FoodStore-ChequeoSalud').State -eq 'Running' -and
        (Get-Date) -lt $limite)
}

# --- Evidencia: lo que quedo registrado, leido de vuelta del Programador ---
$evidencia = Join-Path $tp6 'evidencias\parte2_tareas_programadas.txt'
$reporte = foreach ($n in $nombres) {
    $tarea = Get-ScheduledTask -TaskPath $carpeta -TaskName $n
    $info  = Get-ScheduledTaskInfo -TaskPath $carpeta -TaskName $n
    [pscustomobject]@{
        Tarea          = $carpeta + $n
        Estado         = $tarea.State
        Disparador     = ($tarea.Triggers | ForEach-Object {
                              $d = if ($_.DaysOfWeek) { 'semanal' } else { 'diaria' }
                              '{0} {1:HH:mm}' -f $d, [datetime]$_.StartBoundary }) -join ', '
        LimiteEjecucion = $tarea.Settings.ExecutionTimeLimit
        Ejecuta        = "$($tarea.Actions[0].Execute) $($tarea.Actions[0].Arguments)"
        Usuario        = "$($tarea.Principal.UserId) ($($tarea.Principal.LogonType))"
        ProximaEjecucion = $info.NextRunTime
        UltimaEjecucion  = $info.LastRunTime
        UltimoResultado  = $info.LastTaskResult
    }
}
$encabezado = "Tareas programadas de Food Store - registradas el $(Get-Date -Format s) en $env:COMPUTERNAME`r`n" +
              "Base de origen: $Database`r`n" +
              "UltimoResultado: 0 = exito; 267011 = nunca se ejecuto.`r`n"
($encabezado + ($reporte | Format-List | Out-String)) | Set-Content -Path $evidencia -Encoding UTF8
Write-Host "Evidencia: $evidencia"
