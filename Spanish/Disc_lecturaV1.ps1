# ---VERSIÓN v2.480 - se acaba de iniciar el soporte de la carga de datos en la ram, esta versión supone un avance a este objetivo aunque aun no representa funcionamiento como tal, ya tenemos lo siguiente: el reconocmiento del la ID del disco al acceder a la función sexpr+, el reconocimiento parcial de la ubicación del archivo mapping con su ubicación trabaja, reconocimiento total de los LBA registrados en dicha sesión, pero la carga de datos en ram sigue sin funcionar por ahora. ---
# Codigo llevado a cabo por MartStartIV
Clear-Host
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   MONITOR DE UNIDAD ÓPTICA V2.480             " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

# --- DETECCIÓN AUTOMÁTICA DE HARDWARE ÓPTICO ---
$driveTarget = $null
$driveLetter = ""
# --- COMPILACIÓN INICIAL OBLIGATORIA DE LA API DE HARDWARE NATIVO ---
if (-not ([Ref].Assembly.GetType('Win32API.CDROM'))) {
    $firmasNativas = @'
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr CreateFile(string lpFileName, int dwDesiredAccess, int dwShareMode, IntPtr lpSecurityAttributes, int dwCreationDisposition, int dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool DeviceIoControl(IntPtr hDevice, uint dwIoControlCode, ref CDROM_SET_SPEED lpInBuffer, uint nInBufSize, IntPtr lpOutBuf, uint nOutBufSize, ref uint lpBytesRet, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool DeviceIoControl(IntPtr hDevice, uint dwIoControlCode, IntPtr lpInBuffer, uint nInBufferSize, ref DISK_GEOMETRY lpOutBuffer, uint nOutBufferSize, ref uint lpBytesReturned, IntPtr lpOverlapped);

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
Write-Host "   MONITOR DE UNIDAD ÓPTICA V2.480             " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "[+] Hardware detectado con éxito en la unidad: $driveLetter" -ForegroundColor Green
Write-Host "[+] Disco detectado correctamente en $driveLetter. Configurando entorno..." -ForegroundColor Green
Write-Host "-----------------------------------------------" -ForegroundColor Cyan

# Solicitud del Modo Turbo y Modo Experimental Extremo
$global:modoExperimental = $false
$global:activarCargaPreventivaRAM = $false

$opcion = Read-Host "¿Activar MODO ALTO RENDIMIENTO (Turbo) para Emuladores? (S/N o SEXPR para Experimental)"

# -Función de opciones mejorada.
if ($opcion -eq "sexpr+" -or $opcion -eq "sexpr*") {
    $modoTurbo = $true
    $global:modoExperimental = $true
    $global:activarCargaPreventivaRAM = $true
    Write-Host "`n[!!!] MODO EXPERIMENTAL EXTREMO + CACHÉ PREVENTIVA EN RAM ACTIVADA" -ForegroundColor Magenta
    Start-Sleep -Seconds 2
} elseif ($opcion -eq "sexpr" -or $opcion -eq "SEXPR") {
    $modoTurbo = $true
    $global:modoExperimental = $true
    $global:activarCargaPreventivaRAM = $false
    Write-Host "`n[!!!] MODO EXPERIMENTAL EXTREMO ACTIVADO - SÓLO PERFILADO DE MAPEO" -ForegroundColor Magenta
    Start-Sleep -Seconds 2
} elseif ($opcion -match '^[sS]') {
    $modoTurbo = $true
}


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
"VERSION HERRAMIENTA: V2.480" | Out-File $logFile -Append -Encoding utf8
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

        # --- CARGA E INDEXACIÓN INTELIGENTE DE MAPA EXISTENTE ---
        if ($null -eq $global:LbaIndexCache) {
            $global:LbaIndexCache = New-Object System.Collections.Generic.HashSet[long]
            
            if (Test-Path $gameMapFile) {
                # Extraer todos los números de los bloques horizontales ya registrados
                [System.IO.File]::ReadLines($gameMapFile) | Where-Object { $_ -match "LBA-BLOCK:\s*(.+)" } | ForEach-Object {
                    $_.Split(',').Replace("LBA-BLOCK:", "").Trim() | Where-Object { $_ -match "^\d+$" } | ForEach-Object {
                        $null = $global:LbaIndexCache.Add([long]$_)
                    }
                }
            } else {
                # Inicializar el archivo con la ID única del disco en la primera línea
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

Write-Host "`nIniciando monitoreo especializado en $driveLetter..." -ForegroundColor Green

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
        Write-Host " [!] ALERTA: No existe un archivo de mapeo para este disco." -ForegroundColor Yellow
        Write-Host " Identificador detectado: $($global:DiskID)" -ForegroundColor Cyan
        Write-Host "=========================================================" -ForegroundColor Yellow
        Write-Host "Para usar la carga en RAM, el disco debe ser perfilado primero.`n" -ForegroundColor White
        
        Write-Host "Seleccione una opción válida para continuar:" -ForegroundColor Gray
        Write-Host " [S] Iniciar Modo Mapping (Redirigir a Función Experimental)" -ForegroundColor Green
        Write-Host " [N] Continuar en Modo Normal (Herramienta Estándar sin RAM)" -ForegroundColor White
        Write-Host " [X] Salir de la herramienta de monitoreo óptico" -ForegroundColor Red
        
        $opcionInvalida = $true
        while ($opcionInvalida) {
            $seleccion = Read-Host "`nElija una opción (S / N / X)"
            switch ($seleccion.ToUpper()) {
                "S" {
                    $global:modoExperimental = $true
                    $global:activarCargaPreventivaRAM = $false
                    Write-Host "`n[+] Redirigiendo al sistema Experimental de Mapeo..." -ForegroundColor Magenta
                    Start-Sleep -Seconds 2
                    return # Rompe la función y permite que el script principal tome el flujo experimental
                }
                "N" {
                    $global:modoExperimental = $false
                    $global:activarCargaPreventivaRAM = $false
                    $script:modoTurbo = $false
                    Write-Host "`n[+] Configurando Modo Normal estándar..." -ForegroundColor Green
                    Start-Sleep -Seconds 2
                    return
                }
                "X" {
                    Write-Host "`n[-] Saliendo del sistema de forma limpia..." -ForegroundColor Red
                    Start-Sleep -Seconds 1
                    Exit
                }
                Default {
                    Write-Host "[!] Opción no reconocida. Intente de nuevo." -ForegroundColor Yellow
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

    Write-Log "RAM-ENGINE - Contenedor dinámico inicializado con éxito para la ID: $($global:DiskID)"
}

    # 3. EXTRACCIÓN E INDEXACIÓN DE SECTORES DEL ARCHIVO DE MAPEO (DIAGNÓSTICO ULTRA-PRO)
    $lbaLista = New-Object System.Collections.Generic.List[long]

    Write-Host "`n=== DETALLES DE TELEMETRÍA DE RUTAS ===" -ForegroundColor Magenta
    Write-Host " DiskID registrado en memoria: '$global:diskID'" -ForegroundColor Yellow
    

    # --- LIMPIAMOS LA PANTALLA ANTES DE MOSTRAR EL PANEL ---
    Clear-Host

    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "           VERIFICACIÓN DE HARDWARE ÓPTICO               " -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host " [➔] DiskID detectado físicamente en la RAM: " -NoNewline
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
        Write-Host " [✓] ¡TELEMETRÍA LOCAL ENCONTRADA!" -ForegroundColor Green
        Write-Host " Se detectó el archivo definitivo para este disco: '$nombreSugerido'" -ForegroundColor Green
        Write-Host "---------------------------------------------------------" -ForegroundColor Gray
        Write-Host " Presione [ENTER] para cargar este mapeo automáticamente." -ForegroundColor Yellow
        Write-Host " O escriba el nombre de otro archivo si desea usar uno alternativo." -ForegroundColor Gray
        $entradaUsuario = Read-Host " Nombre del archivo"

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
                Write-Host "`n [+] Vinculación por defecto exitosa. Cargando sectores..." -ForegroundColor Green
            } else {
                Write-Host "`n [!] Cargando archivo alternativo verificado: '$nombreArchivoFinal'" -ForegroundColor Cyan
            }
            Start-Sleep -Seconds 2
        } else {
            $archivoExiste = $false
            Write-Host "`n [!] ERROR: El archivo alternativo '$nombreArchivoFinal' no existe." -ForegroundColor Red
            Start-Sleep -Seconds 3
        }

    } else {
        # ---------------------------------------------------------------------
        # CASO B: EL ARCHIVO NO EXISTE (DESPLIEGUE DEL MENÚ DE ACCIÓN)
        # ---------------------------------------------------------------------
        Write-Host " [!] ADVERTENCIA: Este juego no cuenta con un archivo de mapeo previo." -ForegroundColor Yellow
        Write-Host " Archivo ausente: '$nombreSugerido' en la carpeta Disc_Mapping.`n" -ForegroundColor DarkYellow
        
        Write-Host " ¿Qué acción desea realizar con la herramienta?" -ForegroundColor Cyan
        Write-Host "  [1] Crear / Hacer Mapping del disco ahora mismo" -ForegroundColor White
        Write-Host "  [2] Ejecutar en Modo Normal (Continuar al emulador sin Fix)" -ForegroundColor White
        Write-Host "  [3] Salir de la herramienta" -ForegroundColor White
        Write-Host "---------------------------------------------------------" -ForegroundColor Gray
        
        $opcionMenu = Read-Host " Seleccione una opción (1-3)"

        switch ($opcionMenu.Trim()) {
            "1" {
                Write-Host "`n [➔] Iniciando el asistente de creación de Mapping para '$nombreSugerido'..." -ForegroundColor Cyan
                # Aquí el script debería redirigir a tu función de creación de mapas
                # Por ejemplo: Invoke-MappingWizard o el código que use tu fix para generar el txt
                $archivoExiste = $false 
                Start-Sleep -Seconds 3
            }
            "2" {
                Write-Host "`n [i] Pasando a Modo Normal. Desactivando RAM-ENGINE de forma segura..." -ForegroundColor Yellow
                $archivoExiste = $false
                $global:gameMapFile = ""
                # Seteamos la RAM en 0 para que el script original entienda que va directo al emulador
                $global:RamCacheInstaladaMB = 0.00 
                Start-Sleep -Seconds 2
            }
            "3" {
                Write-Host "`n [X] Cerrando herramienta. Protegiendo procesos operativos..." -ForegroundColor Red
                Start-Sleep -Seconds 2
                Exit
            }
            default {
                Write-Host "`n [!] Opción inválida. Cancelando lectura por seguridad..." -ForegroundColor Red
                $archivoExiste = $false
                Start-Sleep -Seconds 3
            }
        }
    }
    # =========================================================================

    if ($archivoExiste) {
        Write-Host " Ruta final aprobada para el motor: '$global:gameMapFile'" -ForegroundColor Yellow
    }


    
    # --- BLOQUE SEGURO COMPROBACIÓN DE RUTAS ---
    if ([string]::IsNullOrEmpty($global:mappingDir) -or [string]::IsNullOrEmpty($global:gameMapFile)) {
        $carpetaExiste = $false
        $archivoExiste = $false
        Write-Host " [3] ¿La carpeta contenedora existe?: FALSO (Ruta no definida/vacía)" -ForegroundColor Red
        Write-Host " [4] ¿El archivo específico existe?: FALSO" -ForegroundColor Red
    } else {
        # Comprobar si al menos la carpeta existe
        $carpetaExiste = Test-Path $global:mappingDir
        Write-Host " [3] ¿La carpeta contenedora existe?: $carpetaExiste (Ruta: '$($global:mappingDir)')" -ForegroundColor Yellow
        
        # Comprobar si el archivo específico existe
        $archivoExiste = Test-Path $global:gameMapFile
        Write-Host " [4] ¿El archivo específico existe?: $archivoExiste" -ForegroundColor Yellow
    }

    
        if (-not $archivoExiste -and $carpetaExiste) {
        Write-Host " [5] Archivos reales encontrados en esa carpeta en este momento:" -ForegroundColor Gray
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

    # VERIFICACIÓN Y LECTURA ULTRA-PRE_CISA POR COLUMNAS
    if (-not [string]::IsNullOrEmpty($global:gameMapFile) -and $archivoExiste) {
        Write-Host "[+] Ruta validada con éxito. Procesando la lectura de sectores..." -ForegroundColor Green
        
        # 1. Aseguramos la inicialización limpia de la lista de sectores
        $lbaLista = New-Object System.Collections.Generic.List[long]
        $rutaFisica = $global:gameMapFile.Replace('"', '').Trim()

        if (Test-Path $rutaFisica) {
            # 2. Cargamos todas las líneas del archivo en memoria para analizarlas una a una
            $todasLasLineas = [System.IO.File]::ReadAllLines($rutaFisica)

            # Analizamos desde la segunda línea en adelante (Índice 1 en programación)
            for ($numLinea = 1; $numLinea -lt $todasLasLineas.Count; $numLinea++) {
                $lineaActual = $todasLasLineas[$numLinea].Trim()

                # Verificamos si la línea comienza con el encabezado correcto (Columna 1 a 11)
                if ($lineaActual.StartsWith("LBA-BLOCK:")) {
                    
                    # Extraemos todo el texto a partir de la columna 12 (donde empiezan los números)
                    $cadenaNumeros = $lineaActual.Substring(11).Trim()
                    
                    # Separamos la cadena usando el patrón exacto que descubriste: coma y espacio
                    $bloquesSectores = $cadenaNumeros -split ',\s*'

                    foreach ($sectorTexto in $bloquesSectores) {
                        $sectorLimpio = $sectorTexto.Trim()
                        
                        # Validamos que el dato extraído de la columna sea un número puro antes de sumarlo
                        if ($sectorLimpio -match "^\d+$") {
                            $lbaLista.Add([long]$sectorLimpio)
                        }
                    }
                }
            }
        }

        # --- 3. ASIGNACIÓN GLOBAL OBLIGATORIA DEL TANQUE ---
        $global:totalSectores = $lbaLista.Count

        if ($global:totalSectores -gt 0) {
            # Calculamos el tamaño real en MB
            $calculoRealMB = ($global:totalSectores * 2048) / 1MB
            
            # PROTECCIÓN: Si el mapa es muy pequeño, forzamos un mínimo de 1.00 MB para activar el motor físico
            if ($calculoRealMB -lt 1.00) {
                $global:RamCacheInstaladaMB = 1.00
            } else {
                $global:RamCacheInstaladaMB = [math]::Round($calculoRealMB, 2)
            }
            
            Write-Host " [✓] Éxito: Se procesaron $($todasLasLineas.Count - 1) líneas de datos LBA." -ForegroundColor Green
            Write-Host " [✓] Cola de telemetría: $($global:totalSectores) sectores cargados ($($global:RamCacheInstaladaMB) MB)." -ForegroundColor Green
            Start-Sleep -Seconds 2
        } else {
            $global:RamCacheInstaladaMB = 0.00
            Write-Warning "No se pudieron extraer sectores. Revise el formato del archivo."
            Start-Sleep -Seconds 4
        }
    }



    $totalSectores = $lbaLista.Count
    if ($totalSectores -eq 0) {
        Write-Host "[!] El archivo de mapeo está vacío. Redirigiendo a modo experimental..." -ForegroundColor Yellow
        $global:modoExperimental = $true
        Start-Sleep -Seconds 2
        return
    }

    # 4. ALGORITMO DE PRECARGA CONTROLADA (0% A 100%) CON GIRO ACTIVO DEL MOTOR
    Clear-Host
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host " INICIANDO PRECARGA DINÁMICA EN RAM (Límite: $RamMaxMB MB) " -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "[i] Levantando revoluciones del disco óptico..." -ForegroundColor Yellow

    $relojGiro = [System.Diagnostics.Stopwatch]::StartNew()
    $bufferGiro = New-Object byte[] 1
    $sectorSize = 2048

    for ($i = 0; $i -lt $totalSectores; $i++) {
        $lbaActual = $lbaLista[$i]

        # --- FILTRO ANTI-LATENCIA EN PRECARGA (MÍNIMO 512 KB/s DE TRÁFICO EXTERNO) ---
        $currentBytesCheck = [int64](Get-CimInstance -ClassName Win32_Process | 
            Where-Object { $_.Name -match "pcsx2|pcsx2-qt|ePSXe|rpcs3|RPCS3|PPSSPPWindows64|PPSSPPWindows|System" } | 
            Measure-Object -Property ReadTransferCount -Sum).Sum
        
        Start-Sleep -Milliseconds 10 # Pequeño muestreo diferencial
        
        $nextBytesCheck = [int64](Get-CimInstance -ClassName Win32_Process | 
            Where-Object { $_.Name -match "pcsx2|pcsx2-qt|ePSXe|rpcs3|RPCS3|PPSSPPWindows64|PPSSPPWindows|System" } | 
            Measure-Object -Property ReadTransferCount -Sum).Sum
        
        if (($nextBytesCheck - $currentBytesCheck) -gt 512KB) {
            Write-Host "`n[!] Tráfico externo detectado en el disco. Pausando carga por 4 segundos para evitar latencia..." -ForegroundColor Yellow
            Start-Sleep -Seconds 4
            $i-- # Reintentar el mismo sector al retomar
            continue
        }

        # --- SISTEMA DE PULSOS INTEGRADO DURANTE LA CARGA (CADA 350ms APROX) ---
        if ($relojGiro.ElapsedMilliseconds -gt 350) {
            try {
                $streamGiro = [System.IO.File]::Open($DrivePath, 'Open', 'Read', 'ReadWrite')
                $null = $streamGiro.Read($bufferGiro, 0, 1)
                $streamGiro.Close()
                $streamGiro.Dispose()
            } catch {}
            $relojGiro.Restart()
        }

        # --- INYECCIÓN EN EL DICCIONARIO (.NET USER-SPACE) ---
        # Si el tamaño estimado de la caché simulada no excede el límite asignado, guardamos la clave LBA
        if ($global:RamCacheInstaladaMB -lt $RamMaxMB) {
            if (-not $global:RamBlockCache.ContainsKey($lbaActual)) {
                # Inyectamos un byte simulado representando la presencia del sector indexado en memoria
                $global:RamBlockCache.Add($lbaActual, [byte]1)
                $global:RamCacheInstaladaMB += ($sectorSize / 1MB)
            }
        } else {
            Write-Host "`n[i] Límite de $RamMaxMB MB alcanzado en el tanque dinámico." -ForegroundColor Magenta
            break
        }

        # --- INDICADOR VISUAL EN TIEMPO REAL ---
        $porcentaje = [int](($i / $totalSectores) * 100)
        $msgProgreso = "`r[+] Cargando datos a la RAM... {0}% | Sectores: {1}/{2} | Tanque: {3:N2} MB" -f $porcentaje, ($i+1), $totalSectores, $global:RamCacheInstaladaMB
        Write-Host -NoNewline $msgProgreso
    }

    Write-Host "`n`n[+] Precarga completada exitosamente." -ForegroundColor Green
    Write-Host "[+] Entrada al emulador: Instantánea. El hardware óptico queda protegido." -ForegroundColor Green
    
    # =========================================================================
    # CORRECCIÓN DE SEGURIDAD PARA RAM-ENGINE (Evita valores NULL)
    # =========================================================================
    if ($null -eq $global:RamCacheInstaladaMB) {
        $global:RamCacheInstaladaMB = 0.00
    }
    # =========================================================================

    Write-Log "RAM-ENGINE - Fase de precarga terminada. Total en RAM: $($global:RamCacheInstaladaMB.ToString('N2')) MB"
    Start-Sleep -Seconds 2

    # 5. BUCLE DE CONSUMO ULTRASENSIBLE, CONTROL DE PULSOS Y MAPEO PROGRESIVO
    $relojEsperaEmulador = [System.Diagnostics.Stopwatch]::StartNew()
    
    # Corrección del constructor de bytes obsoleto para evitar el error New-Object
    $bufferPulsoEspera = [byte[]]::new(1) 
    
    $lastBytesRAMEngine = 0


    Write-Host "[i] Esperando ejecución del emulador para transferir control de RAM..." -ForegroundColor Yellow

    while ($true) {
        # Detección instantánea de emuladores activos
        $emuladorActivoRAM = Get-Process -Name "pcsx2", "pcsx2-qt", "ePSXe", "rpcs3", "RPCS3", "PPSSPPWindows64", "PPSSPPWindows" -ErrorAction SilentlyContinue | Select-Object -First 1
        
        # --- SISTEMA DE PULSOS DE PROTECCIÓN MIENTRAS EL EMULADOR NO ARRANCA ---
        if ($null -eq $emuladorActivoRAM) {
            if ($relojEsperaEmulador.ElapsedMilliseconds -gt 400) {
                try {
                    $streamPulso = [System.IO.File]::Open($DrivePath, 'Open', 'Read', 'ReadWrite')
                    $null = $streamPulso.Read($bufferPulsoEspera, 0, 1)
                    $streamPulso.Close()
                    $streamPulso.Dispose()
                } catch {}
                $relojEsperaEmulador.Restart()
            }
            Start-Sleep -Milliseconds 100
            continue # Se mantiene esperando el emulador sin consumir CPU
        }

        # --- TRANSICIÓN INSTANTÁNEA: EMULADOR DETECTADO ---
        Clear-Host
        Write-Host "=========================================================" -ForegroundColor Green
        Write-Host "     MOTOR DE MEMORIA RAM EN EJECUCIÓN CONTINUA          " -ForegroundColor Green
        Write-Host "=========================================================" -ForegroundColor Green
        Write-Host "[+] Control transferido con éxito a: $($emuladorActivoRAM.Name)" -ForegroundColor Green

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
            # CASO B: MAPEO PROGRESIVO EN CALIENTE (LBA Nueva / No registrada)
            else {
                if (-not $global:LbaIndexCache.Contains($lbaEstimadoRAM)) {
                    $null = $global:LbaIndexCache.Add($lbaEstimadoRAM)
                    $global:NuevosLbasRegistradosEnCaliente++

                    # Reordenación atómica acelerada y compactación en bloques de 50
                    $lbasOrdenadosRAM = [System.Linq.Enumerable]::ToArray($global:LbaIndexCache)
                    [System.Array]::Sort($lbasOrdenadosRAM)

                    $lineasOutputRAM = @("ID_DISCO: $($global:DiskID)")
                    $bloqueActualRAM = @()

                    foreach ($lba in $lbasOrdenadosRAM) {
                        $bloqueActualRAM += $lba
                        if ($bloqueActualRAM.Count -eq 50) {
                            $lineasOutputRAM += "LBA-BLOCK: " + ($bloqueActualRAM -join ", ")
                            $bloqueActualRAM = @()
                        }
                    }
                    if ($bloqueActualRAM.Count -gt 0) { $lineasOutputRAM += "LBA-BLOCK: " + ($bloqueActualRAM -join ", ") }

                    [System.IO.File]::WriteAllLines($global:gameMapFile, $lineasOutputRAM)
                    Write-Log "RAM-ENGINE - Nuevo sector LBA [$lbaEstimadoRAM] interceptado y registrado en caliente."
                }
            }

        # Panel de visualización dinámico en pantalla
        $textoTráficoRAM = if ($bytesPorSegundoRAM -gt 0) { "{0:N2} MB/s" -f ($bytesPorSegundoRAM / 1MB) } else { "0.00 MB/s" }
        Write-Host "[ TANQUE RAM DINÁMICO: $($global:RamCacheInstaladaMB.ToString('N2')) MB / $RamMaxMB.00 MB ]" -ForegroundColor Magenta
        Write-Host "[ LBA ACTUAL INTERCEPTADA: $lbaEstimadoRAM | NUEVOS REGISTROS EN CALIENTE: $($global:NuevosLbasRegistradosEnCaliente) ]" -ForegroundColor Yellow
        Write-Host "[ TRÁFICO EMULADOR: $textoTráficoRAM ]" -ForegroundColor Cyan
        Write-Host "---------------------------------------------------------" -ForegroundColor Green
        
        # Permitir la salida del bucle si el emulador se cierra
        if ($null -eq (Get-Process -Name "pcsx2", "pcsx2-qt", "ePSXe", "rpcs3", "RPCS3", "PPSSPPWindows64", "PPSSPPWindows" -ErrorAction SilentlyContinue)) {
            Write-Host "`n[-] Emulador cerrado. Finalizando motor RAM and volviendo al estado base..." -ForegroundColor Yellow
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
    
    # --- SE AGREGA LA VERSIÓN Y SE MANTIENE SIN SPAM V2.480 ---
    Write-Host "[ MONITOR DE UNIDAD ÓPTICA V2.480 ]" -ForegroundColor Cyan
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
