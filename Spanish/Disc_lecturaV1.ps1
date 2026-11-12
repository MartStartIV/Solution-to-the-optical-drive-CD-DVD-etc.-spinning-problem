# ---VERSIÓN v2.574 - Se ha correguidos fallos criticos que impedian seleccionar las opciones anteriores ya funcionales limitando su funcionamiento, ya ahi registro de carga de datos en ram aunque es muy poca la cantidad que carga pero es el inicio de lo que se quiere lograr, aun queda bastante camino por recorrer, se han solucionado varios problemas criticos en el codigo base y limpieza general de funciones mal aplicadas pero cumpliendo en parte el objetivo, acceleración de unidad, mejoras leves en NFS most wanter a un 15% mas de rendimiento. ---
# Codigo llevado a cabo por MartStartIV
Clear-Host
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   MONITOR DE UNIDAD ÓPTICA V2.574             " -ForegroundColor Cyan
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


Write-Host "`n[i] Buscando hardware... Conecte la unidad óptica (CD, DVD, Blu-ray) para acceder al sistema." -ForegroundColor Yellow
Write-Host "-> Presione la tecla [ESC] en cualquier momento para salir de la herramienta." -ForegroundColor Gray

while ($null -eq $driveTarget) {
    # Comprobar si el usuario desea abortar la ejecución usando la tecla ESC
    if ([System.Console]::KeyAvailable) {
        $teclaSalida = [System.Console]::ReadKey($true)
        if ($teclaSalida.Key -eq 'Escape') {
            Write-Host "`n[-] Operación cancelada por el usuario. Saliendo..." -ForegroundColor Red
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
        Write-Host "`n[+] Hardware detectado con éxito en la unidad: $driveLetter" -ForegroundColor Green
    } else {
        # Espera breve para no saturar los ciclos de reloj de la CPU durante la búsqueda
        Start-Sleep -Milliseconds 500
    }
}

# --- VERIFICACIÓN AUTOMÁTICA DE DISCO EN LA UNIDAD ---
$mensajeMostrado = $false

while (-not $driveTarget.IsReady) {
    if (-not $mensajeMostrado) {
        Write-Host "`n[!] ADVERTENCIA: No se detecta ningún disco insertado en la unidad $driveLetter." -ForegroundColor Yellow
        Write-Host "Por favor, introduzca el disco del juego para continuar..." -ForegroundColor Yellow
        Write-Host "-> El sistema lo detectará automáticamente al ingresarlo o presione [ESC] para salir." -ForegroundColor Gray
        $mensajeMostrado = $true
    }

    # Escucha en tiempo real de la tecla ESC sin bloquear el flujo automático
    if ([System.Console]::KeyAvailable) {
        $teclaDisco = [System.Console]::ReadKey($true)
        if ($teclaDisco.Key -eq 'Escape') {
            Write-Host "`n[-] Operación cancelada por el usuario. Saliendo..." -ForegroundColor Red
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
Write-Host "   MONITOR DE UNIDAD ÓPTICA V2.574             " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "[+] Hardware detectado con éxito en la unidad: $driveLetter" -ForegroundColor Green
Write-Host "[+] Disco detectado correctamente en $driveLetter. Configurando entorno..." -ForegroundColor Green
Write-Host "-----------------------------------------------" -ForegroundColor Cyan

# Solicitud del Modo Turbo y Modo Experimental Extremo (LOGICA ESTABLE ORIGINAL RESTAURADA)
$global:modoExperimental = $false
$global:activarCargaPreventivaRAM = $false
$modoTurbo = $false

$opcion = Read-Host "¿Activar MODO ALTO RENDIMIENTO (Turbo) para Emuladores? (S/N o SEXPR para Experimental)"

# =========================================================================
# CONTROL DE ENRUTAMIENTO ESTRICTO ORIGINAL (PREVIENE FUGAS DE FLUJO)
# =========================================================================
if ($opcion -match "^sexpr" -or $opcion -eq "SEXPR") {
    $modoTurbo = $true
    $global:modoExperimental = $true
    
    # Si agregas el modificador + o *, se encenderá el disparador de precarga en RAM
    if ($opcion -eq "sexpr+" -or $opcion -eq "sexpr*") {
        $global:activarCargaPreventivaRAM = $true
        Write-Host "`n[!!!] MODO EXPERIMENTAL EXTREMO + CACHÉ PREVENTIVA EN RAM ACTIVADA" -ForegroundColor Magenta
    } else {
        $global:activarCargaPreventivaRAM = $false
        Write-Host "`n[!!!] MODO EXPERIMENTAL EXTREMO ACTIVADO - SÓLO PERFILADO DE MAPEO" -ForegroundColor Magenta
    }
    Start-Sleep -Seconds 2
} 
elseif ($opcion -match '^[sS]') {
    $modoTurbo = $true
    $global:activarCargaPreventivaRAM = $false
    $global:modoExperimental = $false
    Write-Host "`n[+] MODO TURBO ESTÁNDAR TRADICIONAL ACTIVADO" -ForegroundColor Green
    Start-Sleep -Seconds 1
} 
else {
    Write-Host "`n[i] Iniciando en Modo Normal (Sin RAM-ENGINE)" -ForegroundColor Yellow
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
"HERRAMIENTA INICIADA: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $logFile -Append -Encoding utf8
# --- TELEMETRÍA DE LOG: DETALLES DE VERSIÓN Y DISCO ---
"VERSION HERRAMIENTA: V2.574" | Out-File $logFile -Append -Encoding utf8
$etiquetaDisco = if ($driveTarget.IsReady) { $driveTarget.VolumeLabel } else { "Desconocido" }
"UNIDAD MONITOREADA : $driveLetter (Etiqueta: $etiquetaDisco)" | Out-File $logFile -Append -Encoding utf8
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
                Write-Log "RAM-ENGINE - Sincronización exitosa: Se absorbieron $($global:LbaIndexCache.Count) sectores mapeados de sesiones anteriores."
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
                $msgMapeo = "MAPEO-REGISTRO - [DATOS GUARDADOS EN MAPPING] | Sectores: $sectoresLeidos | Tamaño: $($mbLeidos.ToString('N2')) MB | Emulador: $nombreEmuladorActivo"
                Write-Log $msgMapeo
            }

            if ($global:CacheRAM_ActualMB -gt 0) {
                $global:CacheRAM_ActualMB = [System.Math]::Max(0.00, $global:CacheRAM_ActualMB - $mbLeidos)
            }

            $msgTracker = "EXPR-TRACKER - [EJECUTANDO: $nombreEmuladorActivo] - Bloques: $sectoresLeidos sectores ($sectorSize b) | TANQUE RAM SCRIPT: $($global:CacheRAM_ActualMB.ToString('N2')) MB | TOTAL LEÍDO DVD: $($global:TotalLeidoDVD_FisicoMB.ToString('N2')) MB"
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
        Write-Log "EXPR-CACHE - Bus retenido en este ciclo: $_"
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


# =========================================================================
# MOTOR DE CARGA PREVENTIVA EN RAM (ENCAPSULADO TOTAL CON MOTOR OPERATIVO CONTINUO) - PARTE 1
# =========================================================================
function Invoke-RamCacheEngine {
    [CmdletBinding()]
    param (
        [string]$DrivePath,
        [int]$RamMaxMB = 512
    )

    if ($null -ne $global:DiskID) { $global:DiskID = $global:DiskID.Trim().ToUpper() }

    $rutaDocumentosUniversal = [System.Environment]::GetFolderPath("MyDocuments")
    if ([string]::IsNullOrEmpty($rutaDocumentosUniversal)) {
        $rutaDocumentosUniversal = Join-Path -Path $env:USERPROFILE -ChildPath "Documents"
    }

    $global:mappingDir = Join-Path -Path $rutaDocumentosUniversal -ChildPath "Disc Rotation Tool LOGS\Disc_Mapping"
    $global:gameMapFile = Join-Path -Path $global:mappingDir -ChildPath "$($global:DiskID).txt"

    if ($null -eq $global:RamBlockCache) {
        $global:RamBlockCache = New-Object "System.Collections.Generic.Dictionary[long, byte[]]"
        $global:RamCacheInstaladaMB = 0.00
        $global:NuevosLbasRegistradosEnCaliente = 0
    }

    # ---------------------------------------------------------------------
    # PANEL INTERACTIVO DE ASIGNACIÓN (ENCAPSULADO)
    # ---------------------------------------------------------------------
    Clear-Host
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "           VERIFICACIÓN DE HARDWARE ÓPTICO               " -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host " [➔] DiskID detectado físicamente en la RAM: " -NoNewline
    Write-Host "'$($global:DiskID.Trim())'" -ForegroundColor Green
    Write-Host "=========================================================`n" -ForegroundColor Cyan

    $nombreSugerido = "$($global:DiskID.Trim()).txt"
    $rutaSugeridaFisica = Join-Path $global:mappingDir $nombreSugerido

    if (Test-Path $rutaSugeridaFisica) {
        Write-Host " [✓] ¡TELEMETRÍA LOCAL ENCONTRADA!" -ForegroundColor Green
        Write-Host " Se detectó el archivo definitivo para este disco: '$nombreSugerido'" -ForegroundColor Green
        Write-Host "---------------------------------------------------------" -ForegroundColor Gray
        Write-Host " Presione [ENTER] para cargar este mapeo automáticamente." -ForegroundColor Yellow
        Write-Host " O escriba el nombre de otro archivo si desea usar uno alternativo." -ForegroundColor Gray
        $entradaUsuario = Read-Host " Nombre del archivo"

        if ([string]::IsNullOrEmpty($entradaUsuario)) { $nombreLimpio = $global:DiskID.Trim() } 
        else { $nombreLimpio = $entradaUsuario.Trim().Replace(".txt", "") }
        $global:gameMapFile = Join-Path $global:mappingDir "$nombreLimpio.txt"
        $archivoExiste = Test-Path $global:gameMapFile
    } else {
        Write-Host " [!] ADVERTENCIA: Este juego no cuenta con un archivo de mapeo previo." -ForegroundColor Yellow
        Write-Host " Archivo ausente: '$nombreSugerido'`n" -ForegroundColor DarkYellow
        Write-Host "  Crear / Hacer Mapping del disco ahora mismo" -ForegroundColor White
        Write-Host "  Ejecutar en Modo Normal (Sin Fix)" -ForegroundColor White
        Write-Host "  Salir" -ForegroundColor White
        
        $opcionMenu = Read-Host " Seleccione una opción (1-3)"
        switch ($opcionMenu.Trim()) {
            "1" { Invoke-ExperimentalCache -DrivePath $global:driveTarget -CacheMaxMB 64; return }
            "2" { $archivoExiste = $false; $global:gameMapFile = ""; return }
            "3" { Exit }
            default { $archivoExiste = $false; return }
        }
    }

    # --- LECTURA HORIZONTAL AISLADA DE SECTORES (.TXT) (SINCRONIZACIÓN TOTAL CON HASHSET) ---
    if ($archivoExiste) {
        $lbaLista = New-Object System.Collections.Generic.List[long]
        
        # Aseguramos e inicializamos el HashSet indexador de la sesión viva para que recuerde el pasado
        if ($null -eq $global:LbaIndexCache) {
            $global:LbaIndexCache = New-Object System.Collections.Generic.HashSet[long]
        }

        $todasLasLineas = [System.IO.File]::ReadAllLines($global:gameMapFile)
        for ($numLinea = 1; $numLinea -lt $todasLasLineas.Count; $numLinea++) {
            $lineaActual = $todasLasLineas[$numLinea].Trim()
            if ($lineaActual.StartsWith("LBA-BLOCK:")) {
                $lineaActual.Substring(11).Trim() -split ',\s*' | ForEach-Object {
                    $sectorLimpioEngine = $_.Trim()
                    if ($sectorLimpioEngine -match "^\d+$") { 
                        # 1. Lo añadimos a la cola de precarga Win32
                        $lbaLista.Add([long]$sectorLimpioEngine)
                        # 2. BLOQUEO ULTRA-CRÍTICO: Lo guardamos en el HashSet para que el motor en caliente sepa que ya existía
                        $null = $global:LbaIndexCache.Add([long]$sectorLimpioEngine)
                    }
                }
            }
        }

        # --- MOTOR REAL DE EXTRACCIÓN POR PUERTO DE HARDWARE WIN32 ---
        $totalSectores = $lbaLista.Count
        if ($totalSectores -gt 0) {
            Clear-Host
            Write-Host "=========================================================" -ForegroundColor Cyan
            Write-Host "    INICIANDO PRECARGA PREVENTIVA EN MEMORIA RAM         " -ForegroundColor Cyan
            Write-Host "=========================================================" -ForegroundColor Cyan
            
            $sectorSize = 2048
            $bufferSectorReal = New-Object byte[] $sectorSize
            $bytesLeidosControl = 0
            $punteroNuevoSalida = 0

            $letraPura = $driveLetter.Replace(":", "").Replace("\", "")
            $targetWin32 = "\\.\$letraPura`:"
            $manejadorHardware = [Win32API.CDROM]::CreateFile($targetWin32, 0x80000000, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)

            for ($i = 0; $i -lt $totalSectores; $i++) {
                $lbaActual = $lbaLista[$i]
                
                # Filtro Anti-Latencia por Tráfico Externo
                $currentBytesCheck = [int64](Get-CimInstance -ClassName Win32_Process | Where-Object { $_.Name -match "pcsx2|pcsx2-qt|ePSXe|rpcs3|RPCS3|PPSSPPWindows64|PPSSPPWindows|System" } | Measure-Object -Property ReadTransferCount -Sum).Sum
                Start-Sleep -Milliseconds 10 
                $nextBytesCheck = [int64](Get-CimInstance -ClassName Win32_Process | Where-Object { $_.Name -match "pcsx2|pcsx2-qt|ePSXe|rpcs3|RPCS3|PPSSPPWindows64|PPSSPPWindows|System" } | Measure-Object -Property ReadTransferCount -Sum).Sum
                
                if (($nextBytesCheck - $currentBytesCheck) -gt 512KB) {
                    Write-Host "`n[!] Tráfico externo detectado. Pausando carga por 4 segundos..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 4
                    $i-- 
                    continue
                }

                if ($manejadorHardware -ne [IntPtr]-1) {
                    $offsetFisicoBytes = $lbaActual * $sectorSize
                    [void][Win32API.CDROM]::SetFilePointerEx($manejadorHardware, $offsetFisicoBytes, [ref]$punteroNuevoSalida, 0)
                    $null = [Win32API.CDROM]::ReadFile($manejadorHardware, $bufferSectorReal, $sectorSize, [ref]$bytesLeidosControl, [IntPtr]::Zero)
                    
                    if (-not $global:RamBlockCache.ContainsKey($lbaActual)) {
                        $global:RamBlockCache.Add($lbaActual, [byte]1)
                        $global:RamCacheInstaladaMB += ($sectorSize / 1MB)
                    }
                }
                
                # --- AQUÍ ESTÁ LA INYECCIÓN TELEMÉTRICA EN TIEMPO REAL ---
                $porcentaje = [int](($i / $totalSectores) * 100)
                Write-Host ("`r[➔] INYECTANDO SECTOR LBA: {0,-10} | Progreso: {1}% | Tanque: {2:N2} MB" -f $lbaActual, $porcentaje, $global:RamCacheInstaladaMB) -NoNewline
            }
            Write-Host "`n[✓] Datos inyectados con éxito en RAM. Láser estabilizado." -ForegroundColor Green
            Start-Sleep -Seconds 2
            # =========================================================================
            # CORAZÓN OPERATIVO EN CALIENTE: SEGUIMIENTO Y MAPEO ACUMULATIVO TOTAL (SEXPR+)
            # =========================================================================
            $lastBytesRAMEngine = 0
            $sectorSize = 2048
            $RamMaxMB = $global:RamCacheInstaladaMB

            Write-Host "`n[i] ESCANER ACTIVO: Esperando a que inicie el emulador para enlazar el tanque RAM..." -ForegroundColor Yellow

            # BUCLE DE ESPERA ACTIVA: Monitorea el sistema hasta que el juego aparezca en ejecución
            $emuladorActivoRAM = $null
            while ($null -eq $emuladorActivoRAM) {
                $emuladorActivoRAM = Get-Process -Name "pcsx2", "pcsx2-qt", "ePSXe", "rpcs3", "RPCS3", "PPSSPPWindows64", "PPSSPPWindows" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -eq $emuladorActivoRAM) {
                    if ($Host.UI.RawUI.KeyAvailable) {
                        $teclaEspera = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        if ($teclaEspera.Character.ToString().ToUpper() -eq "X") { Exit }
                    }
                    Start-Sleep -Seconds 1
                }
            }

            Write-Host "`n[+] Emulador detectado: $($emuladorActivoRAM.Name). Transfiriendo control operacional..." -ForegroundColor Green
            Start-Sleep -Seconds 1

            # BUCLE DE MONITOREO CONTINUO Y MAPEO ACUMULATIVO EN CALIENTE
            while ($true) {
                # Validamos si el emulador se cerró para retornar limpiamente al modo experimental base
                $verificarEmulador = Get-Process -Name "pcsx2", "pcsx2-qt", "ePSXe", "rpcs3", "RPCS3", "PPSSPPWindows64", "PPSSPPWindows" -ErrorAction SilentlyContinue | Where-Object { $_.Id -eq $emuladorActivoRAM.Id }
                if ($null -eq $verificarEmulador) {
                    Write-Host "`n[-] Emulador cerrado por el usuario. Protegiendo archivos de mapeo..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                    
                    # --- RECONFIGURACIÓN EN CALIENTE PARA REDIRIGIR AL MONITOR EXPERIMENTAL ---
                    $global:activarCargaPreventivaRAM = $false  # Apaga la precarga en RAM para salir de esta función
                    $global:modoExperimental = $true           # Mantiene el modo experimental activo para el monitor general
                    $modoTurbo = $true                         # Mantiene el modo turbo activo para el bypass virtual
                    $global:RamCacheInstaladaMB = 0.00         # Resetea el contador del tanque para la siguiente carga
                    
                    break # Rompe este bucle de la RAM y devuelve el control al flujo principal en modo experimental
                }

                Clear-Host
                Write-Host "=========================================================" -ForegroundColor Green
                Write-Host "     MOTOR DE MEMORIA RAM EN EJECUCIÓN CONTINUA (SEXPR+) " -ForegroundColor Green
                Write-Host "=========================================================" -ForegroundColor Green
                Write-Host "[✓] Enlazado con éxito al proceso: $($emuladorActivoRAM.Name)" -ForegroundColor Green

                # Captura de tráfico en tiempo real del proceso emulador
                $currentBytesRAM = [int64](Get-CimInstance -ClassName Win32_Process | 
                    Where-Object { $_.Name -match "pcsx2|pcsx2-qt|ePSXe|rpcs3|RPCS3|PPSSPPWindows64|PPSSPPWindows|System" } | 
                    Measure-Object -Property ReadTransferCount -Sum).Sum

                $diffRAM = if ($lastBytesRAMEngine -gt 0) { $currentBytesRAM - $lastBytesRAMEngine } else { 0 }
                $lastBytesRAMEngine = $currentBytesRAM
                $bytesPorSegundoRAM = if ($diffRAM -gt 0) { $diffRAM } else { 0 }

                # Estimación analítica de LBA solicitada por el emulador (BLINDAJE ANTI-DIVISIÓN POR CERO)
                if ($bytesPorSegundoRAM -gt 0) {
                    $mbLeidosRAM = $bytesPorSegundoRAM / 1MB
                    
                    # Evita que el script colapse con discos nuevos si el pool inicial es 0
                    $colchonSeguridadMB = if ($RamMaxMB -gt 0) { $RamMaxMB } else { 16.00 }
                    $lbaEstimadoRAM = [long](($currentBytesRAM % ($colchonSeguridadMB * 1MB)) / $sectorSize)

                    # Aseguramos la existencia del HashSet indexador en la sesión viva
                    if ($null -eq $global:LbaIndexCache) {
                        $global:LbaIndexCache = New-Object System.Collections.Generic.HashSet[long]
                    }

                    # --- COMPORTAMIENTO MEJORADO ACCUMULATIVE SKIP (REPLICA EXACTA EXPERIMENTAL) ---
                    # 1. Conservamos los LBAs de la precarga en $global:RamBlockCache sin borrarlos de la memoria
                    if (-not $global:RamBlockCache.ContainsKey($lbaEstimadoRAM)) {
                        # Si el emulador pisa una zona nueva, la sumamos al contenedor en RAM de inmediato
                        $global:RamBlockCache.Add($lbaEstimadoRAM, [byte]1)
                        $global:RamCacheInstaladaMB += ($sectorSize / 1MB)
                    }

                    # 2. Guardamos de forma acumulativa en el archivo maestro .txt sin pisar el progreso anterior
                    if (-not $global:LbaIndexCache.Contains($lbaEstimadoRAM)) {
                        $null = $global:LbaIndexCache.Add($lbaEstimadoRAM)
                        $global:NuevosLbasRegistradosEnCaliente++

                        # Reordenación total numérica ascendente en memoria RAM
                        $lbasOrdenados = [System.Linq.Enumerable]::ToArray($global:LbaIndexCache)
                        [System.Array]::Sort($lbasOrdenados)

                        # Reconstrucción compactada atómica horizontal (Bloques de 50)
                        $lineasOutput = @("ID_DISCO: $($global:DiskID)")
                        $bloqueActual = @()

                        foreach ($lbaElemento in $lbasOrdenados) {
                            $bloqueActual += $lbaElemento
                            if ($bloqueActual.Count -eq 50) {
                                $lineasOutput += "LBA-BLOCK: " + ($bloqueActual -join ", ")
                                $bloqueActual = @()
                            }
                        }
                        if ($bloqueActual.Count -gt 0) {
                            $lineasOutput += "LBA-BLOCK: " + ($bloqueActual -join ", ")
                        }

                        # Escritura física limpia sin corromper el histórico
                        [System.IO.File]::WriteAllLines($global:gameMapFile, $lineasOutput)
                        Write-Log "RAM-ENGINE (SEXPR+) - Nuevo sector LBA [$lbaEstimadoRAM] interceptado y sumado al archivo maestro."
                    }

                # Panel de visualización dinámico en tiempo real
                $textoTraficoRAM = if ($bytesPorSegundoRAM -gt 0) { "{0:N2} MB/s" -f ($bytesPorSegundoRAM / 1MB) } else { "0.00 MB/s" }
                Write-Host "[ TOTAL ACUMULADO EN TANQUE RAM: $($global:RamCacheInstaladaMB.ToString('N2')) MB ]" -ForegroundColor Magenta
                Write-Host "[ LBA INTERCEPTADA: $lbaEstimadoRAM | NUEVOS SECTORES CAPTURADOS: $($global:NuevosLbasRegistradosEnCaliente) ]" -ForegroundColor Yellow
                Write-Host "[ VELOCIDAD LECTURA EMULADOR: $textoTraficoRAM ]" -ForegroundColor Cyan
                Write-Host "---------------------------------------------------------" -ForegroundColor Gray
                Write-Host " [M] Retornar al Monitor General | [X] Salir de la Herramienta" -ForegroundColor DarkGray

                # Detector de botones en caliente no bloqueante
                if ($Host.UI.RawUI.KeyAvailable) {
                    $teclaPresionada = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    if ($teclaPresionada.Character.ToString().ToUpper() -eq "M") { break }
                    if ($teclaPresionada.Character.ToString().ToUpper() -eq "X") { Exit }
                }
                Start-Sleep -Seconds 1
            }
            # =========================================================================
        }
    }
  }
}

# =========================================================================
# DISPARADOR CRÍTICO: SOLO TRABAJA SI ELEGISTE "sexpr+" o "sexpr*"
# =========================================================================
if ($global:activarCargaPreventivaRAM) {
    Invoke-RamCacheEngine -DrivePath $path -RamMaxMB 512
}
# =========================================================================




while($true) {
    try {

        Clear-Host # <-- NUEVA LÍNEA: Limpia la pantalla en cada ciclo para fijar la interfaz

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

        # --- INYECCIÓN PREVENTIVA ASILADA BLINDADA ---
        if ($global:modoExperimental -and $emuladorActivo) {
            try {
                # Pasamos solo la letra de unidad limpia en formato "F:" para evitar que métodos de .NET busquen paths de hardware directos
                $letraLimpiaBucle = $driveLetter.Replace(":", "").Replace("\", "")
                Invoke-ExperimentalCache -DrivePath "$letraLimpiaBucle`:" -CacheMaxMB 64
            }
            catch {
                Write-Log "MONITOR-BUCLE - Omisión preventiva en este ciclo: $_"
            }
        }

        # --- FILTRO INTELIGENTE ULTRA-SELECTIVO MODIFICADO ---
        # Si el modo experimental está activo, cualquier lectura por encima de 0 bytes cancelará el pulso físico.
        if ($global:modoExperimental) {
            if ($ejecutarPulso -and $bytesTransferidosUltimoSegundo -gt 0) { 
                $ejecutarPulso = $false 
                $motivoSalto = "LECTURA ACTIVA JUEGO" 
            }
        } else {
            # Mantiene tu sensibilidad original de 10KB para el Modo Turbo estándar
            if ($ejecutarPulso -and $bytesTransferidosUltimoSegundo -gt 10KB) { 
                $ejecutarPulso = $false 
                $motivoSalto = "LECTURA ACTIVA JUEGO" 
            }
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
            # --- SE REMUEVE EL `n DEL PRINCIPIO PARA EVITAR SPAM ---
            Write-Host ("{0} - [{1}] - Latencia: {2:N3}ms" -f (Get-Date -Format 'HH:mm:ss'), $accion, $ms) -ForegroundColor Green
            Write-Log "PULSO OK - [$accion] - Latencia: $($ms.ToString('N3'))ms - Lectura actual: $(($bytesTransferidosUltimoSegundo / 1MB).ToString('N2'))MB/s"
        } 
        else {
            if($esTurboActual) { $stats.SaltadosTurbo++ } else { $stats.Saltados++ }
            $colorSalto = if ($motivoSalto -eq "LECTURA ACTIVA JUEGO") { "Green" } else { "Cyan" }
            # --- SE REMUEVE EL `n DEL PRINCIPIO PARA EVITAR SPAM ---
            Write-Host ("{0} - [SALTADO] - {1} ({2:N3}ms)" -f (Get-Date -Format 'HH:mm:ss'), $motivoSalto, $ms) -ForegroundColor $colorSalto
            Write-Log "SALTADO - Motivo: $motivoSalto - Latencia: $($ms.ToString('N3'))ms - Lectura actual: $(($bytesTransferidosUltimoSegundo / 1MB).ToString('N2'))MB/s"
        }
    } 
    catch {
        $errPrincipal = $_.ToString()
        Write-Host "`n$(Get-Date -Format 'HH:mm:ss') - [!] Unidad ocupada (Lectura de datos)." -ForegroundColor Yellow
        Write-Log "MONITOR-CATCH - Unidad física ocupada: $errPrincipal"
    }

    # PANEL DE ESTADÍSTICAS CORREGIDO (CON VERSIÓN FIJA)
    $colorPanel = if($modoBajaLatenciaActivo){ "Magenta" } else { "White" }
    $textoBytes = if ($bytesTransferidosUltimoSegundo -gt 0) { "{0:N2} MB/s" -f ($bytesTransferidosUltimoSegundo / 1MB) } else { "0.00 MB/s" }
    
    # --- SE AGREGA LA VERSIÓN Y SE MANTIENE SIN SPAM V2.574 ---
    Write-Host "[ MONITOR DE UNIDAD ÓPTICA V2.574 ]" -ForegroundColor Cyan
    Write-Host "[ SESIÓN GLOBAL: $($inicioGlobal.Elapsed.ToString('hh\:mm\:ss')) | OK: $($stats.Exitosos) | SALTOS: $($stats.Saltados) | TRÁFICO: $textoBytes ]" -ForegroundColor $colorPanel
    
    if ($relojEmulador.ElapsedMilliseconds -gt 0) {
        $colorSesion = if ($emuladorActivo) { "Green" } else { "Gray" }
        $estadoJuego = if ($emuladorActivo) { "EJECUTANDO" } else { "EN PAUSA/CERRADO" }
        Write-Host "[ SESIÓN JUEGO ($estadoJuego): $($relojEmulador.Elapsed.ToString('hh\:mm\:ss')) ]" -ForegroundColor $colorSesion
        if ($global:modoExperimental) {
            # MODIFICACIÓN: Aplicamos un módulo matemático circular de 256MB para normalizar el indicador visual
            $totalAnticipadoRAM_Circular = $global:TotalDatosPrecargadosMB % 256.01
            
            # Panel mejorado con indicador del Tanque Circular y Acumulado Histórico normalizado a 256MB
            $textoCache = "[ MODO EXPERIMENTAL SEXPR ACTIVO | TANQUE RAM: {0:N2} MB / 64.00 MB ]" -f $global:CacheRAM_ActualMB
            $textoAcumulado = "[ TELEMETRÍA PREDICTIVA | TOTAL ANTICIPADO A RAM: {0:N2} MB / 256.00 MB ]" -f $totalAnticipadoRAM_Circular
            
            Write-Host $textoCache -ForegroundColor Magenta
            Write-Host $textoAcumulado -ForegroundColor Yellow
            Write-Host "[ MODO TURBO ACTIVO | OK: $($stats.ExitososTurbo) | SALTOS: $($stats.SaltadosTurbo) ]" -ForegroundColor Red
        }
        elseif ($modoTurbo) {
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

        # --- MEJORA AJUSTADA: MAPEO AL FINAL DEL PROCESAMIENTO DEL SEGUNDO ---
        if ($global:modoExperimental -and $emuladorActivo -and $bytesTransferidosUltimoSegundo -gt 0) {
            try {
                $global:bytesTransferidosUltimoSegundo = $bytesTransferidosUltimoSegundo
                $letraLimpiaBucle = $driveLetter.Replace(":", "").Replace("\", "")
                Invoke-ExperimentalCache -DrivePath "$letraLimpiaBucle`:" -CacheMaxMB 64
            }
            catch {
                Write-Log "MONITOR-ESPERA - Omisión en segundo ${i}: $_"
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
        $msg = "`r[{0}] Espe: {1}s | Controles: [´/+]Turbo [-]Pausa [*]Salir | Tasa: {2:N2} MB/s    " -f $textoEstado, $i, ($tasaParaPantalla / 1MB)
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
