<#
save-sync: sincroniza partidas guardadas de juegos sin nube propia entre
varios ordenadores Windows usando una carpeta de OneDrive, Google Drive o Dropbox.

- La lista de juegos (games.json) vive en la nube: un juego añadido en un PC
  aparece en todos.
- Cada PC guarda su propia ruta para cada juego.
- La carpeta de guardado se mueve a la nube y en su sitio queda un enlace
  (junction). El juego cree que guarda en local.

Uso:
  save-sync.ps1                      menú interactivo
  save-sync.ps1 add [ruta] [nombre]  añade un juego desde este PC
  save-sync.ps1 sync [-Quiet]        enlaza en este PC todos los juegos de la lista
  save-sync.ps1 status               estado de cada juego en este PC
  save-sync.ps1 unlink [nombre]      deshace el enlace en este PC (deja copia local)
  save-sync.ps1 autostart on|off     sincronizar al iniciar Windows
#>
param(
    [Parameter(Position = 0)][string]$Command = "menu",
    [Parameter(Position = 1)][string]$Arg1,
    [Parameter(Position = 2)][string]$Arg2,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$PC = $env:COMPUTERNAME
$SettingsDir = Join-Path $env:APPDATA "save-sync"
$SettingsFile = Join-Path $SettingsDir "settings.json"

# ------------------------------------------------------------------ salida

function Say([string]$msg, [string]$color = "Gray") {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $color }
}
function Log([string]$msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    try { Add-Content -Path (Join-Path $SettingsDir "save-sync.log") -Value $line -Encoding UTF8 } catch {}
}

# ------------------------------------------------------------------ rutas

# Convierte C:\Users\X\AppData\Roaming\Juego en %APPDATA%\Juego, para que la
# misma ruta sirva en otro PC con otro nombre de usuario.
function To-Portable([string]$path) {
    $full = [IO.Path]::GetFullPath($path).TrimEnd('\')
    foreach ($var in "LOCALAPPDATA", "APPDATA", "USERPROFILE") {
        $base = [Environment]::GetEnvironmentVariable($var)
        if ($base -and $full.StartsWith($base.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return "%$var%" + $full.Substring($base.TrimEnd('\').Length)
        }
    }
    return $full
}
function From-Portable([string]$path) {
    return [Environment]::ExpandEnvironmentVariables($path).TrimEnd('\')
}

function Pick-Folder([string]$description) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $description
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return $null
}

# ------------------------------------------------------------------ ajustes de este PC

function Get-CloudDir {
    if (Test-Path $SettingsFile) {
        $s = Get-Content $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($s.cloudDir) { return $s.cloudDir }
    }
    $default = $null
    $od = $env:OneDrive
    if (-not ($od -and (Test-Path $od))) { $od = Join-Path $env:USERPROFILE "OneDrive" }
    if (Test-Path $od) { $default = Join-Path $od "SaveSync" }

    if ($Quiet) {
        if (-not $default) { throw "No hay carpeta de nube configurada. Abre save-sync una vez a mano." }
        $dir = $default
    } else {
        if ($default) {
            Say "Carpeta de nube detectada: $default" Cyan
            $ans = Read-Host "¿Usar esta? (S/n)"
            if ($ans -match '^[nN]') { $default = $null }
        }
        if ($default) { $dir = $default }
        else {
            $picked = Pick-Folder "Elige una carpeta que se sincronice con la nube (OneDrive, Google Drive, Dropbox)"
            if (-not $picked) { throw "No se eligió carpeta de nube." }
            $dir = Join-Path $picked "SaveSync"
        }
    }
    New-Item -ItemType Directory -Force -Path $SettingsDir | Out-Null
    @{ cloudDir = $dir } | ConvertTo-Json | Set-Content $SettingsFile -Encoding UTF8
    return $dir
}

# ------------------------------------------------------------------ lista de juegos (en la nube)

function Load-Games([string]$cloud) {
    $file = Join-Path $cloud "games.json"
    $games = [ordered]@{}
    if (Test-Path $file) {
        $data = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($g in $data.games) {
            $paths = [ordered]@{}
            foreach ($p in $g.paths.PSObject.Properties) { $paths[$p.Name] = $p.Value }
            $games[$g.name] = $paths
        }
    }
    return $games
}

function Save-Games([string]$cloud, $games) {
    New-Item -ItemType Directory -Force -Path $cloud | Out-Null
    $list = @()
    foreach ($name in $games.Keys) { $list += [ordered]@{ name = $name; paths = $games[$name] } }
    $json = [ordered]@{ games = $list } | ConvertTo-Json -Depth 5
    Set-Content -Path (Join-Path $cloud "games.json") -Value $json -Encoding UTF8
}

# Ruta del juego en este PC: la suya si la tiene; si no, la de otro PC
# (sirve si el juego guarda en %APPDATA% o similar).
function Resolve-LocalPath($paths) {
    if ($paths.Contains($PC)) { return From-Portable $paths[$PC] }
    foreach ($k in $paths.Keys) {
        if ($paths[$k] -like "%*") { return From-Portable $paths[$k] }
    }
    # Ruta absoluta de otro PC (p. ej. D:\Juegos\X): solo si aquí existe esa carpeta padre
    foreach ($k in $paths.Keys) {
        $p = From-Portable $paths[$k]
        if (Test-Path -LiteralPath (Split-Path $p -Parent)) { return $p }
    }
    return $null
}

# ------------------------------------------------------------------ enlaces

function Get-JunctionTarget([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $item = Get-Item -LiteralPath $path -Force
    if ($item.LinkType -in "Junction", "SymbolicLink") {
        return (@($item.Target)[0]).TrimEnd('\')
    }
    return $null
}

function Same-Path([string]$a, [string]$b) {
    return [string]::Equals($a.TrimEnd('\').Replace('\\?\', ''), $b.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
}

function Has-Files([string]$dir) {
    return (Test-Path $dir) -and ($null -ne (Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1))
}

function Move-Folder([string]$src, [string]$dst) {
    # robocopy funciona también entre discos distintos
    & robocopy $src $dst /E /MOVE /COPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy falló moviendo $src (código $LASTEXITCODE)" }
    if (Test-Path -LiteralPath $src) { Remove-Item -LiteralPath $src -Recurse -Force }
}

function Pin-Offline([string]$dir) {
    # OneDrive: "Mantener siempre en este dispositivo"
    & attrib +P -U "$dir" /S /D 2>$null | Out-Null
}

function Sync-Game([string]$name, $paths, [string]$cloud) {
    $local = Resolve-LocalPath $paths
    $target = Join-Path (Join-Path $cloud "Partidas") $name
    if (-not $local) { Say "[--]     $name : sin ruta para este PC (añádelo desde aquí)" DarkGray; return }

    $link = Get-JunctionTarget $local
    if ($link) {
        if (Same-Path $link $target) { Say "[OK]     $name : ya enlazado" Green; return }
        Say "[AVISO]  $name : $local ya es un enlace a $link. No lo toco." Yellow; return
    }

    $parent = Split-Path $local -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        Say "[--]     $name : no instalado en este PC ($parent no existe)" DarkGray; return
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    if (Test-Path -LiteralPath $local) {
        if (Has-Files $target) {
            # La nube ya tiene partidas: mandan las de la nube, lo local se guarda aparte.
            $backup = "$local.backup-$stamp"
            Rename-Item -LiteralPath $local -NewName (Split-Path $backup -Leaf)
            Say "[COPIA]  $name : partidas locales guardadas en $backup" Yellow
            Log "$name : backup local en $backup"
        } else {
            New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
            Move-Folder $local $target
            Say "[SUBIDO] $name : partidas movidas a la nube" Cyan
            Log "$name : partidas movidas a $target"
        }
    }
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    New-Item -ItemType Junction -Path $local -Target $target | Out-Null
    Pin-Offline $target
    Say "[OK]     $name : $local -> nube" Green
    Log "$name : enlazado $local -> $target"
}

# ------------------------------------------------------------------ comandos

function Cmd-Add([string]$path, [string]$name) {
    $cloud = Get-CloudDir
    if (-not $path) {
        $path = Pick-Folder "Elige la carpeta donde el juego guarda las partidas"
        if (-not $path) { Say "Cancelado." Yellow; return }
    }
    $path = [IO.Path]::GetFullPath($path).TrimEnd('\')
    if (Get-JunctionTarget $path) { throw "Esa carpeta ya es un enlace. Elige la carpeta real de partidas." }

    $games = Load-Games $cloud
    if (-not $name) {
        $suggest = Split-Path $path -Leaf
        if ($games.Count -gt 0) {
            Say "`nJuegos ya en la lista: $($games.Keys -join ', ')" Gray
            Say "Si es uno de esos, escribe el mismo nombre para añadir la ruta de este PC." Gray
        }
        $name = Read-Host "Nombre del juego [$suggest]"
        if (-not $name) { $name = $suggest }
    }
    $name = ($name -replace '[\\/:*?"<>|]', '').Trim()

    if (-not $games.Contains($name)) { $games[$name] = [ordered]@{} }
    $games[$name][$PC] = To-Portable $path
    Save-Games $cloud $games
    Say "Añadido '$name' para $PC." Cyan
    Sync-Game $name $games[$name] $cloud
}

function Cmd-Sync {
    $cloud = Get-CloudDir
    $games = Load-Games $cloud
    if ($games.Count -eq 0) { Say "La lista está vacía. Añade un juego primero." Yellow; return }
    foreach ($name in $games.Keys) {
        try { Sync-Game $name $games[$name] $cloud }
        catch { Say "[ERROR]  $name : $($_.Exception.Message)" Red; Log "$name : ERROR $($_.Exception.Message)" }
    }
}

function Cmd-Status {
    $cloud = Get-CloudDir
    Say "Nube: $cloud   |   Este PC: $PC`n" Cyan
    $games = Load-Games $cloud
    if ($games.Count -eq 0) { Say "No hay juegos en la lista." Yellow; return }
    foreach ($name in $games.Keys) {
        $local = Resolve-LocalPath $games[$name]
        $target = Join-Path (Join-Path $cloud "Partidas") $name
        $link = if ($local) { Get-JunctionTarget $local } else { $null }
        if ($link -and (Same-Path $link $target)) {
            $last = Get-ChildItem -LiteralPath $target -Recurse -File -Force -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $when = if ($last) { $last.LastWriteTime.ToString("dd/MM/yyyy HH:mm") } else { "vacío" }
            $state = "enlazado  (último guardado $when)"; $color = "Green"
        } elseif (-not $local) { $state = "sin ruta en este PC"; $color = "DarkGray" }
        elseif ($link) { $state = "enlace a otra carpeta"; $color = "Yellow" }
        elseif (Test-Path -LiteralPath $local) { $state = "sin enlazar (pulsa Sincronizar)"; $color = "Yellow" }
        else { $state = "no instalado en este PC"; $color = "DarkGray" }
        Say ("{0,-28} {1}" -f $name, $state) $color
        Say ("{0,-28} {1}" -f "", ($games[$name].Keys -join ', ')) DarkGray
    }
}

function Cmd-Unlink([string]$only) {
    $cloud = Get-CloudDir
    $games = Load-Games $cloud
    foreach ($name in $games.Keys) {
        if ($only -and $name -ne $only) { continue }
        $local = Resolve-LocalPath $games[$name]
        $target = Join-Path (Join-Path $cloud "Partidas") $name
        $link = if ($local) { Get-JunctionTarget $local } else { $null }
        if (-not ($link -and (Same-Path $link $target))) { continue }
        & cmd /c rmdir "$local"   # borra solo el enlace, nunca las partidas
        & robocopy $target $local /E /COPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        Say "[OK]     $name : copia local restaurada en $local" Green
        Log "$name : desenlazado"
    }
}

function Cmd-Autostart([string]$mode) {
    $startup = [Environment]::GetFolderPath("Startup")
    $lnk = Join-Path $startup "save-sync.lnk"
    if ($mode -eq "off") {
        if (Test-Path $lnk) { Remove-Item $lnk }
        Say "Sincronización al iniciar Windows: desactivada." Yellow
        return
    }
    $null = Get-CloudDir   # deja la nube configurada antes
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($lnk)
    $s.TargetPath = "powershell.exe"
    $s.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" sync -Quiet"
    $s.WindowStyle = 7
    $s.Save()
    Say "Sincronización al iniciar Windows: activada." Green
}

function Show-Menu {
    while ($true) {
        Write-Host ""
        Write-Host "=========== save-sync ($PC) ===========" -ForegroundColor Cyan
        Write-Host " 1. Añadir juego"
        Write-Host " 2. Sincronizar este PC"
        Write-Host " 3. Ver estado"
        Write-Host " 4. Sincronizar automáticamente al iniciar Windows"
        Write-Host " 5. Deshacer enlace de un juego"
        Write-Host " 0. Salir"
        $op = Read-Host "Opción"
        try {
            switch ($op) {
                "1" { Cmd-Add $null $null }
                "2" { Cmd-Sync }
                "3" { Cmd-Status }
                "4" { Cmd-Autostart "on" }
                "5" { $n = Read-Host "Nombre del juego"; Cmd-Unlink $n }
                "0" { return }
            }
        } catch { Say "[ERROR] $($_.Exception.Message)" Red }
    }
}

New-Item -ItemType Directory -Force -Path $SettingsDir | Out-Null
try {
    switch ($Command.ToLower()) {
        "menu"      { Show-Menu }
        "add"       { Cmd-Add $Arg1 $Arg2 }
        "sync"      { Cmd-Sync }
        "status"    { Cmd-Status }
        "unlink"    { Cmd-Unlink $Arg1 }
        "autostart" { Cmd-Autostart $(if ($Arg1) { $Arg1 } else { "on" }) }
        default     { Say "Comando desconocido: $Command" Red; exit 1 }
    }
} catch {
    Say "[ERROR] $($_.Exception.Message)" Red
    Log "ERROR $($_.Exception.Message)"
    exit 1
}
