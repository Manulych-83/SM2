[CmdletBinding()]
param([string]$GodotPath = '', [string]$RuntimeRoot = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'find_godot.ps1')
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$logPath = ''
try {
    $logPath = New-Sm2LogPath $projectRoot 'export'
    $RuntimeRoot = Initialize-Sm2Runtime -ProjectRoot $projectRoot -RuntimeRoot $RuntimeRoot
    $godot = Resolve-Sm2Godot -ProjectRoot $projectRoot -GodotPath $GodotPath -LogPath $logPath -RuntimeRoot $RuntimeRoot
    $presetText = [System.IO.File]::ReadAllText((Join-Path $projectRoot 'export_presets.cfg'))
    if ($presetText -notmatch '(?m)^custom_template/release="[^"]+"') {
        # The current preset needs only the standard Windows x86_64 release template.
        $templateName = 'windows_release_x86_64.exe'
        $templateDirectory = Join-Path $RuntimeRoot 'appdata\Godot\export_templates\4.7.2.stable'
        $cachedTemplate = Join-Path $templateDirectory $templateName
        $installedTemplate = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)) ('Godot\export_templates\4.7.2.stable\' + $templateName)
        if (-not (Test-Path -LiteralPath $installedTemplate -PathType Leaf)) { throw 'Не найден установленный Windows release-шаблон Godot 4.7.2. Автоматическая загрузка не выполняется.' }
        [void][System.IO.Directory]::CreateDirectory($templateDirectory)
        $sourceHash = (Get-FileHash -LiteralPath $installedTemplate -Algorithm SHA256).Hash
        if (-not (Test-Path -LiteralPath $cachedTemplate -PathType Leaf) -or (Get-FileHash -LiteralPath $cachedTemplate -Algorithm SHA256).Hash -ne $sourceHash) {
            [System.IO.File]::Copy($installedTemplate, $cachedTemplate, $true)
        }
        if ((Get-FileHash -LiteralPath $cachedTemplate -Algorithm SHA256).Hash -ne $sourceHash) { throw 'Не удалось проверить локальную копию шаблона.' }
        Add-Sm2Log $logPath ("Local release template: $cachedTemplate`nSHA256: $sourceHash")
    }
    Invoke-Sm2Import -Godot $godot -ProjectRoot $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
    $buildDirectory = Join-Path $projectRoot 'builds'
    [void][System.IO.Directory]::CreateDirectory($buildDirectory)
    $outputPath = Join-Path $buildDirectory 'SM2.exe'
    $startedUtc = [DateTime]::UtcNow
    $exportArgs = @('--headless', '--path', $projectRoot, '--export-release', 'Windows Desktop', $outputPath)
    $result = Invoke-Sm2Process -Executable $godot -Arguments $exportArgs -WorkingDirectory $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
    if ($result.ExitCode -ne 0 -or (Test-Sm2GodotOutput $result.Text)) { throw "Экспорт завершился с ошибкой (код $($result.ExitCode)). Проверьте шаблоны Godot 4.7.2." }
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw 'Godot не создал builds\SM2.exe.' }
    $build = Get-Item -LiteralPath $outputPath
    if ($build.Length -le 0 -or $build.LastWriteTimeUtc -lt $startedUtc.AddSeconds(-2)) { throw 'Новая сборка не подтверждена: файл пуст или остался от прежнего запуска.' }
    Write-Output "Сборка готова: $outputPath`nЖурнал: $logPath"
    exit 0
}
catch {
    $message = "Не удалось собрать SM2.`n`n$($_.Exception.Message)"
    if ($logPath) {
        try { Add-Sm2Log $logPath $message; $message += "`n`nЖурнал: $logPath" }
        catch { $message += "`n`nНе удалось записать журнал: $logPath" }
    }
    [Console]::Error.WriteLine($message)
    exit 1
}
