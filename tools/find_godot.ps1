# Shared Windows helpers. Compatible with Windows PowerShell 5.1.

function Initialize-Sm2Runtime {
    param([string]$ProjectRoot, [string]$RuntimeRoot = '')
    $project = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
    if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) { $RuntimeRoot = '.local\runtime' }
    if (-not [System.IO.Path]::IsPathRooted($RuntimeRoot)) { $RuntimeRoot = Join-Path $project $RuntimeRoot }
    $resolved = [System.IO.Path]::GetFullPath($RuntimeRoot).TrimEnd('\', '/')
    if (-not $resolved.StartsWith($project + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'RuntimeRoot должен находиться внутри папки проекта.'
    }
    foreach ($suffix in @('', 'appdata', 'cache', 'temp')) {
        $directory = if ($suffix) { Join-Path $resolved $suffix } else { $resolved }
        $cursor = $directory
        while ($cursor.Length -gt $project.Length) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
            if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { throw "RuntimeRoot проходит через символическую ссылку: $cursor" }
            $cursor = [System.IO.Path]::GetDirectoryName($cursor)
        }
        [void][System.IO.Directory]::CreateDirectory($directory)
    }
    return $resolved
}

function ConvertTo-Sm2ProcessArgument {
    param([AllowEmptyString()][string]$Value)
    # CommandLineToArgvW quoting; also handles spaces, quotes and trailing slashes.
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $quoted = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $quoted = [regex]::Replace($quoted, '(\\+)$', '$1$1')
    return '"' + $quoted + '"'
}

function New-Sm2LogPath {
    param([string]$ProjectRoot, [string]$Kind)
    $directory = Join-Path $ProjectRoot '.local\logs'
    [void][System.IO.Directory]::CreateDirectory($directory)
    $name = '{0}-{1}-{2}.log' -f $Kind, (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    return Join-Path $directory $name
}

function Add-Sm2Log {
    param([string]$Path, [string]$Text)
    [System.IO.File]::AppendAllText($Path, $Text + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($true))
}

function Invoke-Sm2Process {
    param([string]$Executable, [string[]]$Arguments, [string]$WorkingDirectory, [string]$LogPath, [string]$RuntimeRoot)
    if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) { throw 'Для дочернего процесса требуется проверенный RuntimeRoot.' }
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = (($Arguments | ForEach-Object { ConvertTo-Sm2ProcessArgument $_ }) -join ' ')
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    $info.EnvironmentVariables['APPDATA'] = Join-Path $RuntimeRoot 'appdata'
    $info.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $RuntimeRoot 'cache'
    $info.EnvironmentVariables['TEMP'] = Join-Path $RuntimeRoot 'temp'
    $info.EnvironmentVariables['TMP'] = Join-Path $RuntimeRoot 'temp'
    if ($LogPath) { Add-Sm2Log $LogPath ("[{0}] {1} {2}`nRuntimeRoot: {3}" -f (Get-Date -Format o), $Executable, $info.Arguments, $RuntimeRoot) }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $started = $false
    try {
        if (-not $process.Start()) { throw 'Не удалось запустить Godot.' }
        $started = $true
        # Read both pipes concurrently: large import errors cannot deadlock the launcher.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $result = [pscustomobject]@{ ExitCode = $process.ExitCode; Text = ($stdout + "`n" + $stderr) }
        if ($LogPath) { Add-Sm2Log $LogPath ($result.Text + "`nExitCode: " + $result.ExitCode) }
        return $result
    }
    finally {
        # Never launch and forget an unowned helper/game process.
        if ($started -and -not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit()
        }
        $process.Dispose()
    }
}

function Test-Sm2GodotOutput {
    param([string]$Text)
    return $Text -match '(?im)^\s*(?:SCRIPT ERROR:|ERROR:|Parse Error:|Fatal Error:|Unhandled exception|CrashHandler:)'
}

function Resolve-Sm2Godot {
    param([string]$ProjectRoot, [string]$GodotPath = '', [string]$LogPath = '', [string]$RuntimeRoot = '')
    $RuntimeRoot = Initialize-Sm2Runtime -ProjectRoot $ProjectRoot -RuntimeRoot $RuntimeRoot
    $candidatePaths = New-Object 'System.Collections.Generic.List[string]'
    $explicitChoice = $false
    if ($GodotPath) {
        $candidatePaths.Add($GodotPath)
        $explicitChoice = $true
    }
    else {
        $configPath = Join-Path $ProjectRoot '.local\godot.path'
        if (Test-Path -LiteralPath $configPath -PathType Leaf) {
            $configured = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8).Trim().Trim('"')
            if (-not $configured) { throw "Файл $configPath пуст. Укажите в нём путь к Godot 4.7.2." }
            $candidatePaths.Add($configured)
            $explicitChoice = $true
        }
        elseif ($env:GODOT_BIN) {
            $candidatePaths.Add($env:GODOT_BIN.Trim().Trim('"'))
            $explicitChoice = $true
        }
        else {
            $wingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
            if (Test-Path -LiteralPath $wingetRoot -PathType Container) {
                $packages = @(Get-ChildItem -LiteralPath $wingetRoot -Directory -Filter 'GodotEngine.GodotEngine_*' -ErrorAction SilentlyContinue)
                foreach ($package in $packages) {
                    foreach ($file in @(Get-ChildItem -LiteralPath $package.FullName -File -Filter '*4.7.2*win64.exe' -Recurse -ErrorAction SilentlyContinue)) {
                        $candidatePaths.Add($file.FullName)
                    }
                }
            }
            foreach ($name in @('godot.exe', 'godot4.exe', 'godot', 'godot4')) {
                $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($command) { $candidatePaths.Add($command.Source) }
            }
        }
    }
    foreach ($candidate in $candidatePaths) {
        $path = $candidate
        if (-not [System.IO.Path]::IsPathRooted($path)) { $path = Join-Path $ProjectRoot $path }
        $path = [System.IO.Path]::GetFullPath($path)
        # The console .exe is a wrapper. Own the actual Godot process for both GUI and headless runs.
        if ($path -match '_console\.exe$') {
            $mainPath = $path -replace '_console\.exe$', '.exe'
            if (Test-Path -LiteralPath $mainPath -PathType Leaf) { $path = $mainPath }
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            if ($explicitChoice) { throw "Godot не найден: $path" }
            continue
        }
        $version = Invoke-Sm2Process -Executable $path -Arguments @('--version') -WorkingDirectory $ProjectRoot -LogPath $LogPath -RuntimeRoot $RuntimeRoot
        if ($version.ExitCode -eq 0 -and $version.Text.Trim() -match '^4\.7\.2\.stable\.' -and $version.Text -notmatch '\.mono\.') {
            return $path
        }
        if ($explicitChoice) { throw "Нужен стандартный Godot 4.7.2 stable. Ответ выбранного файла: $($version.Text.Trim())" }
    }
    throw "Godot 4.7.2 не найден. Укажите путь к установленному Godot в файле .local\godot.path или переменной GODOT_BIN. Автоматическая загрузка не выполняется."
}

function Invoke-Sm2Import {
    param([string]$Godot, [string]$ProjectRoot, [string]$LogPath, [string]$RuntimeRoot)
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'project.godot') -PathType Leaf)) { throw 'В папке проекта отсутствует project.godot.' }
    $result = Invoke-Sm2Process -Executable $Godot -Arguments @('--headless', '--path', $ProjectRoot, '--editor', '--import') -WorkingDirectory $ProjectRoot -LogPath $LogPath -RuntimeRoot $RuntimeRoot
    if ($result.ExitCode -ne 0 -or (Test-Sm2GodotOutput $result.Text)) {
        throw "Подготовка проекта завершилась с ошибкой (код $($result.ExitCode)). Игра не запущена."
    }
}

function Show-Sm2Message {
    param([string]$Message, [bool]$Failure = $false)
    Add-Type -AssemblyName System.Windows.Forms
    $icon = if ($Failure) { [System.Windows.Forms.MessageBoxIcon]::Error } else { [System.Windows.Forms.MessageBoxIcon]::Information }
    [void][System.Windows.Forms.MessageBox]::Show($Message, 'SM2', [System.Windows.Forms.MessageBoxButtons]::OK, $icon)
}
