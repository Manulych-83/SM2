[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [string]$RuntimeRoot = '.local\test-runtime',
    [ValidateSet('all', 'survival', 'unit', 'integration', 'scenario', 'spatial', 'm2_content', 'm2_movement', 'turn_scheduler', 'turn_content', 'm2_snapshot', 'm2_turns', 'm2_turn_storage', 'm2_attacks', 'm2_combat_storage', 'm2_consequences', 'm2_consequence_storage', 'm2_ai', 'm4_effects', 'm4_magic', 'm4_ability_ai','m4_areas','p6_region','p5_hybrids','p5_cross_nodes','p5_implants','p5_upgrades','p5_shield','p5_growth','p5_psionics','p4_hero_screen','p4_discovery','p4_search','p4_exploration','p4_care','p4_prosthesis','p4_body','p4_party','p4_attributes','p4_journey','p3_world','p2_development','p1_progression')][string]$Suite = 'all',
    [switch]$ShowResult
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'find_godot.ps1')
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$logPath = ''
try {
    $logPath = New-Sm2LogPath $projectRoot 'checks'
    $reportPath = [System.IO.Path]::ChangeExtension($logPath, '.json')
    if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) { $RuntimeRoot = '.local\test-runtime' }
    $RuntimeRoot = Initialize-Sm2Runtime -ProjectRoot $projectRoot -RuntimeRoot $RuntimeRoot
    $godot = Resolve-Sm2Godot -ProjectRoot $projectRoot -GodotPath $GodotPath -LogPath $logPath -RuntimeRoot $RuntimeRoot
    Invoke-Sm2Import -Godot $godot -ProjectRoot $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
    $testArgs = @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_runner.gd', '--', '--suite', $Suite, '--report', $reportPath)
    $result = Invoke-Sm2Process -Executable $godot -Arguments $testArgs -WorkingDirectory $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
    if ($result.ExitCode -ne 0 -or (Test-Sm2GodotOutput $result.Text)) { throw "Проверки Godot завершились с ошибкой (код $($result.ExitCode))." }
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw 'Godot не создал отчёт. Успех не подтверждён.' }
    $report = [System.IO.File]::ReadAllText($reportPath) | ConvertFrom-Json
    # JSON may write an integer count as 2.0; accept integral numbers, never booleans/strings.
    $numericChecks = $report.checks -is [int] -or $report.checks -is [long] -or $report.checks -is [double] -or $report.checks -is [decimal]
    $validChecks = $numericChecks -and $report.checks -gt 0 -and $report.checks -le [int]::MaxValue -and [Math]::Floor([double]$report.checks) -eq $report.checks
    if ($report.passed -isnot [bool] -or -not $report.passed -or -not $validChecks -or @($report.failures).Count -ne 0 -or @($report.suites).Count -eq 0) {
        throw 'Отчёт содержит ошибки или не подтверждает выполнение проверок.'
    }
    $message = "SM2: все проверки пройдены.`nПроверок: $($report.checks). Набор: $Suite.`n`nОтчёт: $reportPath`nЖурнал: $logPath"
    Write-Output $message
    if ($ShowResult) { Show-Sm2Message $message }
    exit 0
}
catch {
    $message = "Проверка SM2 не пройдена.`n`n$($_.Exception.Message)"
    if ($logPath) {
        try { Add-Sm2Log $logPath $message; $message += "`n`nЖурнал: $logPath" }
        catch { $message += "`n`nНе удалось записать журнал: $logPath" }
    }
    [Console]::Error.WriteLine($message)
    if ($ShowResult) { Show-Sm2Message $message $true }
    exit 1
}
