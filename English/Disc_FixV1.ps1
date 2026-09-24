# --- CONFIGURACIÓN INICIAL 2026 (VERSIÓN v1.102 - PPSSPP & RPCS3 UPDATE) ---
# Code implemented by MartStartIV
Clear-Host
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   OPTICAL DRIVE MONITOR v1.102                " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

# Selección de Letra de Unidad
$unidadesDisponibles = @("E", "F", "G", "Z")
Write-Host "Detectable drives: $($unidadesDisponibles -join ', ')" -ForegroundColor Yellow
$letraElegida = Read-Host "Choose the drive letter (Press Enter to load drive E)"
if ([string]::IsNullOrWhiteSpace($letraElegida)) { $letraElegida = "E" }
$driveLetter = "$($letraElegida.ToUpper()):"
$path = "\\.\$driveLetter"

if (-not (Test-Path $driveLetter)) {
    Write-Host "[!] Error: Drive $driveLetter does not exist." -ForegroundColor Red
    pause
    return
}

$opcion = Read-Host "Activate HIGH PERFORMANCE MODE (Turbo) for Emulators? (Y/N)"
$modoTurbo = ($opcion -eq "Y" -or $opcion -eq "y" -or $opcion -eq "S" -or $opcion -eq "s")

# --- VARIABLES DE ESTADO Y AJUSTE DINÁMICO ---
$stats = @{ Exitosos = 0; Saltados = 0; ExitososTurbo = 0; SaltadosTurbo = 0 }
$inicioGlobal = [System.Diagnostics.Stopwatch]::StartNew()
$relojEmulador = New-Object System.Diagnostics.Stopwatch
$buffer = New-Object byte[] 1

# Parámetros de detección de Baja Latencia y Estabilidad
$conteoBajaLatencia = 0
$conteoEstabilidadNormal = 0
$modoBajaLatenciaActivo = $false
$limiteInferior = 0.48
$limiteSuperior = 2.15

Write-Host "`nStarting specialized monitoring on $driveLetter..." -ForegroundColor Green

while($true) {
    try {
        # SE AGREGA PPSSPP Y RPCS3 A LA LISTA DE PROCESOS
        $emuladorActivo = Get-Process -Name "pcsx2", "pcsx2-qt", "ePSXe", "rpcs3", "RPCS3", "PPSSPPWindows64", "PPSSPPWindows" -ErrorAction SilentlyContinue
        
        if ($emuladorActivo) {
            if (-not $relojEmulador.IsRunning) { $relojEmulador.Start() }
        } else {
            if ($relojEmulador.IsRunning) { $relojEmulador.Stop() }
        }

        $tiempo = Measure-Command {
            $streamSonda = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
            $streamSonda.Close()
            $streamSonda.Dispose()
        }
        $ms = $tiempo.TotalMilliseconds
        
        $ejecutarPulso = $false
        $esTurboActual = ($modoTurbo -and $emuladorActivo)
        $motivoSalto = "Out of Range"

        # --- LÓGICA DE PRECISIÓN PARA DETECCIÓN DE HARDWARE ---
        if (-not $modoBajaLatenciaActivo) {
            if ($ms -lt 0.601 -and $ms -gt 0.100) {
                $conteoBajaLatencia++
                $conteoEstabilidadNormal = 0 
                if ($conteoBajaLatencia -ge 6) {
                    $modoBajaLatenciaActivo = $true
                    $limiteInferior = 0.380
                    $limiteSuperior = 1.18
                    Write-Host "`n[!] LOW LATENCY MODE AUTOMATICALLY ACTIVATED" -ForegroundColor Magenta
                }
            } 
            elseif ($ms -ge 0.601) {
                $conteoEstabilidadNormal++
                if ($conteoEstabilidadNormal -ge 8) {
                    $conteoBajaLatencia = 0
                    $conteoEstabilidadNormal = 0
                }
            }
        }

        # --- LÓGICA DE PULSO ADAPTATIVA (MEJORA PPSSPP & RPCS3) ---
        # Definimos límites temporales para el cálculo actual
        $limiteInfActual = $limiteInferior
        $limiteSupActual = $limiteSuperior

        # Si el emulador es PPSSPP o RPCS3, aplicamos el rango especial solicitado
        if ($emuladorActivo -and ($emuladorActivo.Name -like "*PPSSPP*" -or $emuladorActivo.Name -like "*rpcs3*")) {
            $limiteInfActual = 0.15
            $limiteSupActual = 25.98
        }

        if ($emuladorActivo) {
            if ($ms -ge $limiteInfActual -and $ms -le $limiteSupActual) {
                $accion = "GAME MAINTENANCE ($($emuladorActivo.Name))"
                $ejecutarPulso = $true
            } else {
                $motivoSalto = if ($ms -lt $limiteInfActual) { "ACTIVE READING" } else { "HIGH LATENCY" }
            }
        }
        elseif ($ms -ge $limiteInferior -and $ms -le ($limiteSuperior - 0.049)) {
            $accion = "STANDARD IDLE PULSE"
            $ejecutarPulso = $true
        }

        if ($ejecutarPulso) {
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            $stream = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
            $null = $stream.Read($buffer, 0, 1)
            $stream.Close()
            $stream.Dispose()
            
            if($esTurboActual) { $stats.ExitososTurbo++ } else { $stats.Exitosos++ }
            Write-Host ("`n{0} - [{1}] - Latency: {2:N3}ms" -f (Get-Date -Format 'HH:mm:ss'), $accion, $ms) -ForegroundColor Green
        } 
        else {
            if($esTurboActual) { $stats.SaltadosTurbo++ } else { $stats.Saltados++ }
            Write-Host ("`n{0} - [SKIPPED] - {1} ({2:N3}ms)" -f (Get-Date -Format 'HH:mm:ss'), $motivoSalto, $ms) -ForegroundColor Cyan
        }
    } 
    catch {
        Write-Host "`n$(Get-Date -Format 'HH:mm:ss') - [!] Drive busy (Data reading)." -ForegroundColor Yellow
    }

    # PANEL DE ESTADÍSTICAS
    $colorPanel = if($modoBajaLatenciaActivo){ "Magenta" } else { "White" }
    Write-Host "`n[ GLOBAL SESSION: $($inicioGlobal.Elapsed.ToString('hh\:mm\:ss')) | OK: $($stats.Exitosos) | SKIPPED: $($stats.Saltados) ]" -ForegroundColor $colorPanel
    
    if ($relojEmulador.ElapsedMilliseconds -gt 0) {
        $colorSesion = if ($emuladorActivo) { "Green" } else { "Gray" }
        $estadoJuego = if ($emuladorActivo) { "RUNNING" } else { "PAUSED/CLOSED" }
        Write-Host "[ GAME SESSION ($estadoJuego): $($relojEmulador.Elapsed.ToString('hh\:mm\:ss')) ]" -ForegroundColor $colorSesion
        if($modoTurbo) {
            Write-Host "[ TURBO MODE ACTIVE | OK: $($stats.ExitososTurbo) | SKIPPED: $($stats.SaltadosTurbo) ]" -ForegroundColor Red
        }
    }

    # Gestión de tiempos de espera (Optimizado con While para evitar descontrol)
    $segundosEspera = if ($emuladorActivo) { if ($modoTurbo) { 5 } else { 22 } } else { 23 }
    $i = $segundosEspera
    while ($i -gt 0) {
        
        # COMPROBACIÓN DE TECLAS AL VUELO (' o +)
        if ([System.Console]::KeyAvailable) {
            $tecla = [System.Console]::ReadKey($true)
            if ($tecla.KeyChar -eq '´' -or $tecla.KeyChar -eq '+') {
                $modoTurbo = -not $modoTurbo
                [System.Console]::Beep(800, 100) # Sonido rápido de confirmación
                
                # Ajustamos la cuenta regresiva de forma lineal y segura
                if ($emuladorActivo) {
                    if ($modoTurbo -and $i -gt 5) { $i = 5 }
                    elseif (-not $modoTurbo) { $i = 22 }
                }
            }
        }

        $esTurboActual = ($modoTurbo -and $emuladorActivo)
        $statusExtra = if($modoBajaLatenciaActivo){ " (LOW-LAT)" } else { "" }
        $textoEstado = if($esTurboActual){ "TURBO" } else { "ESPERA$statusExtra" }
        $msg = "`r{0}: {1} sec. remaining... Toggle Turbo: [´] or [+]      " -f $textoEstado, $i
        Write-Host -NoNewline $msg
        
        Start-Sleep -Seconds 1
        $i--
    }
    Write-Host "" 
}
