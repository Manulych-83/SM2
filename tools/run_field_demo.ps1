[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [string]$RuntimeRoot = '.local\field-demo-runtime'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'find_godot.ps1')
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
try {
    if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) { $RuntimeRoot = '.local\field-demo-runtime' }
    $RuntimeRoot = Initialize-Sm2Runtime -ProjectRoot $projectRoot -RuntimeRoot $RuntimeRoot
    $logPath = New-Sm2LogPath $projectRoot 'field-demo'
    $reportPath = [IO.Path]::ChangeExtension($logPath, '.json')
    $godot = Resolve-Sm2Godot -ProjectRoot $projectRoot -GodotPath $GodotPath -LogPath $logPath -RuntimeRoot $RuntimeRoot
    Invoke-Sm2Import -Godot $godot -ProjectRoot $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
    $arguments = @('--headless', '--path', $projectRoot, '--script', 'res://tests/scenarios/m2_field_demo.gd', '--', '--report', $reportPath)
    $result = Invoke-Sm2Process -Executable $godot -Arguments $arguments -WorkingDirectory $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
    if ($result.ExitCode -ne 0 -or (Test-Sm2GodotOutput $result.Text)) { throw "Прогон поля завершился с ошибкой: $($result.ExitCode). Журнал: $logPath" }
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw 'Отчёт прогона не создан.' }
    $report = [IO.File]::ReadAllText($reportPath) | ConvertFrom-Json
    if ($report.passed -isnot [bool] -or -not $report.passed -or @($report.commands).Count -ne 3 -or @($report.errors).Count -ne 0) { throw 'Отчёт не подтверждает успешный прогон поля.' }
    Write-Output "M2.1: выполнены три перемещения, ошибочный шаг отклонён без изменения состояния. Это проверка поля, не полный бой."
    Write-Output "Отчёт: $reportPath"
    Write-Output "Журнал: $logPath"
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
