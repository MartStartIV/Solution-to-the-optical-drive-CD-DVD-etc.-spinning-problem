# --- VERSIÓN v1.421 - Se ha agregado su registro con limite de peso total para los que quieran verl el historico de lo realizado por la herramienta + boton de pausa y su salida desde la misma interfaz ---
# Codigo llevado a cabo por MartStartIV
Clear-Host
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   MONITOR DE UNIDAD ÓPTICA V1.421             " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

# Selección de Letra de Unidad
$unidadesDisponibles = @("E", "F", "G", "Z")
Write-Host "Unidades detectables: $($unidadesDisponibles -join ', ')" -ForegroundColor Yellow
$letraElegida = Read-Host "Elija la letra de la unidad (Presione Enter para cargar unidad E)"
if ([string]::IsNullOrWhiteSpace($letraElegida)) { $letraElegida = "E" }
$driveLetter = "$($letraElegida.ToUpper()):"
$path = "\\.\$driveLetter"

if (-not (Test-Path $driveLetter)) {
    Write-Host "[!] Error: La unidad $driveLetter no existe." -ForegroundColor Red
    pause
    return
}

$opcion = Read-Host "¿Activar MODO ALTO RENDIMIENTO (Turbo) para Emuladores? (S/N)"
$modoTurbo = ($opcion -eq "S" -or $opcion -eq "s")

# --- VARIABLES DE ESTADO Y AJUSTE DINÁMICO ---
$stats = @{ Exitosos = 0; Saltados = 0; ExitososTurbo = 0; SaltadosTurbo = 0 }
$inicioGlobal = [System.Diagnostics.Stopwatch]::StartNew()
$relojEmulador = New-Object System.Diagnostics.Stopwatch
$buffer = New-Object byte[] 1

$docPath = [System.Environment]::GetFolderPath("MyDocuments")
$logDir = Join-Path -Path $docPath -ChildPath "Disc Rotation Tool LOGS"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path -Path $logDir -ChildPath "Disc_Tools_Log.txt"

"===============================================" | Out-File $logFile -Append -Encoding utf8
"HERRAMIENTA INICIADA: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $logFile -Append -Encoding utf8
"===============================================" | Out-File $logFile -Append -Encoding utf8
$global:pausado = $false

function Write-Log($msg) {
    "{0} - {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg | Out-File $logFile -Append -Encoding utf8
    if ((Get-Item $logFile).Length -gt 5MB) {
        $lineas = Get-Content $logFile
        $lineas[($lineas.Count/4)..($lineas.Count-1)] | Out-File $logFile -Encoding utf8
    }
}


# Parámetros de detección de Baja Latencia y Estabilidad
$conteoBajaLatencia = 0
$conteoEstabilidadNormal = 0
$modoBajaLatenciaActivo = $false
$limiteInferior = 0.48
$limiteSuperior = 3.87
# --- MEJORA: VARIABLES DE TELEMETRÍA GLOBAL DE TRÁFICO ---
$globalSnapshot = @{}
$bytesTransferidosUltimoSegundo = 0
$lastBytes = 0

Write-Host "`nIniciando monitoreo especializado en $driveLetter..." -ForegroundColor Green

while($true) {
    try {

        if ($global:pausado) {
            Write-Host "`r[!] MONITOREO EN PAUSA (Unidad Óptica Descansando)... Controles: [-]Reanudar [*]Salir    " -ForegroundColor Yellow -NoNewline
            
            # --- LEER TECLADO DURANTE LA PAUSA PARA EVITAR QUE SE QUEDE PEGADO ---
            if ([System.Console]::KeyAvailable) {
                $teclaPausa = [System.Console]::ReadKey($true)
                if ($teclaPausa.KeyChar -eq '-') { 
                    $global:pausado = -not $global:pausado
                    [System.Console]::Beep(600, 150) 
                }
                                if ($teclaPausa.KeyChar -eq '*') { 
                    "`nHERRAMIENTA CERRADA DESDE PAUSA: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $logFile -Append -Encoding utf8
                    [System.Console]::Beep(400, 200); Exit 
                }
            }
            
            Start-Sleep -Milliseconds 250 # Espera corta para mantener el teclado responsivo y no saturar el CPU
            continue
        }
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
        $motivoSalto = "Fuera de Rango"

        # --- LÓGICA DE PRECISIÓN PARA DETECCIÓN DE HARDWARE ---
        if (-not $modoBajaLatenciaActivo) {
            if ($ms -lt 0.601 -and $ms -gt 0.100) {
                $conteoBajaLatencia++
                $conteoEstabilidadNormal = 0 
                if ($conteoBajaLatencia -ge 6) {
                    $modoBajaLatenciaActivo = $true
                    $limiteInferior = 0.380
                    $limiteSuperior = 1.18
                    Write-Host "`n[!] MODO BAJA LATENCIA ACTIVADO AUTOMÁTICAMENTE" -ForegroundColor Magenta
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

        # --- LÓGICA DE PULSO ADAPTATIVA (MEJORA PPSSPP) ---
        # Definimos límites temporales para el cálculo actual
        $limiteInfActual = $limiteInferior
        $limiteSupActual = $limiteSuperior

        # Si el emulador es PPSSPP, aplicamos el rango especial solicitado
        if ($emuladorActivo -and ($emuladorActivo.Name -like "*PPSSPP*")) {
            $limiteInfActual = 0.15
            $limiteSupActual = 25.98
        }

        if ($emuladorActivo) {
            if ($ms -ge $limiteInfActual -and $ms -le $limiteSupActual) {
                $accion = "MANTENIMIENTO JUEGO ($($emuladorActivo.Name))"
                $ejecutarPulso = $true
            } else {
                $motivoSalto = if ($ms -lt $limiteInfActual) { "LECTURA ACTIVA" } else { "LATENCIA ALTA" }
            }
        }
        elseif ($ms -ge $limiteInferior -and $ms -le ($limiteSuperior - 0.049)) {
            $accion = "PULSO REPOSO ESTÁNDAR"
            $ejecutarPulso = $true
        }

        # --- FILTRO INTELIGENTE: SI JUEGO LEE, SE CANCELA EL PULSO PARA EVITAR TIRONES ---
        if ($ejecutarPulso -and $bytesTransferidosUltimoSegundo -gt 10KB) { $ejecutarPulso = $false; $motivoSalto = "LECTURA ACTIVA JUEGO" }

        if ($ejecutarPulso) {
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            $stream = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
            $null = $stream.Read($buffer, 0, 1)
            $stream.Close()
            $stream.Dispose()
            
            if ($esTurboActual) { $stats.ExitososTurbo++ } else { $stats.Exitosos++ }
            Write-Host ("`n{0} - [{1}] - Latencia: {2:N3}ms" -f (Get-Date -Format 'HH:mm:ss'), $accion, $ms) -ForegroundColor Green
            Write-Log "PULSO OK - [$accion] - Latencia: $($ms.ToString('N3'))ms - Lectura actual: $(($bytesTransferidosUltimoSegundo / 1MB).ToString('N2'))MB/s"
        } 
        else {
            if($esTurboActual) { $stats.SaltadosTurbo++ } else { $stats.Saltados++ }
            $colorSalto = if ($motivoSalto -eq "LECTURA ACTIVA JUEGO") { "Green" } else { "Cyan" }
            Write-Host ("`n{0} - [SALTADO] - {1} ({2:N3}ms)" -f (Get-Date -Format 'HH:mm:ss'), $motivoSalto, $ms) -ForegroundColor $colorSalto
            Write-Log "SALTADO - Motivo: $motivoSalto - Latencia: $($ms.ToString('N3'))ms - Lectura actual: $(($bytesTransferidosUltimoSegundo / 1MB).ToString('N2'))MB/s"
        }
    } 
    catch {
        Write-Host "`n$(Get-Date -Format 'HH:mm:ss') - [!] Unidad ocupada (Lectura de datos)." -ForegroundColor Yellow
    }

    # PANEL DE ESTADÍSTICAS CORREGIDO
    $colorPanel = if($modoBajaLatenciaActivo){ "Magenta" } else { "White" }
    $textoBytes = if ($bytesTransferidosUltimoSegundo -gt 0) { "{0:N2} MB/s" -f ($bytesTransferidosUltimoSegundo / 1MB) } else { "0.00 MB/s" }
    Write-Host "`n[ SESIÓN GLOBAL: $($inicioGlobal.Elapsed.ToString('hh\:mm\:ss')) | OK: $($stats.Exitosos) | SALTOS: $($stats.Saltados) | TRÁFICO: $textoBytes ]" -ForegroundColor $colorPanel
    
    if ($relojEmulador.ElapsedMilliseconds -gt 0) {
        $colorSesion = if ($emuladorActivo) { "Green" } else { "Gray" }
        $estadoJuego = if ($emuladorActivo) { "EJECUTANDO" } else { "EN PAUSA/CERRADO" }
        Write-Host "[ SESIÓN JUEGO ($estadoJuego): $($relojEmulador.Elapsed.ToString('hh\:mm\:ss')) ]" -ForegroundColor $colorSesion
        if($modoTurbo) {
            Write-Host "[ MODO TURBO ACTIVO | OK: $($stats.ExitososTurbo) | SALTOS: $($stats.SaltadosTurbo) ]" -ForegroundColor Red
        }
    }

    # Gestión de tiempos de espera (Optimizado con Ventana de Anticipación Predictiva)
    $segundosEspera = if ($emuladorActivo) { if ($modoTurbo) { 5 } else { 22 } } else { 23 }
    $i = $segundosEspera
    
    # Reiniciamos las variables acumuladoras para el nuevo ciclo
    $bytesTransferidosUltimoSegundo = 0
    $traficoAcumuladoVentana = 0

    while ($i -gt 0) {
        
        # COMPROBACIÓN DE TECLAS AL VUELO (' o +) - INTACTO
        if ([System.Console]::KeyAvailable) {
            $tecla = [System.Console]::ReadKey($true)
            if ($tecla.KeyChar -eq '´' -or $tecla.KeyChar -eq '+') {
                $modoTurbo = -not $modoTurbo
                [System.Console]::Beep(800, 100) 
                if ($emuladorActivo) {
                    if ($modoTurbo -and $i -gt 5) { $i = 5 }
                    elseif (-not $modoTurbo) { $i = 22 }
                }
            }
            if ($tecla.KeyChar -eq '-') { $global:pausado = -not $global:pausado; [System.Console]::Beep(600, 150) }
            if ($tecla.KeyChar -eq '*') { 
                "`nHERRAMIENTA CERRADA CORRECTAMENTE: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $logFile -Append -Encoding utf8
                [System.Console]::Beep(400, 200); Exit 
            }
        }

        # --- CAPTURA UNIVERSAL SEGUNDO A SEGUNDO ---
        $currentBytes = [int64](Get-CimInstance -ClassName Win32_Process | 
                        Where-Object { $_.Name -match "pcsx2|pcsx2-qt|ePSXe|rpcs3|RPCS3|PPSSPPWindows64|PPSSPPWindows|System|explorer" } | 
                        Measure-Object -Property ReadTransferCount -Sum).Sum

        if ($lastBytes -gt 0) {
            $diff = $currentBytes - $lastBytes
            $bytesTransferidosUltimoSegundo = if ($diff -gt 0) { $diff } else { 0 }
        } else {
            $bytesTransferidosUltimoSegundo = 0
        }
        $lastBytes = $currentBytes

        # --- LÓGICA DE VENTANA PREDICTIVA ADAPTATIVA ---
        # Si está en MODO TURBO, sumamos el tráfico de los últimos 2 segundos (cubre la ventana de 1.5s de forma segura)
        if ($modoTurbo -and $emuladorActivo) {
            if ($i -le 2) {
                $traficoAcumuladoVentana += $bytesTransferidosUltimoSegundo
            }
        }
        # Si está en MODO NORMAL, sumamos el tráfico de los últimos 2 segundos completos
        else {
            if ($i -le 2) {
                $traficoAcumuladoVentana += $bytesTransferidosUltimoSegundo
            }
        }

        $esTurboActual = ($modoTurbo -and $emuladorActivo)
        $statusExtra = if($modoBajaLatenciaActivo){ " (LOW-LAT)" } else { "" }
        $textoEstado = if($esTurboActual){ "TURBO" } else { "ESPERA$statusExtra" }
        
        # Mostramos la tasa instantánea con la guía completa de todos los controles
        $msg = "`r[{0}] Espe: {1}s | Controles: [´/+]Turbo [-]Pausa [*]Salir | Tasa: {2:N2} MB/s    " -f $textoEstado, $i, ($bytesTransferidosUltimoSegundo / 1MB)
        Write-Host -NoNewline $msg
        
        Start-Sleep -Seconds 1
        $i--
    }
    
    # Al salir del bucle, transferimos el acumulado de la ventana de seguridad para la toma de decisiones
    if ($traficoAcumuladoVentana -gt 0) {
        $bytesTransferidosUltimoSegundo = $traficoAcumuladoVentana
    }
    Write-Host "" 
}
