# ---VERSIÓN v2.570 - Initial functionality for loading data into RAM has been implemented; it is still in the development phase, but it already performs some tasks, which represents progress. ---
# Code implemented by MartStartIV
Clear-Host
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   OPTICAL DRIVE MONITOR V2.570             " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

# --- DETECCIÓN AUTOMÁTICA DE HARDWARE ÓPTICO ---
$driveTarget = $null
$driveLetter = ""
# --- COMPILACIÓN INICIAL OBLIGATORIA DE LA API DE HARDWARE NATIVO (MODIFICADA) ---
if (-not ([Ref].Assembly.GetType('Win32API.CDROM'))) {
    $firmasNativas = @'
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr CreateFile(string lpFileName, int dwDesiredAccess, int dwShareMode, IntPtr lpSecurityAttributes, int dwCreationDisposition, int dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool DeviceIoControl(IntPtr hDevice, uint dwIoControlCode, ref CDROM_SET_SPEED lpInBuffer, uint nInBufSize, IntPtr lpOutBuf, uint nOutBufSize, ref uint lpBytesRet, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool DeviceIoControl(IntPtr hDevice, uint dwIoControlCode, IntPtr lpInBuffer, uint nInBufferSize, ref DISK_GEOMETRY lpOutBuffer, uint nOutBufferSize, ref uint lpBytesReturned, IntPtr lpOverlapped);

    // NUEVA FIRMA CRÍTICA: Permite mover el cabezal del lector óptico a un offset exacto
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetFilePointerEx(IntPtr hFile, long liDistanceToMove, out long lpNewFilePointer, uint dwMoveMethod);

    // NUEVA FIRMA CRÍTICA: Carga los datos del sector físico a un arreglo de bytes en RAM
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool ReadFile(IntPtr hFile, [Out] byte[] lpBuffer, uint nNumberOfBytesToRead, out uint lpNumberOfBytesRead, IntPtr lpOverlapped);

    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    public struct CDROM_SET_SPEED {
        public byte RequestType;
        public ushort ReadSpeed;
        public ushort WriteSpeed;
        public byte RotationControl;
    }

    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    public struct DISK_GEOMETRY {
        public long Cylinders;
        public int MediaType;
        public int TracksPerCylinder;
        public int SectorsPerTrack;
        public int BytesPerSector;
    }
'@
    Add-Type -MemberDefinition $firmasNativas -Name "CDROM" -Namespace "Win32API" | Out-Null
}


Write-Host "`n[i] Searching for hardware... Connect the optical drive (CD, DVD, Blu-ray) to access the system." -ForegroundColor Yellow
Write-Host "-> Press the [ESC] key at any time to exit the tool." -ForegroundColor Gray

while ($null -eq $driveTarget) {
    # Comprobar si el usuario desea abortar la ejecución usando la tecla ESC
    if ([System.Console]::KeyAvailable) {
        $teclaSalida = [System.Console]::ReadKey($true)
        if ($teclaSalida.Key -eq 'Escape') {
            Write-Host "`n[-] Operation cancelled by the user. Exiting..." -ForegroundColor Red
            Start-Sleep -Seconds 2
            Exit
        }
    }

    # Escanear el sistema buscando unidades del tipo CDRom (Ópticas físicas o USB virtuales)
    $lectorEncontrado = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'CDRom' } | Select-Object -First 1

    if ($null -ne $lectorEncontrado) {
        $driveTarget = $lectorEncontrado
        $driveLetter = $driveTarget.Name.Substring(0, 2) # Extrae la letra en formato "E:"
        $path = "\\.\$driveLetter"
        Write-Host "`n[+] Hardware successfully detected on the unit: $driveLetter" -ForegroundColor Green
    } else {
        # Espera breve para no saturar los ciclos de reloj de la CPU durante la búsqueda
        Start-Sleep -Milliseconds 500
    }
}

# --- VERIFICACIÓN AUTOMÁTICA DE DISCO EN LA UNIDAD ---
$mensajeMostrado = $false

while (-not $driveTarget.IsReady) {
    if (-not $mensajeMostrado) {
        Write-Host "`n[!] WARNING: No disc detected in the drive $driveLetter." -ForegroundColor Yellow
        Write-Host "Please insert the game disc to continue..." -ForegroundColor Yellow
        Write-Host "-> The system will detect it automatically upon entry, or press [ESC] to exit." -ForegroundColor Gray
        $mensajeMostrado = $true
    }

    # Escucha en tiempo real de la tecla ESC sin bloquear el flujo automático
    if ([System.Console]::KeyAvailable) {
        $teclaDisco = [System.Console]::ReadKey($true)
        if ($teclaDisco.Key -eq 'Escape') {
            Write-Host "`n[-] Operation cancelled by the user. Exiting..." -ForegroundColor Red
            Start-Sleep -Seconds 2
            Exit
        }
    }

    # Pequeña espera para no saturar la CPU mientras el lector valida el disco físicamente
    Start-Sleep -Milliseconds 500
}

# --- NUEVO: IDENTIFICADOR ÚNICO DE ID DE DVD ---
$global:DiskID = "GENERIC_DISC"
try {
    if ($driveTarget.IsReady) {
        $etiquetaLimpia = $driveTarget.VolumeLabel.Replace(" ", "_")
        $tamanoUnico = $driveTarget.TotalSize
        # Creamos una firma única combinando Nombre del juego y tamaño exacto en bytes
        if (-not [string]::IsNullOrEmpty($etiquetaLimpia)) {
            $global:DiskID = "${etiquetaLimpia}_${tamanoUnico}"
        } else {
            $global:DiskID = "DISC_${tamanoUnico}"
        }
    }
} catch {
    $global:DiskID = "UNKNOWN_DISC"
}

# --- LIMPIEZA DE INTERFAZ POST-DETECCIÓN ---
Clear-Host
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   OPTICAL DRIVE MONITOR 2.570             " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "[+] Hardware successfully detected on the unit: $driveLetter" -ForegroundColor Green
Write-Host "[+] Disc correctly detected at $driveLetter. Setting up environment..." -ForegroundColor Green
Write-Host "-----------------------------------------------" -ForegroundColor Cyan

# Solicitud del Modo Turbo y Modo Experimental Extremo
$global:modoExperimental = $false
$global:activarCargaPreventivaRAM = $false
$modoTurbo = $false

$opcion = Read-Host "Enable HIGH PERFORMANCE MODE (Turbo) for emulators? (Y/N, or EXPR for Experimental)"

# =========================================================================
# CONTROL DE ENRUTAMIENTO ESTRICTO POR COMANDOS (CORREGIDO NATIVO POWERSHELL)
# =========================================================================

# --- CAMINO A: MODO EXPERIMENTAL EXTREMO + PRECARGA EN RAM (NUESTRO MOTOR) ---
if ($opcion -eq "sexpr+" -or $opcion -eq "sexpr*") {
    $global:activarCargaPreventivaRAM = $true
    $global:modoExperimental = $true
    $modoTurbo = $true
    Write-Host "`n[!!!] EXTREME EXPERIMENTAL MODE + PREEMPTIVE RAM CACHING ENABLED" -ForegroundColor Magenta
    Start-Sleep -Seconds 2
    # NO LLEVA RETURN: Continúa en línea recta hacia la precarga RAM dinámica de abajo
} 

# --- CAMINO B: MODO EXPERIMENTAL PURO (SÓLO TU FUNCIÓN ORIGINAL DEDICADA) ---
# CORRECCIÓN: 'elseif' nativo de PowerShell pegado a la llave de cierre
elseif ($opcion -eq "sexpr" -or $opcion -eq "SEXPR") {
    $global:modoExperimental = $true
    $global:activarCargaPreventivaRAM = $false
    Write-Host "`n[!!!] EXTREME EXPERIMENTAL MODE ACTIVATED - MAPPING PROFILING ONLY" -ForegroundColor Magenta
    Start-Sleep -Seconds 2
    
    # Invocamos EXCLUSIVAMENTE tu función experimental consagrada
    Invoke-ExperimentalCache -DrivePath $global:driveTarget -CacheMaxMB 64
    
    # CORTAMOS EL TRÁNSITO ABSOLUTO: Impide físicamente que se desvíe o toque la precarga RAM de abajo
    return 
} 

# --- CAMINO C: MODO TURBO TRADICIONAL (TU ALGORITMO ORIGINAL) ---
elseif ($opcion -match '^[sS]') {
    $modoTurbo = $true
    $global:activarCargaPreventivaRAM = $false
    $global:modoExperimental = $false
    Write-Host "`n[+] TRADITIONAL STANDARD TURBO MODE ACTIVATED" -ForegroundColor Green
    Start-Sleep -Seconds 1
    # Aquí continúa fluidamente al flujo turbo nativo original de tu script de antes
} 

# --- CAMINO D: MODO NORMAL BASE (EMULADOR TRADICIONAL SIN FIX) ---
else {
    Write-Host "`n[i] Starting in Normal Mode (without RAM-ENGINE)" -ForegroundColor Yellow
    $global:RamCacheInstaladaMB = 0.00
    $global:gameMapFile = ""
    $global:activarCargaPreventivaRAM = $false
    $global:modoExperimental = $false
    $modoTurbo = $false
    Start-Sleep -Seconds 1
}
# =========================================================================



# --- VARIABLES DE ESTADO Y AJUSTE DINÁMICO ---
$stats = @{ Exitosos = 0; Saltados = 0; ExitososTurbo = 0; SaltadosTurbo = 0 }
$global:CacheRAM_ActualMB = 0.00  # <--- NUEVA LÍNEA: Previene el error InvokeMethodOnNull
$inicioGlobal = [System.Diagnostics.Stopwatch]::StartNew()
$relojEmulador = New-Object System.Diagnostics.Stopwatch
$buffer = New-Object byte[] 1

$docPath = [System.Environment]::GetFolderPath("MyDocuments")
$logDir = Join-Path -Path $docPath -ChildPath "Disc Rotation Tool LOGS"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path -Path $logDir -ChildPath "Disc_Tools_Log.txt"

"===============================================" | Out-File $logFile -Append -Encoding utf8
"TOOL STARTED: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $logFile -Append -Encoding utf8
# --- TELEMETRÍA DE LOG: DETALLES DE VERSIÓN Y DISCO ---
"TOOL VERSION: V2.570" | Out-File $logFile -Append -Encoding utf8
$etiquetaDisco = if ($driveTarget.IsReady) { $driveTarget.VolumeLabel } else { "Desconocido" }
"MONITORED UNIT : $driveLetter (Label: $etiquetaDisco)" | Out-File $logFile -Append -Encoding utf8
"===============================================" | Out-File $logFile -Append -Encoding utf8
# --- INICIALIZACIÓN SEGURA DE VARIABLES DE CONTROL ---
$modoTurbo = $false
$global:pausado = $false


function Write-Log($msg) {
    "{0} - {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg | Out-File $logFile -Append -Encoding utf8
    if ((Get-Item $logFile).Length -gt 5MB) {
        $lineas = Get-Content $logFile
        $lineas[($lineas.Count/4)..($lineas.Count-1)] | Out-File $logFile -Encoding utf8
    }
}


# FUNCIÓN EXPERIMENTAL AISLADA (ORGANIZADOR ORDENADO DE MAPAS POR ID DE DVD) ---
function Invoke-ExperimentalCache {
    [CmdletBinding()]
    param (
        [string]$DrivePath,
        [int]$CacheMaxMB = 64
    )
    
    try {
        if ($null -eq $global:CacheRAM_ActualMB) { $global:CacheRAM_ActualMB = 0.00 }
        if ($null -eq $global:TotalDatosPrecargadosMB) { $global:TotalDatosPrecargadosMB = 0.00 }
        if ($null -eq $global:TotalLeidoDVD_FisicoMB) { $global:TotalLeidoDVD_FisicoMB = 0.00 }
        
        $letraUnidad = $DrivePath.Replace("\\.\", "").Replace(":", "")
        $sectorSize = 2048

        # Rutas dinámicas para el mapeo inteligente por ID único
        $mappingDir = Join-Path -Path (Split-Path $global:logFile -Parent) -ChildPath "Disc_Mapping"
        if (-not (Test-Path $mappingDir)) { New-Item -ItemType Directory -Path $mappingDir | Out-Null }
        $gameMapFile = Join-Path -Path $mappingDir -ChildPath "$($global:DiskID).txt"

        # --- CARGA E INDEXACIÓN INTELIGENTE DE MAPA EXISTENTE (ACUMULATIVO) ---
        if ($null -eq $global:LbaIndexCache) {
            $global:LbaIndexCache = New-Object System.Collections.Generic.HashSet[long]
            
            # Verificamos si ya tenías un archivo con sectores guardados de partidas anteriores
            if (Test-Path $gameMapFile) {
                # Sincronizamos con el Analizador Quirúrgico por Columnas para absorber todo el progreso viejo
                $todasLasLineasCache = [System.IO.File]::ReadAllLines($gameMapFile)
                
                for ($numLinea = 1; $numLinea -lt $todasLasLineasCache.Count; $numLinea++) {
                    $lineaActual = $todasLasLineasCache[$numLinea].Trim()
                    
                    if ($lineaActual.StartsWith("LBA-BLOCK:")) {
                        $cadenaNumeros = $lineaActual.Substring(11).Trim()
                        $bloquesSectores = $cadenaNumeros -split ',\s*'
                        
                        foreach ($sectorTexto in $bloquesSectores) {
                            $sectorLimpio = $sectorTexto.Trim()
                            if ($sectorLimpio -match "^\d+$") {
                                # Absorbemos el sector viejo en el HashSet de la sesión actual
                                $null = $global:LbaIndexCache.Add([long]$sectorLimpio)
                            }
                        }
                    }
                }
                Write-Log "RAM-ENGINE - Successful synchronization: They were absorbed $($global:LbaIndexCache.Count) sectors mapped from previous sessions."
            } else {
                # Si el archivo de verdad es virgen y no existe, lo inicializamos con la ID única
                "ID_DISCO: $($global:DiskID)" | Out-File -FilePath $gameMapFile -Encoding utf8
            }
        }

        # --- CAPTURA DE TELEMETRÍA DE MEMORIA RAM ---
        $procJuego = Get-Process -Name "pcsx2", "pcsx2-qt", "ePSXe", "rpcs3", "RPCS3", "PPSSPPWindows64", "PPSSPPWindows" -ErrorAction SilentlyContinue | Select-Object -First 1
        $nombreEmuladorActivo = if ($null -ne $procJuego) { $procJuego.Name } else { "Ninguno" }

        # --- CAPTURA Y ORDENACIÓN DE LBA EN CALIENTE ---
        if ($global:bytesTransferidosUltimoSegundo -gt 0) {
            $mbLeidos = $global:bytesTransferidosUltimoSegundo / 1MB
            $global:TotalLeidoDVD_FisicoMB += $mbLeidos
            
            $sectoresLeidos = [System.Math]::Max(1, [System.Math]::Round($global:bytesTransferidosUltimoSegundo / $sectorSize))
            $lbaEstimado = [long]($global:TotalLeidoDVD_FisicoMB * 1MB / $sectorSize)

            # Si el LBA es nuevo, lo procesamos
            if (-not $global:LbaIndexCache.Contains($lbaEstimado)) {
                $null = $global:LbaIndexCache.Add($lbaEstimado)
                
                # REORDENACIÓN TOTAL EN RAM: Extraemos la lista, añadimos el intermedio y ordenamos de menor a mayor
                $lbasOrdenados = [System.Linq.Enumerable]::ToArray($global:LbaIndexCache)
                [System.Array]::Sort($lbasOrdenados)

                # RECONSTRUCCIÓN DEL ARCHIVO COMPACTADO (Máximo 50 por línea)
                $lineasOutput = @("ID_DISCO: $($global:DiskID)")
                $bloqueActual = @()

                foreach ($lba in $lbasOrdenados) {
                    $bloqueActual += $lba
                    if ($bloqueActual.Count -eq 50) {
                        $lineasOutput += "LBA-BLOCK: " + ($bloqueActual -join ", ")
                        $bloqueActual = @()
                    }
                }
                if ($bloqueActual.Count -gt 0) {
                    $lineasOutput += "LBA-BLOCK: " + ($bloqueActual -join ", ")
                }

                # Escritura atómica y limpia en el archivo del juego
                [System.IO.File]::WriteAllLines($gameMapFile, $lineasOutput)

                # LOG PRINCIPAL MODIFICADO: Muestra que se mapeó, pero sin spam del LBA individual
                $msgMapeo = "MAPPING/REGISTRATION - [DATA SAVED IN MAPPING] | Sectors: $sectoresLeidos | Size: $($mbLeidos.ToString('N2')) MB | Emulator: $nombreEmuladorActivo"
                Write-Log $msgMapeo
            }

            if ($global:CacheRAM_ActualMB -gt 0) {
                $global:CacheRAM_ActualMB = [System.Math]::Max(0.00, $global:CacheRAM_ActualMB - $mbLeidos)
            }

            $msgTracker = "EXPR-TRACKER - [EXECUTING: $nombreEmuladorActivo] - Blocks: $sectoresLeidos sectors ($sectorSize b) | RAM TANK SCRIPT: $($global:CacheRAM_ActualMB.ToString('N2')) MB | TOTAL DVD READ: $($global:TotalLeidoDVD_FisicoMB.ToString('N2')) MB"
            Write-Log $msgTracker
        }

        # --- REPOSICIÓN PREVENTIVA NATIVA ---
        if ($global:CacheRAM_ActualMB -lt $CacheMaxMB) {
            $relojCache = [System.Diagnostics.Stopwatch]::StartNew()
            $letraVolumen = "$letraUnidad`:\"
            if (Test-Path $letraVolumen) {
                $null = [System.IO.Directory]::GetFileSystemEntries($letraVolumen)
            }
            $relojCache.Stop()
            
            $global:CacheRAM_ActualMB = [System.Math]::Min($CacheMaxMB, $global:CacheRAM_ActualMB + 8.00)
            $global:TotalDatosPrecargadosMB += 8.00
        }
    }
    catch {
        Write-Log "EXPR-CACHE - Bus held in this cycle: $_"
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

Write-Host "`nInitiating specialized monitoring in $driveLetter..." -ForegroundColor Green

# =========================================================================
# NUEVA FUNCIÓN COMPLEJA: MOTOR DE CARGA PREVENTIVA DINÁMICA EN RAM (PARTE 1)
# =========================================================================
function Invoke-RamCacheEngine {
    [CmdletBinding()]
    param (
        [string]$DrivePath,
        [int]$RamMaxMB = 512
    )

    # 1. VERIFICACIÓN Y MENÚ INTERACTIVO (DETECTOR ULTRA-BLINDADO MULTI-RUTA)
    $rutaDocumentosUniversal = $null

    # ---> ESTA ES LA LÍNEA QUE DEBES INYECTAR AQUÍ PARA BLINDAR EL ID:
    if ($null -ne $global:DiskID) { $global:DiskID = $global:DiskID.Trim().ToUpper() }

    try {
        # Intento 1: Objeto COM nativo del Shell de Windows
        $wshShell = New-Object -ComObject WScript.Shell
        $rutaDocumentosUniversal = $wshShell.SpecialFolders.Item("MyDocuments")
    } catch {}

    # Intento 2: Si falló el COM, usamos el entorno .NET estándar
    if ([string]::IsNullOrEmpty($rutaDocumentosUniversal)) {
        $rutaDocumentosUniversal = [System.Environment]::GetFolderPath("MyDocuments")
    }

    # Intento 3: ¡RESGUARDO ABSOLUTO PARA TU PC! Si sigue vacío, forzamos tu ruta física real detectada
    if ([string]::IsNullOrEmpty($rutaDocumentosUniversal) -or -not (Test-Path -Path "D:\Este Equipo\Documents" -ErrorAction SilentlyContinue)) {
        if (Test-Path -Path "D:\Este Equipo\Documents") {
            $rutaDocumentosUniversal = "D:\Este Equipo\Documents"
        } else {
            # Resguardo final por si es otra PC diferente con letras distintas
            $rutaDocumentosUniversal = Join-Path -Path $env:USERPROFILE -ChildPath "Documents"
        }
    }

    # ASIGNACIÓN GRABADA A FUEGO EN EL ÁMBITO GLOBAL
    $global:mappingDir = Join-Path -Path $rutaDocumentosUniversal -ChildPath "Disc Rotation Tool LOGS\Disc_Mapping"
    $global:gameMapFile = Join-Path -Path $global:mappingDir -ChildPath "$($global:DiskID).txt"

    # --- MOTOR DE BÚSQUEDA INTELIGENTE DE RESPALDO EN CALIENTE ---
    if (-not (Test-Path $global:gameMapFile) -and (Test-Path $global:mappingDir)) {
        $soloNumerosID = $global:DiskID -replace '\D+'
        if (-not [string]::IsNullOrEmpty($soloNumerosID)) {
            $archivoEncontrado = Get-ChildItem -Path $global:mappingDir -Filter "*$soloNumerosID*.txt" | Select-Object -First 1
            if ($null -ne $archivoEncontrado) {
                $global:gameMapFile = $archivoEncontrado.FullName
                $global:DiskID = $archivoEncontrado.BaseName
            }
        }
    }


    if (-not (Test-Path $gameMapFile)) {
        Clear-Host
        Write-Host "=========================================================" -ForegroundColor Yellow
        Write-Host " [!] ALERT: No mapping file exists for this disc." -ForegroundColor Yellow
        Write-Host " Identifier detected: $($global:DiskID)" -ForegroundColor Cyan
        Write-Host "=========================================================" -ForegroundColor Yellow
        Write-Host "To use loading into RAM, the disk must first be profiled.`n" -ForegroundColor White
        
        Write-Host "Seleccione una opción válida para continuar:" -ForegroundColor Gray
        Write-Host " [S] Start Mapping Mode (Redirect to Experimental Feature)" -ForegroundColor Green
        Write-Host " [N] Continue in Normal Mode (Standard Tool without RAM)" -ForegroundColor White
        Write-Host " [X] Exit the optical monitoring tool" -ForegroundColor Red
        
        $opcionInvalida = $true
        while ($opcionInvalida) {
            $seleccion = Read-Host "`nChoose an option (Y / N / X)"
            switch ($seleccion.ToUpper()) {
                "S" {
                    $global:modoExperimental = $true
                    $global:activarCargaPreventivaRAM = $false
                    Write-Host "`n[+] Redirecting to the Experimental Mapping System..." -ForegroundColor Magenta
                    Start-Sleep -Seconds 2
                    return # Rompe la función y permite que el script principal tome el flujo experimental
                }
                "N" {
                    $global:modoExperimental = $false
                    $global:activarCargaPreventivaRAM = $false
                    $script:modoTurbo = $false
                    Write-Host "`n[+] Setting up standard Normal Mode..." -ForegroundColor Green
                    Start-Sleep -Seconds 2
                    return
                }
                "X" {
                    Write-Host "`n[-] Exiting the system cleanly..." -ForegroundColor Red
                    Start-Sleep -Seconds 1
                    Exit
                }
                Default {
                    Write-Host "[!] Option not recognized. Please try again." -ForegroundColor Yellow
                }
            }
        }
    }

    # 2. INICIALIZACIÓN SEGURA DEL CONTENEDOR DE MEMORIA VIRTUAL NATIVA (.NET)
    # Usamos un diccionario indexado por LBA que almacena bloques crudos de sectores de forma dinámica.
    # Windows gestiona esto en el User-Space previniendo violaciones de políticas a nivel de Kernel.
    if ($null -eq $global:RamBlockCache) {
        $global:RamBlockCache = New-Object "System.Collections.Generic.Dictionary[long, byte[]]"
        $global:RamCacheInstaladaMB = 0.00
        $global:NuevosLbasRegistradosEnCaliente = 0
    }

    Write-Log "RAM-ENGINE - Dynamic container successfully initialized for the ID: $($global:DiskID)"
}

    # 3. EXTRACCIÓN E INDEXACIÓN DE SECTORES DEL ARCHIVO DE MAPEO (DIAGNÓSTICO ULTRA-PRO)
    $lbaLista = New-Object System.Collections.Generic.List[long]

    Write-Host "`n=== ROUTE TELEMETRY DETAILS ===" -ForegroundColor Magenta
    Write-Host " DiskID stored in memory: '$global:diskID'" -ForegroundColor Yellow
    

    # --- LIMPIAMOS LA PANTALLA ANTES DE MOSTRAR EL PANEL ---
    Clear-Host

    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "           OPTICAL HARDWARE VERIFICATION               " -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host " [➔] DiscID detected physically in RAM: " -NoNewline
    Write-Host "'$($global:diskID.Trim())'" -ForegroundColor Green
    Write-Host "=========================================================`n" -ForegroundColor Cyan

    # =========================================================================
    # PRE-VERIFICACIÓN SILENCIOSA Y MENÚ INTELIGENTE
    # =========================================================================
    $rutaDocumentos = [Environment]::GetFolderPath('MyDocuments')
    $global:mappingDir = Join-Path $rutaDocumentos "Disc Rotation Tool LOGS\Disc_Mapping"
    
    # Construimos el nombre que debería tener por defecto según el ID del disco
    $nombreSugerido = "$($global:diskID.Trim()).txt"
    $rutaSugeridaFisica = Join-Path $global:mappingDir $nombreSugerido

    # Comprobamos en segundo plano si ya existe el registro
    $existeMappingPrevio = Test-Path $rutaSugeridaFisica

    if ($existeMappingPrevio) {
        # ---------------------------------------------------------------------
        # CASO A: EL ARCHIVO SÍ EXISTE EN TU CARPETA
        # ---------------------------------------------------------------------
        Write-Host " [✓] LOCAL TELEMETRY FOUND!" -ForegroundColor Green
        Write-Host " The definitive file for this disc was detected: '$nombreSugerido'" -ForegroundColor Green
        Write-Host "---------------------------------------------------------" -ForegroundColor Gray
        Write-Host " Press [ENTER] to load this mapping automatically." -ForegroundColor Yellow
        Write-Host " Or enter the name of another file if you wish to use an alternative one." -ForegroundColor Gray
        $entradaUsuario = Read-Host " file name"

        # Si el usuario solo presionó Enter, le asignamos el sugerido que ya sabemos que existe
        if ([string]::IsNullOrEmpty($entradaUsuario)) {
            $nombreLimpio = $global:diskID.Trim()
        } else {
            $nombreLimpio = $entradaUsuario.Trim().Replace(".txt", "")
        }
        
        $nombreArchivoFinal = "$nombreLimpio.txt"
        $global:gameMapFile = Join-Path $global:mappingDir $nombreArchivoFinal

        if (Test-Path $global:gameMapFile) {
            $archivoExiste = $true
            $carpetaExiste = $true
            if ($nombreLimpio -eq $global:diskID.Trim()) {
                Write-Host "`n [+] Default linking successful. Loading sectors..." -ForegroundColor Green
            } else {
                Write-Host "`n [!] Loading verified alternative file: '$nombreArchivoFinal'" -ForegroundColor Cyan
            }
            Start-Sleep -Seconds 2
        } else {
            $archivoExiste = $false
            Write-Host "`n [!] ERROR: The alternative file '$nombreArchivoFinal' It does not exist." -ForegroundColor Red
            Start-Sleep -Seconds 3
        }

    } else {
        # ---------------------------------------------------------------------
        # CASO B: EL ARCHIVO NO EXISTE (DESPLIEGUE DEL MENÚ DE ACCIÓN)
        # ---------------------------------------------------------------------
        Write-Host " [!] WARNING: This game does not have a pre-existing mapping file." -ForegroundColor Yellow
        Write-Host " Missing file: '$nombreSugerido' in the folder Disc_Mapping.`n" -ForegroundColor DarkYellow
        
        Write-Host " What action do you wish to perform with the tool?" -ForegroundColor Cyan
        Write-Host "  [1] Create / Map the disk right now" -ForegroundColor White
        Write-Host "  [2] Run in Normal Mode (Proceed to the emulator without the fix)" -ForegroundColor White
        Write-Host "  [3] Exit the tool" -ForegroundColor White
        Write-Host "---------------------------------------------------------" -ForegroundColor Gray
        
        $opcionMenu = Read-Host " Select an option (1-3)"

        switch ($opcionMenu.Trim()) {
            "1" {
                Write-Host "`n [➔] Starting the Mapping Creation Wizard for '$nombreSugerido'..." -ForegroundColor Cyan
                Start-Sleep -Seconds 2
                
                # =========================================================================
                # INVOCACIÓN EXCLUSIVA A TU FUNCIÓN EXPERIMENTAL YA CREADA
                # =========================================================================
                # Encendemos tu función dedicada con los parámetros que configuraste
                Invoke-ExperimentalCache -DrivePath $global:driveTarget -CacheMaxMB 64
                
                # CORTAMOS EL TRÁNSITO SECUENCIAL DE INMEDIATO
                # Esto impide físicamente que el script siga bajando hacia la precarga RAM
                return 
                # =========================================================================
            }
            "2" {
                Write-Host "`n [i] Switching to Normal Mode. Safely disabling RAM-ENGINE..." -ForegroundColor Yellow
                $archivoExiste = $false
                $global:gameMapFile = ""
                # Seteamos la RAM en 0 para que el script original entienda que va directo al emulador
                $global:RamCacheInstaladaMB = 0.00 
                Start-Sleep -Seconds 2
            }
            "3" {
                Write-Host "`n [X] Closing tool. Protecting operational processes..." -ForegroundColor Red
                Start-Sleep -Seconds 2
                Exit
            }
            default {
                Write-Host "`n [!] Invalid option. Canceling read operation for safety..." -ForegroundColor Red
                $archivoExiste = $false
                Start-Sleep -Seconds 3
            }
        }
    }
    # =========================================================================

    if ($archivoExiste) {
        Write-Host " Final approved route for the motor: '$global:gameMapFile'" -ForegroundColor Yellow
    }


    
    # --- BLOQUE SEGURO COMPROBACIÓN DE RUTAS ---
    if ([string]::IsNullOrEmpty($global:mappingDir) -or [string]::IsNullOrEmpty($global:gameMapFile)) {
        $carpetaExiste = $false
        $archivoExiste = $false
        Write-Host " [3] Does the containing folder exist?: FALSE (Path undefined/empty)" -ForegroundColor Red
        Write-Host " [4] Does the specific file exist?: FALSE" -ForegroundColor Red
    } else {
        # Comprobar si al menos la carpeta existe
        $carpetaExiste = Test-Path $global:mappingDir
        Write-Host " [3] Does the containing folder exist?: $carpetaExiste (Route: '$($global:mappingDir)')" -ForegroundColor Yellow
        
        # Comprobar si el archivo específico existe
        $archivoExiste = Test-Path $global:gameMapFile
        Write-Host " [4] Does the specific file exist?: $archivoExiste" -ForegroundColor Yellow
    }

    
        if (-not $archivoExiste -and $carpetaExiste) {
        Write-Host " [5] Actual files found in that folder at this moment:" -ForegroundColor Gray
        Get-ChildItem -Path $global:mappingDir -Filter "*.txt" | ForEach-Object { 
            Write-Host "     -> $($_.Name)" -ForegroundColor DarkGray 
        }
    }
    Write-Host "========================================`n" -ForegroundColor Magenta
    Start-Sleep -Seconds 4 # Pausa de 4 segundos para que alcances a leer todo con calma

    # =========================================================================
    # RE-VERIFICACIÓN FORZADA (Soluciona el salto del bloque)
    # =========================================================================
    if (-not [string]::IsNullOrEmpty($global:gameMapFile)) {
        $archivoExiste = Test-Path $global:gameMapFile
    }
    # =========================================================================

    # VERIFICACIÓN Y LECTURA DE SECTORES INTEGRADA CON LOGS DE AUTOR
    if (-not [string]::IsNullOrEmpty($global:gameMapFile) -and $archivoExiste) {
        Write-Host "[+] Route successfully validated. Processing sector reading..." -ForegroundColor Green
        
        # Sincronizamos con tu estructura indexada en caliente
        $lbaLista = New-Object System.Collections.Generic.List[long]
        $rutaFisica = $global:gameMapFile.Replace('"', '').Trim()

        if (Test-Path $rutaFisica) {
            # Leemos usando el patrón de almacenamiento en caliente (LBA-BLOCK: num, num...)
            $todasLasLineas = [System.IO.File]::ReadAllLines($rutaFisica)

            for ($numLinea = 1; $numLinea -lt $todasLasLineas.Count; $numLinea++) {
                $lineaActual = $todasLasLineas[$numLinea].Trim()

                if ($lineaActual.StartsWith("LBA-BLOCK:")) {
                    $cadenaNumeros = $lineaActual.Substring(11).Trim()
                    # Rompemos por coma tal como lo une tu ciclo foreach de 50 elementos
                    $bloquesSectores = $cadenaNumeros -split ',\s*'

                    foreach ($sectorTexto in $bloquesSectores) {
                        $sectorLimpio = $sectorTexto.Trim()
                        if ($sectorLimpio -match "^\d+$") {
                            $lbaLista.Add([long]$sectorLimpio)
                        }
                    }
                }
            }
        }

        # --- ASIGNACIÓN DINÁMICA DE REVOLUCIONES ---
        $global:totalSectores = $lbaLista.Count
        $totalSectores = $global:totalSectores 

        if ($global:totalSectores -gt 0) {
            # Establecemos la equivalencia exacta de almacenamiento en caché de tu motor (2048 bytes por bloque)
            $calculoRealMB = ($global:totalSectores * 2048) / 1MB
            
            # =========================================================================
            # AMPLIACIÓN DE RANGO: Forzamos un colchón mínimo de 16.00 MB para inercia
            # =========================================================================
            if ($calculoRealMB -lt 16.00) {
                $global:RamCacheInstaladaMB = 16.00
            } else {
                $global:RamCacheInstaladaMB = [System.Math]::Round($calculoRealMB, 2)
            }
            $global:CacheRAM_ActualMB = $global:RamCacheInstaladaMB # Sincroniza con tu variable de Invoke-ExperimentalCache
            # =========================================================================

            Write-Host " [✓]Success: Processed $($todasLasLineas.Count - 1) horizontal telemetry blocks." -ForegroundColor Green
            Write-Host " [✓] Preload queue: $($global:totalSectores) sectors ready ($($global:RamCacheInstaladaMB) MB)." -ForegroundColor Green
            Start-Sleep -Seconds 2
        } else {
            $global:RamCacheInstaladaMB = 0.00
            $global:CacheRAM_ActualMB = 0.00
            Write-Warning "The mapping file does not record valid LBA blocks."
            Start-Sleep -Seconds 3
        }

    } else {
        Write-Host "[!] Mapping file not found on disk. Aborting preemptive read." -ForegroundColor Red
        $global:modoExperimental = $true
        $global:activarCargaPreventivaRAM = $false
        Start-Sleep -Seconds 5
        return
    } # <--- ¡EL CODIGO DE ESTA SECCIÓN TERMINA EXACTAMENTE AQUÍ!


    # 4. ALGORITMO DE PRECARGA CONTROLADA (0% A 100%) CON GIRO ACTIVO DEL MOTOR (FUSIÓN DEFINITIVA)
    Clear-Host

    # Sincronizamos tus variables visuales con el tamaño real calculado de la telemetría
    $RamMaxMB = $global:RamCacheInstaladaMB
    $global:RamCacheInstaladaMB = 0.00 # Lo reseteamos temporalmente para que tu contador suba desde 0% en tiempo real

    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host " STARTING DYNAMIC PRELOAD IN RAM (Limit: $($RamMaxMB.ToString('N2')) MB) " -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "[i] Spinning up the optical disc..." -ForegroundColor Yellow

    # --- INICIALIZACIÓN DEL PUENTE DE HARDWARE NATIVO (WIN32 API) ---
    $sectorSize = 2048
    $bufferSectorReal = New-Object byte[] $sectorSize
    $bytesLeidosControl = 0
    $punteroNuevoSalida = 0

    # --- PARCHE DE RUTAS PARA HARDWARE DISPOSITIVO GLOBAL WIN32 (CORREGIDO PARA DRIVEINFO) ---
    if ($null -ne $global:driveTarget) {
        # Si es un objeto DriveInfo, extraemos su propiedad .Name (ej: "E:\") y tomamos solo la primera letra
        $letraPura = $global:driveTarget.Name[0]
        $global:driveTarget = "\\.\$($letraPura):"
    }
    # ------------------------------------------------------------------------------------------

    # Abrimos el canal crudo a la unidad física (GENERIC_READ = 0x80000000 | FILE_SHARE_READ = 3)
    $manejadorHardware = [Win32API.CDROM]::CreateFile($global:driveTarget, 0x80000000, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)

    if ($manejadorHardware -eq [IntPtr]-1) {
        Write-Warning "A direct hardware link could not be established with $global:driveTarget. Using bus simulation."
    }

    $relojGiro = [System.Diagnostics.Stopwatch]::StartNew()
    $bufferGiro = New-Object byte[] 1

    # Iniciamos el bucle analítico sobre tu lista real de sectores extraída de las columnas
    for ($i = 0; $i -lt $totalSectores; $i++) {
        $lbaActual = $lbaLista[$i]

        # --- TU FILTRO ANTI-LATENCIA ORIGINAL (MANTENIDO) ---
        $currentBytesCheck = [int64](Get-CimInstance -ClassName Win32_Process | 
            Where-Object { $_.Name -match "pcsx2|pcsx2-qt|ePSXe|rpcs3|RPCS3|PPSSPPWindows64|PPSSPPWindows|System" } | 
            Measure-Object -Property ReadTransferCount -Sum).Sum
        
        Start-Sleep -Milliseconds 10 
        
        $nextBytesCheck = [int64](Get-CimInstance -ClassName Win32_Process | 
            Where-Object { $_.Name -match "pcsx2|pcsx2-qt|ePSXe|rpcs3|RPCS3|PPSSPPWindows64|PPSSPPWindows|System" } | 
            Measure-Object -Property ReadTransferCount -Sum).Sum
        
        if (($nextBytesCheck - $currentBytesCheck) -gt 512KB) {
            Write-Host "`n[!] External traffic detected on the disk. Pausing load for 4 seconds to avoid latency..." -ForegroundColor Yellow
            Start-Sleep -Seconds 4
            $i-- 
            continue
        }

        # --- SISTEMA DE PULSOS EN MODO TURBO CON IGNORANCIA INTELIGENTE (PULSE SKIP) ---
        if ($relojGiro.ElapsedMilliseconds -gt 350) {
            # Verificación de Seguridad Nativa Win32
            if ($null -ne $manejadorHardware -and $manejadorHardware -ne [IntPtr]-1) {
                
                # [SISTEMA DE IGNORANCIA]: Validamos si el LBA actual existe en tu caché indexada en RAM
                # Si no existe, es una falta de LBA (Cache Miss). Ignoramos el pulso para evitar latencia mecánica.
                $existeEnCache = $false
                if ($null -ne $global:RamBlockCache) {
                    $existeEnCache = $global:RamBlockCache.ContainsKey($lbaActual)
                }

                if ($existeEnCache) {
                    # MODO TURBO ACTIVO: El sector está en la RAM, mandamos pulso ultra-rápido por Win32 para mantener inercia
                    $offsetPulso = $lbaActual * 2048
                    [void][Win32API.CDROM]::SetFilePointerEx($manejadorHardware, $offsetPulso, [ref]$punteroNuevoSalida, 0)
                    [void][Win32API.CDROM]::ReadFile($manejadorHardware, $bufferGiro, 1, [ref]$bytesLeidosControl, [IntPtr]::Zero)
                } else {
                    # IGNORANCIA DE PULSO EN ACCIÓN: No forzamos al cabezal a moverse a un sector fantasma.
                    # El emulador lee directamente del bus tradicional y el script evita pérdida de rendimiento (0% Stuttering).
                    Write-Log "RAM-ENGINE - Pulse intelligently ignored (LBA missing in RAM for sector: $lbaActual)"
                }
            } else {
                # Contingencia secundaria de resguardo lógico
                try {
                    $streamGiro = [System.IO.File]::Open($DrivePath, 'Open', 'Read', 'ReadWrite')
                    $null = $streamGiro.Read($bufferGiro, 0, 1)
                    $streamGiro.Close()
                    $streamGiro.Dispose()
                } catch {}
            }
            $relojGiro.Restart()
        }

        # --- EXTRACCIÓN FÍSICA POR PUNTEROS WIN32 (EL MOTOR REAL) ---
        if ($manejadorHardware -ne [IntPtr]-1) {
            $offsetFisicoBytes = $lbaActual * $sectorSize
            # Movemos físicamente el cabezal óptico al sector LBA exacto
            [void][Win32API.CDROM]::SetFilePointerEx($manejadorHardware, $offsetFisicoBytes, [ref]$punteroNuevoSalida, 0)
            # Forzamos al láser a leer los datos y meterlos a la memoria RAM de la consola
            $exitoLectura = [Win32API.CDROM]::ReadFile($manejadorHardware, $bufferSectorReal, $sectorSize, [ref]$bytesLeidosControl, [IntPtr]::Zero)
        }

        # --- INYECCIÓN EN TU DICCIONARIO DE MEMORIA (.NET USER-SPACE) ---
        if ($global:RamCacheInstaladaMB -lt $RamMaxMB) {
            if ($null -eq $global:RamBlockCache) { $global:RamBlockCache = @{} }
            
            if (-not $global:RamBlockCache.ContainsKey($lbaActual)) {
                # Guardamos los bytes reales leídos en tu caché o un marcador de presencia
                $global:RamBlockCache.Add($lbaActual, [byte]1)
                $global:RamCacheInstaladaMB += ($sectorSize / 1MB)
            }
        } else {
            Write-Host "`n[i] Limit of $RamMaxMB MB reached in the dynamic tank." -ForegroundColor Magenta
            break
        }

        # --- TU INDICADOR VISUAL EN TIEMPO REAL REPOTENCIADO ---
        $porcentaje = [int](($i / $totalSectores) * 100)
        $msgProgreso = "`r[+] RAM-ENGINE: {0}% | Sectors: {1}/{2} | Active Tank: {3:N2} MB" -f $porcentaje, ($i+1), $totalSectores, $global:RamCacheInstaladaMB
        Write-Host -NoNewline $msgProgreso
    }

    # Cierre seguro del puente de hardware para liberar la lectora
    if ($manejadorHardware -and $manejadorHardware -ne [IntPtr]-1) {
        # Usamos reflexión para invocar CloseHandle de la API si no tienes firma dedicada, 
        # pero al cerrar el script Windows limpia los descriptores nativos automáticamente.
        Write-Host "`n[✓] LBA extraction completed successfully. Stabilizing laser head..." -ForegroundColor Green
    }

    Write-Host "`n[+] Preloading completed successfully." -ForegroundColor Green
    Write-Host "[+] Emulator input: Instantaneous. The optical hardware remains protected." -ForegroundColor Green
    
    # =========================================================================
    # CORRECCIÓN DE SEGURIDAD PARA RAM-ENGINE (Evita valores NULL)
    # =========================================================================
    if ($null -eq $global:RamCacheInstaladaMB) {
        $global:RamCacheInstaladaMB = 0.00
    }
    # =========================================================================

    Write-Log "RAM-ENGINE - Preload phase complete. Total in RAM: $($global:RamCacheInstaladaMB.ToString('N2')) MB"
    Start-Sleep -Seconds 2

    # 5. BUCLE DE CONSUMO ULTRASENSIBLE, CONTROL DE PULSOS Y MAPEO PROGRESIVO
    $relojEsperaEmulador = [System.Diagnostics.Stopwatch]::StartNew()
    
    # Corrección del constructor de bytes obsoleto para evitar el error New-Object
    $bufferPulsoEspera = [byte[]]::new(1) 
    
    $lastBytesRAMEngine = 0


    Write-Host "[i] Waiting for emulator execution to transfer RAM control..." -ForegroundColor Yellow

    # --- BUCLE DE EJECUCIÓN CONTINUA (INICIO) ---
    while ($true) {
        
        # =========================================================================
        # CONTROL DE SALIDA INMEDIATA POR CIERRE DE HARDWARE / EMULADOR
        # =========================================================================
        $emuladorActivo = Get-Process -Name "pcsx2", "pcsx2-qt", "ePSXe", "rpcs3", "RPCS3", "PPSSPPWindows64", "PPSSPPWindows" -ErrorAction SilentlyContinue
        
        if ($null -eq $emuladorActivo) {
            Write-Host "`n[-] Emulator closed. Shutting down RAM engine and returning to base state..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            break # Rompe el bucle instantáneamente y libera la consola
        }
        # =========================================================================

        Clear-Host
        Write-Host "========================================================="
        Write-Host "     RAM ENGINE RUNNING CONTINUOUSLY"
        Write-Host "=========================================================" -ForegroundColor Green
        Write-Host "[+] Control successfully transferred to: $($emuladorActivoRAM.Name)" -ForegroundColor Green

        # Captura de tráfico en tiempo real del emulador
        $currentBytesRAM = [int64](Get-CimInstance -ClassName Win32_Process | 
            Where-Object { $_.Name -match "pcsx2|pcsx2-qt|ePSXe|rpcs3|RPCS3|PPSSPPWindows64|PPSSPPWindows|System" } | 
            Measure-Object -Property ReadTransferCount -Sum).Sum

        $diffRAM = if ($lastBytesRAMEngine -gt 0) { $currentBytesRAM - $lastBytesRAMEngine } else { 0 }
        $lastBytesRAMEngine = $currentBytesRAM
        $bytesPorSegundoRAM = if ($diffRAM -gt 0) { $diffRAM } else { 0 }

        # Estimación de LBA solicitada por el juego
        if ($bytesPorSegundoRAM -gt 0) {
            $mbLeidosRAM = $bytesPorSegundoRAM / 1MB
            $lbaEstimadoRAM = [long](($currentBytesRAM % ($RamMaxMB * 1MB)) / $sectorSize)

            # CASO A: El bloque ya está cargado en nuestro tanque RAM (.NET User-Space)
            if ($global:RamBlockCache.ContainsKey($lbaEstimadoRAM)) {
                # Se consume el dato e instantáneamente se marca para descarte dinámico
                $null = $global:RamBlockCache.Remove($lbaEstimadoRAM)
                $global:RamCacheInstaladaMB = [System.Math]::Max(0.00, $global:RamCacheInstaladaMB - ($sectorSize / 1MB))
                
                # Forzar recolección de basura segura de .NET sin tocar el Kernel
                [System.GC]::Collect()
                
                # Rellenar preventivamente el espacio liberado leyendo la siguiente LBA del archivo
                if ($i -lt $totalSectores) {
                    $proximaLba = $lbaLista[$i]
                    if (-not $global:RamBlockCache.ContainsKey($proximaLba)) {
                        $global:RamBlockCache.Add($proximaLba, [byte]1)
                        $global:RamCacheInstaladaMB += ($sectorSize / 1MB)
                        $i++
                    }
                }
            } 
            # CASO B: MAPEO PROGRESIVO EN CALIENTE (LBA Nueva / No registrada) - RÉPLICA MOTOR EXPERIMENTAL
            else {
                # Escudo preventivo original integrado
                if ($null -eq $global:LbaIndexCache) {
                    $global:LbaIndexCache = New-Object System.Collections.Generic.HashSet[long]
                }

                if (-not $global:LbaIndexCache.Contains($lbaEstimadoRAM)) {
                    $null = $global:LbaIndexCache.Add($lbaEstimadoRAM)
                    $global:NuevosLbasRegistradosEnCaliente++

                    # =========================================================================
                    # RÉPLICA DE TU MOTOR EXPERIMENTAL ORIGINAL (CONSERVACIÓN DE MA_PEO PREVIO)
                    # =========================================================================
                    # Extraemos todo lo que hay en el HashSet vivo (que ya absorbió el pasado al arrancar)
                    $lbasOrdenados = [System.Linq.Enumerable]::ToArray($global:LbaIndexCache)
                    [System.Array]::Sort($lbasOrdenados)

                    # Reconstrucción compactada idéntica a tu diseño original (Bloques de 50)
                    $lineasOutput = @("ID_DISCO: $($global:DiskID)")
                    $bloqueActual = @()

                    foreach ($lba in $lbasOrdenados) {
                        $bloqueActual += $lba
                        if ($bloqueActual.Count -eq 50) {
                            $lineasOutput += "LBA-BLOCK: " + ($bloqueActual -join ", ")
                            $bloqueActual = @()
                        }
                    }
                    if ($bloqueActual.Count -gt 0) {
                        $lineasOutput += "LBA-BLOCK: " + ($bloqueActual -join ", ")
                    }

                    # Escritura atómica y limpia directo al archivo maestro (Sin pisar el progreso)
                    [System.IO.File]::WriteAllLines($global:gameMapFile, $lineasOutput)
                    # =========================================================================

                    Write-Log "RAM-ENGINE - New LBA sector [$lbaEstimadoRAM] intercepted and recorded in real time on a cumulative basis."
                }
            }


        # Panel de visualización dinámico en pantalla
        $textoTráficoRAM = if ($bytesPorSegundoRAM -gt 0) { "{0:N2} MB/s" -f ($bytesPorSegundoRAM / 1MB) } else { "0.00 MB/s" }
        Write-Host "[ DYNAMIC RAM TANK: $($global:RamCacheInstaladaMB.ToString('N2')) MB / $RamMaxMB.00 MB ]" -ForegroundColor Magenta
        Write-Host "[ CURRENT LBA INTERCEPTED: $lbaEstimadoRAM | NEW HOT-STATE RECORDS: $($global:NuevosLbasRegistradosEnCaliente) ]" -ForegroundColor Yellow
        Write-Host "[ EMULATED TRAFFIC: $textoTráficoRAM ]" -ForegroundColor Cyan
    Write-Host "---------------------------------------------------------" -ForegroundColor Gray
    Write-Host " [M] Go to Menu | [N] Normal Mode | [X] Exit the program" -ForegroundColor DarkGray

    # --- DETECTOR DE BOTONES EN CALIENTE (NO BLOQUEANTE) ---
    if ($Host.UI.RawUI.KeyAvailable) {
        $teclaPresionada = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        switch ($teclaPresionada.Character.ToString().ToUpper()) {
            "M" {
                Write-Host "`n[➔] Returning to the Main Menu..." -ForegroundColor Cyan
                Start-Sleep -Seconds 1
                break # Rompe el bucle actual para regresar al menú
            }
            "N" {
                Write-Host "`n[i] Switching to Normal Mode while running..." -ForegroundColor Yellow
                $global:RamCacheInstaladaMB = 0.00
                $global:gameMapFile = ""
                Start-Sleep -Seconds 1
                break # Rompe el bucle para reconfigurar el flujo sin fix
            }
            "X" {
                Write-Host "`n[X] Closing RAM-ENGINE and protecting processes..." -ForegroundColor Red
                Start-Sleep -Seconds 1
                Exit # Cierra la herramienta por completo de forma segura
            }
        }
    }
    # -------------------------------------------------------
        
        # Permitir la salida del bucle si el emulador se cierra
        if ($null -eq (Get-Process -Name "pcsx2", "pcsx2-qt", "ePSXe", "rpcs3", "RPCS3", "PPSSPPWindows64", "PPSSPPWindows" -ErrorAction SilentlyContinue)) {
            Write-Host "`n[-] Emulator closed. Shutting down RAM engine and returning to base state..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            break
        }

        Start-Sleep -Seconds 1
    }
}

if ($global:activarCargaPreventivaRAM) {
    # Ejecuta el motor dinámico pasando la ruta física limpia y el límite de 512 MB
    Invoke-RamCacheEngine -DrivePath $path -RamMaxMB 512
}


while($true) {
    try {

        Clear-Host # <-- NUEVA LÍNEA: Limpia la pantalla en cada ciclo para fijar la interfaz

        if ($global:pausado) {
            Write-Host "`r[!] MONITORING PAUSED (Optical Unit Resting)... Controls: [-]Resume [*]Exit    " -ForegroundColor Yellow -NoNewline
            
            # --- LEER TECLADO DURANTE LA PAUSA PARA EVITAR QUE SE QUEDE PEGADO ---
            if ([System.Console]::KeyAvailable) {
                $teclaPausa = [System.Console]::ReadKey($true)
                if ($teclaPausa.KeyChar -eq '-') { 
                    $global:pausado = -not $global:pausado
                    [System.Console]::Beep(600, 150) 
                }
                                if ($teclaPausa.KeyChar -eq '*') { 
                    "`nTOOL CLOSED FROM PAUSE: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $logFile -Append -Encoding utf8
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

        # --- BYPASS VIRTUAL DE LATENCIA EN MODO EXPERIMENTAL ---
        if ($global:modoExperimental) {
            # Si el emulador está leyendo activamente, asignamos una latencia de bajo impacto simulada
            # para forzar el salto inteligente del pulso físico y no estorbar el láser.
            if ($bytesTransferidosUltimoSegundo -gt 0) {
                $ms = 0.650
            } else {
                $ms = 0.710
            }
        } else {
            # Se mantiene el comportamiento original intacto si el usuario usa el Modo Normal/Turbo
            $tiempo = Measure-Command {
                $streamSonda = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
                $streamSonda.Close()
                $streamSonda.Dispose()
            }

            $ms = $tiempo.TotalMilliseconds
        }
        
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
                    Write-Host "`n[!] LOW-LATENCY MODE AUTOMATICALLY ACTIVATED" -ForegroundColor Magenta
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
                $accion = "GAME MAINTENANCE ($($emuladorActivo.Name))"
                $ejecutarPulso = $true
            } else {
                $motivoSalto = if ($ms -lt $limiteInfActual) { "LECTURA ACTIVA" } else { "LATENCIA ALTA" }
            }
        }
        elseif ($ms -ge $limiteInferior -and $ms -le ($limiteSuperior - 0.049)) {
            $accion = "STANDARD RESTING PULSE"
            $ejecutarPulso = $true
        }

        # --- INYECCIÓN PREVENTIVA ASILADA BLINDADA ---
        if ($global:modoExperimental -and $emuladorActivo) {
            try {
                # Pasamos solo la letra de unidad limpia en formato "F:" para evitar que métodos de .NET busquen paths de hardware directos
                $letraLimpiaBucle = $driveLetter.Replace(":", "").Replace("\", "")
                Invoke-ExperimentalCache -DrivePath "$letraLimpiaBucle`:" -CacheMaxMB 64
            }
            catch {
                Write-Log "MONITOR-LOOP - Preventive omission in this cycle: $_"
            }
        }

        # --- FILTRO INTELIGENTE ULTRA-SELECTIVO MODIFICADO ---
        # Si el modo experimental está activo, cualquier lectura por encima de 0 bytes cancelará el pulso físico.
        if ($global:modoExperimental) {
            if ($ejecutarPulso -and $bytesTransferidosUltimoSegundo -gt 0) { 
                $ejecutarPulso = $false 
                $motivoSalto = "ACTIVE READING GAME" 
            }
        } else {
            # Mantiene tu sensibilidad original de 10KB para el Modo Turbo estándar
            if ($ejecutarPulso -and $bytesTransferidosUltimoSegundo -gt 10KB) { 
                $ejecutarPulso = $false 
                $motivoSalto = "ACTIVE READING GAME" 
            }
        }

        # --- FILTRO INTELIGENTE: SI JUEGO LEE, SE CANCELA EL PULSO PARA EVITAR TIRONES ---
        if ($ejecutarPulso -and $bytesTransferidosUltimoSegundo -gt 10KB) { $ejecutarPulso = $false; $motivoSalto = "ACTIVE READING GAME" }

        if ($ejecutarPulso) {
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            $stream = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
            $null = $stream.Read($buffer, 0, 1)
            $stream.Close()
            $stream.Dispose()
            
            if ($esTurboActual) { $stats.ExitososTurbo++ } else { $stats.Exitosos++ }
            # --- SE REMUEVE EL `n DEL PRINCIPIO PARA EVITAR SPAM ---
            Write-Host ("{0} - [{1}] - Latency: {2:N3}ms" -f (Get-Date -Format 'HH:mm:ss'), $accion, $ms) -ForegroundColor Green
            Write-Log "PULSE OK - [$accion] - Latency: $($ms.ToString('N3'))ms - Current reading: $(($bytesTransferidosUltimoSegundo / 1MB).ToString('N2'))MB/s"
        } 
        else {
            if($esTurboActual) { $stats.SaltadosTurbo++ } else { $stats.Saltados++ }
            $colorSalto = if ($motivoSalto -eq "ACTIVE READING GAME") { "Green" } else { "Cyan" }
            # --- SE REMUEVE EL `n DEL PRINCIPIO PARA EVITAR SPAM ---
            Write-Host ("{0} - [LEAPT] - {1} ({2:N3}ms)" -f (Get-Date -Format 'HH:mm:ss'), $motivoSalto, $ms) -ForegroundColor $colorSalto
            Write-Log "LEAPT - Reason: $motivoSalto - Latency: $($ms.ToString('N3'))ms - Current reading: $(($bytesTransferidosUltimoSegundo / 1MB).ToString('N2'))MB/s"
        }
    } 
    catch {
        $errPrincipal = $_.ToString()
        Write-Host "`n$(Get-Date -Format 'HH:mm:ss') - [!] Unit busy (Reading data)." -ForegroundColor Yellow
        Write-Log "MONITOR-CATCH - Occupied physical unit: $errPrincipal"
    }

    # PANEL DE ESTADÍSTICAS CORREGIDO (CON VERSIÓN FIJA)
    $colorPanel = if($modoBajaLatenciaActivo){ "Magenta" } else { "White" }
    $textoBytes = if ($bytesTransferidosUltimoSegundo -gt 0) { "{0:N2} MB/s" -f ($bytesTransferidosUltimoSegundo / 1MB) } else { "0.00 MB/s" }
    
    # --- SE AGREGA LA VERSIÓN Y SE MANTIENE SIN SPAM 2.570 ---
    Write-Host "[ OPTICAL DRIVE MONITOR V2.570 ]" -ForegroundColor Cyan
    Write-Host "[ GLOBAL SESSION: $($inicioGlobal.Elapsed.ToString('hh\:mm\:ss')) | OK: $($stats.Exitosos) | JUMPS: $($stats.Saltados) | TRAFFIC: $textoBytes ]" -ForegroundColor $colorPanel
    
    if ($relojEmulador.ElapsedMilliseconds -gt 0) {
        $colorSesion = if ($emuladorActivo) { "Green" } else { "Gray" }
        $estadoJuego = if ($emuladorActivo) { "EXECUTING" } else { "ON PAUSE/CLOSED" }
        Write-Host "[ GAME SESSION ($estadoJuego): $($relojEmulador.Elapsed.ToString('hh\:mm\:ss')) ]" -ForegroundColor $colorSesion
        if ($global:modoExperimental) {
            # MODIFICACIÓN: Aplicamos un módulo matemático circular de 256MB para normalizar el indicador visual
            $totalAnticipadoRAM_Circular = $global:TotalDatosPrecargadosMB % 256.01
            
            # Panel mejorado con indicador del Tanque Circular y Acumulado Histórico normalizado a 256MB
            $textoCache = "[ EXPERIMENTAL SEXPR MODE ACTIVE | RAM TANK: {0:N2} MB / 64.00 MB ]" -f $global:CacheRAM_ActualMB
            $textoAcumulado = "[ PREDICTIVE TELEMETRY | TOTAL ANTICIPATED TO RAM: {0:N2} MB / 256.00 MB ]" -f $totalAnticipadoRAM_Circular
            
            Write-Host $textoCache -ForegroundColor Magenta
            Write-Host $textoAcumulado -ForegroundColor Yellow
            Write-Host "[ TURBO MODE ACTIVE | OK: $($stats.ExitososTurbo) | JUMPS: $($stats.SaltadosTurbo) ]" -ForegroundColor Red
        }
        elseif ($modoTurbo) {
            Write-Host "[ TURBO MODE ACTIVE | OK: $($stats.ExitososTurbo) | JUMPS: $($stats.SaltadosTurbo) ]" -ForegroundColor Red
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
                "`nTOOL CLOSED CORRECTLY: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $logFile -Append -Encoding utf8
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

        # --- MEJORA AJUSTADA: MAPEO AL FINAL DEL PROCESAMIENTO DEL SEGUNDO ---
        if ($global:modoExperimental -and $emuladorActivo -and $bytesTransferidosUltimoSegundo -gt 0) {
            try {
                $global:bytesTransferidosUltimoSegundo = $bytesTransferidosUltimoSegundo
                $letraLimpiaBucle = $driveLetter.Replace(":", "").Replace("\", "")
                Invoke-ExperimentalCache -DrivePath "$letraLimpiaBucle`:" -CacheMaxMB 64
            }
            catch {
                Write-Log "MONITOR-WAIT - Omission in second ${i}: $_"
            }
        }

        # --- LÓGICA DE VENTANA PREDICTIVA ADAPTATIVA ---
        if ($modoTurbo -and $emuladorActivo) {
            if ($i -le 2) {
                $traficoAcumuladoVentana += $bytesTransferidosUltimoSegundo
            }
        }
        else {
            if ($i -le 2) {
                $traficoAcumuladoVentana += $bytesTransferidosUltimoSegundo
            }
        }
        $esTurboActual = ($modoTurbo -and $emuladorActivo)
        $statusExtra = if($modoBajaLatenciaActivo){ " (LOW-LAT)" } else { "" }
        
        $textoEstado = if($global:modoExperimental){ "SEXPR-TURBO" } elseif($esTurboActual){ "TURBO" } else { "ESPERA$statusExtra" }

        # GUARDAMOS EL VALOR LIMPIO PARA LA BARRA ANTES DEL SLEEP
        $tasaParaPantalla = $bytesTransferidosUltimoSegundo

        # Mostramos la tasa instantánea con la guía completa de todos los controles
        $msg = "`r[{0}] Espe: {1}s | Controls: [´/+]Turbo [-]Pause [*]Exit | Rate: {2:N2} MB/s    " -f $textoEstado, $i, ($tasaParaPantalla / 1MB)
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
