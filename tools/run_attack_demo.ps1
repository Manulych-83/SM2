[CmdletBinding()]
param([string]$GodotPath = '', [string]$RuntimeRoot = '.local\attack-demo-runtime')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'find_godot.ps1')
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
try {
    if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) { $RuntimeRoot = '.local\attack-demo-runtime' }
    $RuntimeRoot = Initialize-Sm2Runtime -ProjectRoot $projectRoot -RuntimeRoot $RuntimeRoot
    $logPath = New-Sm2LogPath $projectRoot 'attack-demo'
    $reportPath = [IO.Path]::ChangeExtension($logPath, '.json')
    $godot = Resolve-Sm2Godot -ProjectRoot $projectRoot -GodotPath $GodotPath -LogPath $logPath -RuntimeRoot $RuntimeRoot
    Invoke-Sm2Import -Godot $godot -ProjectRoot $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
    $result = Invoke-Sm2Process -Executable $godot -Arguments @('--headless','--path',$projectRoot,'--script','res://tests/scenarios/m2_attack_demo.gd','--','--report',$reportPath) -WorkingDirectory $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
    if ($result.ExitCode -ne 0 -or (Test-Sm2GodotOutput $result.Text)) { throw "Прогон атаки завершился с ошибкой. Журнал: $logPath" }
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw 'Отчёт не создан.' }
    $report = [IO.File]::ReadAllText($reportPath) | ConvertFrom-Json
    if ($report.passed -isnot [bool] -or -not $report.passed -or @($report.errors).Count -ne 0 -or @($report.commands).Count -ne 9 -or @($report.cases).Count -ne 3) { throw 'Неполный или неуспешный прогон.' }
    foreach ($case in $report.cases) {
        foreach ($flag in @('save_reload_equal','continuation_equal','m1_slot_unchanged')) {
            if ($case.$flag -isnot [bool] -or -not $case.$flag) { throw "Не подтверждено $flag для $($case.name)." }
        }
    }
    Write-Output "M2.3: три сценария, девять команд; атаки, разрушение щита и продолжение сохранений проверены."
    Write-Output "Отчёт: $reportPath"
    Write-Output "Журнал: $logPath"
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
