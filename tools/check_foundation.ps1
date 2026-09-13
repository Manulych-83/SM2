[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [string]$RuntimeRoot = '.local\foundation-3\runtime',
    [string]$OutputDirectory = 'outputs\foundation-3\latest'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'find_godot.ps1')
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
try {
    $RuntimeRoot = Initialize-Sm2Runtime -ProjectRoot $projectRoot -RuntimeRoot $RuntimeRoot
    $outputRoot = Initialize-Sm2Runtime -ProjectRoot $projectRoot -RuntimeRoot $OutputDirectory
    $logPath = Join-Path $outputRoot 'checks.log'
    $reportPath = Join-Path $outputRoot 'report.json'
    $godot = Resolve-Sm2Godot -ProjectRoot $projectRoot -GodotPath $GodotPath -LogPath $logPath -RuntimeRoot $RuntimeRoot
    Invoke-Sm2Import -Godot $godot -ProjectRoot $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
    $result = Invoke-Sm2Process -Executable $godot -Arguments @('--headless','--path',$projectRoot,'--script','res://tools/check_foundation.gd','--','--report',$reportPath) -WorkingDirectory $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
    if ($result.ExitCode -ne 0 -or (Test-Sm2GodotOutput $result.Text)) { throw 'Foundation audit failed. See checks.log.' }
    $report = [System.IO.File]::ReadAllText($reportPath) | ConvertFrom-Json
    if ($report.passed -isnot [bool] -or -not $report.passed -or @($report.metrics).Count -eq 0 -or @($report.failures).Count -ne 0) { throw 'Invalid or failed audit report.' }
    Write-Output "Audit completed. Large campaign ready: $($report.ready_for_large_campaign). Blockers: $(@($report.blockers).Count). Report: $reportPath"
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
