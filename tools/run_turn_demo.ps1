[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [string]$RuntimeRoot = '.local\turn-demo-runtime'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'find_godot.ps1')
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
try {
    if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) { $RuntimeRoot = '.local\turn-demo-runtime' }
    $RuntimeRoot = Initialize-Sm2Runtime -ProjectRoot $projectRoot -RuntimeRoot $RuntimeRoot
    $logPath = New-Sm2LogPath $projectRoot 'turn-demo'
    $reportPath = [IO.Path]::ChangeExtension($logPath, '.json')
    $godot = Resolve-Sm2Godot -ProjectRoot $projectRoot -GodotPath $GodotPath -LogPath $logPath -RuntimeRoot $RuntimeRoot
    Invoke-Sm2Import -Godot $godot -ProjectRoot $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
    $arguments = @('--headless', '--path', $projectRoot, '--script', 'res://tests/scenarios/m2_turn_demo.gd', '--', '--report', $reportPath)
    $result = Invoke-Sm2Process -Executable $godot -Arguments $arguments -WorkingDirectory $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
    if ($result.ExitCode -ne 0 -or (Test-Sm2GodotOutput $result.Text)) { throw "Прогон очереди завершился с ошибкой: $($result.ExitCode). Журнал: $logPath" }
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw 'Отчёт прогона очереди не создан.' }
    $report = [IO.File]::ReadAllText($reportPath) | ConvertFrom-Json
    if ($report.passed -isnot [bool] -or -not $report.passed -or @($report.commands).Count -ne 8 -or @($report.errors).Count -ne 0) { throw 'Отчёт не подтверждает успешный прогон очереди.' }
    if ($report.save_reload_equal -isnot [bool] -or -not $report.save_reload_equal -or
        $report.continuation_equal -isnot [bool] -or -not $report.continuation_equal -or
        $report.m1_slot_unchanged -isnot [bool] -or -not $report.m1_slot_unchanged) { throw 'Сохранение и продолжение очереди не совпали с непрерывным прогоном.' }
    Write-Output "M2.2: выполнены восемь команд, очередь после Wait сохранена и загружена; события и состояние продолжения совпали."
    Write-Output "Это диагностический прогон очереди, ещё без атак и игрового поля в окне."
    Write-Output "Отчёт: $reportPath"
    Write-Output "Журнал: $logPath"
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
