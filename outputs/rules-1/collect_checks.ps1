$ErrorActionPreference = 'Stop'
$taskProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskSuites = @('rules','m4_effects','m2_attacks','m4_magic','m4_areas','m4_ability_ai','combat_hud','combat_profile','after_battle','unit','content_packages','campaigns','integration','skill_scale')
$taskCandidates = @()
foreach ($taskFile in Get-ChildItem -LiteralPath (Join-Path $taskProject '.local/logs') -Filter 'checks-20260913-14*.json') {
    $taskLog = [IO.Path]::ChangeExtension($taskFile.FullName,'.log')
    if (-not [IO.File]::ReadAllText($taskLog).Contains('\.local\rules-1\')) { continue }
    $taskReport = [IO.File]::ReadAllText($taskFile.FullName) | ConvertFrom-Json
    if ($taskReport.passed -ne $true -or @($taskReport.failures).Count -ne 0 -or $taskReport.checks -le 0) { continue }
    $taskCandidates += [pscustomobject]@{file=$taskFile; report=$taskReport; log=$taskLog}
}
[void][IO.Directory]::CreateDirectory((Join-Path $PSScriptRoot 'core'))
$taskRows = @()
foreach ($taskSuite in $taskSuites) {
    $taskMatch = $taskCandidates | Where-Object { $taskSuite -in $_.report.suites } | Sort-Object { $_.file.LastWriteTimeUtc } -Descending | Select-Object -First 1
    if (-not $taskMatch) { throw "Missing successful suite: $taskSuite" }
    Copy-Item -LiteralPath $taskMatch.file.FullName -Destination (Join-Path $PSScriptRoot ('core/'+$taskSuite+'.json'))
    Copy-Item -LiteralPath $taskMatch.log -Destination (Join-Path $PSScriptRoot ('core/'+$taskSuite+'.log'))
    $taskRows += @{suite=$taskSuite;checks=[int]$taskMatch.report.checks;passed=$true;report=('core/'+$taskSuite+'.json')}
}
$taskUi = @()
foreach ($taskSuite in @('ui-final','ui-m4','ui-combat_hud')) {
    $taskReport = Get-Content -LiteralPath (Join-Path $PSScriptRoot ($taskSuite+'/report.json')) -Raw | ConvertFrom-Json
    if ($taskReport.passed -ne $true -or $taskReport.rendered -ne $true -or @($taskReport.failures).Count -ne 0 -or $taskReport.checks -le 0) { throw "Invalid UI result: $taskSuite" }
    $taskUi += @{suite=$taskSuite;checks=[int]$taskReport.checks;passed=$true;rendered=$true;report=($taskSuite+'/report.json')}
}
@{passed=$true;core=$taskRows;core_checks=($taskRows | Measure-Object -Property checks -Sum).Sum;ui=$taskUi;ui_checks=($taskUi | Measure-Object -Property checks -Sum).Sum} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'checks.json')
