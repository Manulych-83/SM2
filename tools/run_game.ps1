[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [string]$RuntimeRoot = '',
    [switch]$PrepareOnly,
    [switch]$NoDialogs,
    [switch]$LegacyDemos,
    [string[]]$ExtraArguments = @()
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'find_godot.ps1')
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$logPath = ''
$env:SM2_LEGACY_DEMOS = if ($LegacyDemos) { '1' } else { '0' }
try {
    $logPath = New-Sm2LogPath $projectRoot 'launch'
    $RuntimeRoot = Initialize-Sm2Runtime -ProjectRoot $projectRoot -RuntimeRoot $RuntimeRoot
    $godot = Resolve-Sm2Godot -ProjectRoot $projectRoot -GodotPath $GodotPath -LogPath $logPath -RuntimeRoot $RuntimeRoot
    Invoke-Sm2Import -Godot $godot -ProjectRoot $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
    if (-not $PrepareOnly) {
        $gameLog = [System.IO.Path]::ChangeExtension($logPath, '.game.log')
        $gameArgs = @('--path', $projectRoot, '--log-file', $gameLog) + $ExtraArguments
        $result = Invoke-Sm2Process -Executable $godot -Arguments $gameArgs -WorkingDirectory $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
        $engineText = ''
        if (Test-Path -LiteralPath $gameLog -PathType Leaf) { $engineText = [System.IO.File]::ReadAllText($gameLog) }
        if ($result.ExitCode -ne 0 -or (Test-Sm2GodotOutput ($result.Text + "`n" + $engineText))) {
            throw "Игра завершилась с ошибкой (код $($result.ExitCode))."
        }
    }
    Write-Output "SM2: подготовка и запуск завершены успешно. Журнал: $logPath"
    exit 0
}
catch {
    $message = "Не удалось запустить SM2.`n`n$($_.Exception.Message)"
    if ($logPath) {
        try { Add-Sm2Log $logPath $message; $message += "`n`nЖурнал: $logPath" }
        catch { $message += "`n`nНе удалось записать журнал: $logPath" }
    }
    [Console]::Error.WriteLine($message)
    if (-not $NoDialogs -and -not $PrepareOnly) { Show-Sm2Message $message $true }
    exit 1
}
