[CmdletBinding()]
param(
    [string]$SourceFile = '.local/foundation-3/verified/appdata/SM2/foundation/4096/survival_tissues.json',
    [string]$RuntimeRoot = '.local/checkpoint-1/scale',
    [string]$OutputDirectory = 'outputs/checkpoint-1/scale'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'find_godot.ps1')
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
try {
    $runtime = Initialize-Sm2Runtime -ProjectRoot $projectRoot -RuntimeRoot $RuntimeRoot
    $outputRoot = Initialize-Sm2Runtime -ProjectRoot $projectRoot -RuntimeRoot $OutputDirectory
    $source = [IO.Path]::GetFullPath((Join-Path $projectRoot $SourceFile))
    if (-not $source.StartsWith($projectRoot + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Source must be in SM2.' }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Historical fixture missing; run check_foundation first.' }
    $log = Join-Path $outputRoot 'checks.log'
    $report = Join-Path $outputRoot 'report.json'
    $godot = Resolve-Sm2Godot -ProjectRoot $projectRoot -GodotPath '' -LogPath $log -RuntimeRoot $runtime
    Invoke-Sm2Import -Godot $godot -ProjectRoot $projectRoot -LogPath $log -RuntimeRoot $runtime
    $result = Invoke-Sm2Process -Executable $godot -Arguments @('--headless','--path',$projectRoot,'--script','res://tools/check_checkpoint.gd','--','--source',$source,'--report',$report) -WorkingDirectory $projectRoot -LogPath $log -RuntimeRoot $runtime
    if ($result.ExitCode -ne 0 -or (Test-Sm2GodotOutput $result.Text)) { throw "Checkpoint audit failed. See $report" }
    Write-Output "Checkpoint audit passed: $report"
    exit 0
} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
