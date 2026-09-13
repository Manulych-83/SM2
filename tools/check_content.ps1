[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [string]$RuntimeRoot = '.local\content-audit',
    [string]$OutputDirectory = 'outputs\content-audit',
    [string]$ProgressionFile = '',
    [string]$ItemManifestFile = '',
    [string]$ProgressionManifestFile = ''
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
    $arguments = @('--headless','--path',$projectRoot,'--script','res://tools/check_content.gd','--','--report',$reportPath)
    if (@(@($ProgressionFile,$ItemManifestFile,$ProgressionManifestFile) | Where-Object { $_ }).Count -gt 1) { throw 'Choose one content input.' }
    if ($ProgressionManifestFile) {
        $manifestPath = [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($ProgressionManifestFile)) { $ProgressionManifestFile } else { Join-Path $projectRoot $ProgressionManifestFile }))
        $contentPrefix = (Join-Path $projectRoot 'content') + '\'
        if (-not $manifestPath.StartsWith($contentPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Progression manifest must be inside content.' }
        $arguments += @('--progress-packages', ('res://' + $manifestPath.Substring($projectRoot.Length + 1).Replace('\','/')))
    }
    if ($ItemManifestFile) {
        $manifestPath = [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($ItemManifestFile)) { $ItemManifestFile } else { Join-Path $projectRoot $ItemManifestFile }))
        $contentPrefix = (Join-Path $projectRoot 'content') + '\'
        if (-not $manifestPath.StartsWith($contentPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Item manifest must be inside content.' }
        $relative = $manifestPath.Substring($projectRoot.Length + 1).Replace('\','/')
        $arguments += @('--items', ('res://' + $relative))
    }
    if ($ProgressionFile) {
        $sourcePath = [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($ProgressionFile)) { $ProgressionFile } else { Join-Path $projectRoot $ProgressionFile }))
        if (-not $sourcePath.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Content file must be inside SM2.' }
        $arguments += @('--progression',$sourcePath)
    }
    $godot = Resolve-Sm2Godot -ProjectRoot $projectRoot -GodotPath $GodotPath -LogPath $logPath -RuntimeRoot $RuntimeRoot
    Invoke-Sm2Import -Godot $godot -ProjectRoot $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
    $result = Invoke-Sm2Process -Executable $godot -Arguments $arguments -WorkingDirectory $projectRoot -LogPath $logPath -RuntimeRoot $RuntimeRoot
    if ($result.ExitCode -ne 0 -or (Test-Sm2GodotOutput $result.Text)) { throw "Content rejected or checker failed. Report: $reportPath" }
    $report = [System.IO.File]::ReadAllText($reportPath) | ConvertFrom-Json
    if ($report.ok -isnot [bool] -or -not $report.ok) { throw 'Report does not confirm valid content.' }
    Write-Output "Content validated. Report: $reportPath"
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
