[CmdletBinding()]
param([string]$GodotPath = '', [string]$RuntimeRoot = '', [string]$OutputDirectory = '', [ValidateSet('controls','settings','journal','soul','battle_results','campaigns','start_menu','camp_layout','development_layout','inventory_layout','display','journey_guide','combat_hud','battle_feedback','battle_art','survival_workspace','survival_tissues','survival_devices','survival','p6_region','p5_hybrids','p5_cross_nodes','p5_menu','p5_implants','p5_upgrades','p5_shield','p5_growth','p5_psionics','p4_hero_screen','p4_discovery','p4_search','p4_exploration','p4_care','p4_prosthesis','p4_body','p4_party','p4_attributes','p4','p3','p2','p1','m4_areas','m4_ai','m4_magic','m4','m3','m1')][string]$Suite = 'm3', [switch]$Headless)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'find_godot.ps1')
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
try {
    if (-not $RuntimeRoot) { $RuntimeRoot = '.local\ui-checks\' + $stamp }
    $runtime = Initialize-Sm2Runtime -ProjectRoot $projectRoot -RuntimeRoot $RuntimeRoot
    if (-not $OutputDirectory) { $OutputDirectory = '.local\ui-reports\' + $stamp }
    $outputPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
    if (-not $outputPath.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'UI output must stay inside the project.' }
    if (Test-Path -LiteralPath (Join-Path $outputPath 'report.json')) { throw 'Use a fresh output directory for each acceptance run.' }
    [void][IO.Directory]::CreateDirectory($outputPath)
    $logPath = New-Sm2LogPath $projectRoot 'ui-checks'
    $godot = Resolve-Sm2Godot -ProjectRoot $projectRoot -GodotPath $GodotPath -LogPath $logPath -RuntimeRoot $runtime
    Invoke-Sm2Import -Godot $godot -ProjectRoot $projectRoot -LogPath $logPath -RuntimeRoot $runtime
    $scriptPath = if ($Suite -eq 'm4_areas') { 'res://tests/m4_area_ui.gd' } elseif ($Suite -eq 'm4_ai') { 'res://tests/m4_ability_ai_ui.gd' } elseif ($Suite -eq 'm4_magic') { 'res://tests/m4_magic_ui.gd' } elseif ($Suite -eq 'm4') { 'res://tests/m4_ui.gd' } elseif ($Suite -eq 'm3') { 'res://tests/m3_ui.gd' } else { 'res://tests/ui_smoke.gd' }
    if ($Suite -eq 'p1') { $scriptPath = 'res://tests/p1_progress_ui.gd' }
    if ($Suite -eq 'p4_attributes') { $scriptPath = 'res://tests/p4_attribute_ui.gd' }
    if ($Suite -eq 'controls') { $scriptPath = 'res://tests/controls_ui.gd' }
    if ($Suite -eq 'settings') { $scriptPath = 'res://tests/settings_ui.gd' }
    if ($Suite -eq 'journal') { $scriptPath = 'res://tests/journal_ui.gd' }
    if ($Suite -eq 'soul') { $scriptPath = 'res://tests/soul_ui.gd' }
    if ($Suite -eq 'battle_results') { $scriptPath = 'res://tests/battle_results_ui.gd' }
    if ($Suite -eq 'campaigns') { $scriptPath = 'res://tests/campaigns_ui.gd' }
    if ($Suite -eq 'start_menu') { $scriptPath = 'res://tests/start_menu_ui.gd' }
    if ($Suite -eq 'camp_layout') { $scriptPath = 'res://tests/camp_layout_ui.gd' }
    if ($Suite -eq 'development_layout') { $scriptPath = 'res://tests/development_layout_ui.gd' }
    if ($Suite -eq 'inventory_layout') { $scriptPath = 'res://tests/inventory_layout_ui.gd' }
    if ($Suite -eq 'display') { $scriptPath = 'res://tests/display_ui.gd' }
    if ($Suite -eq 'journey_guide') { $scriptPath = 'res://tests/journey_guide_ui.gd' }
    if ($Suite -eq 'combat_hud') { $scriptPath = 'res://tests/combat_hud_ui.gd' }
    if ($Suite -eq 'battle_feedback') { $scriptPath = 'res://tests/battle_feedback_ui.gd' }
    if ($Suite -eq 'battle_art') { $scriptPath = 'res://tests/battle_art_ui.gd' }
    if ($Suite -eq 'survival_workspace') { $scriptPath = 'res://tests/survival_workspace_ui.gd' }
    if ($Suite -eq 'survival_tissues') { $scriptPath = 'res://tests/survival_tissues_ui.gd' }
    if ($Suite -eq 'survival_devices') { $scriptPath = 'res://tests/survival_devices_ui.gd' }
    if ($Suite -eq 'survival') { $scriptPath = 'res://tests/survival_ui.gd' }
    if ($Suite -eq 'p6_region') { $scriptPath = 'res://tests/p6_region_ui.gd' }
    if ($Suite -eq 'p5_hybrids') { $scriptPath = 'res://tests/p5_hybrid_ui.gd' }
    if ($Suite -eq 'p5_cross_nodes') { $scriptPath = 'res://tests/p5_cross_nodes_ui.gd' }
    if ($Suite -eq 'p5_menu') { $scriptPath = 'res://tests/p5_menu_ui.gd' }
    if ($Suite -eq 'p5_implants') { $scriptPath = 'res://tests/p5_implant_ui.gd' }
    if ($Suite -eq 'p5_upgrades') { $scriptPath = 'res://tests/p5_upgrade_ui.gd' }
    if ($Suite -eq 'p5_shield') { $scriptPath = 'res://tests/p5_shield_ui.gd' }
    if ($Suite -eq 'p5_growth') { $scriptPath = 'res://tests/p5_growth_ui.gd' }
    if ($Suite -eq 'p5_psionics') { $scriptPath = 'res://tests/p5_psionic_ui.gd' }
    if ($Suite -eq 'p4_hero_screen') { $scriptPath = 'res://tests/p4_hero_screen_ui.gd' }
    if ($Suite -eq 'p4_discovery') { $scriptPath = 'res://tests/p4_discovery_ui.gd' }
    if ($Suite -eq 'p4_search') { $scriptPath = 'res://tests/p4_search_ui.gd' }
    if ($Suite -eq 'p4_exploration') { $scriptPath = 'res://tests/p4_exploration_ui.gd' }
    if ($Suite -eq 'p4_care') { $scriptPath = 'res://tests/p4_care_ui.gd' }
    if ($Suite -eq 'p4_prosthesis') { $scriptPath = 'res://tests/p4_prosthesis_ui.gd' }
    if ($Suite -eq 'p4_body') { $scriptPath = 'res://tests/p4_body_ui.gd' }
    if ($Suite -eq 'p4_party') { $scriptPath = 'res://tests/p4_party_ui.gd' }
    if ($Suite -eq 'p4') { $scriptPath = 'res://tests/p4_journey_ui.gd' }
    if ($Suite -eq 'p3') { $scriptPath = 'res://tests/p3_world_ui.gd' }
    if ($Suite -eq 'p2') { $scriptPath = 'res://tests/p2_development_ui.gd' }
    $arguments = @('--path',$projectRoot,'--script',$scriptPath,'--','--output',$outputPath)
    if ($Headless) {
        if ($Suite -eq 'm1') { throw 'M1 UI suite requires rendering.' }
        $arguments = @('--headless') + $arguments
    }
    $result = Invoke-Sm2Process -Executable $godot -Arguments $arguments -WorkingDirectory $projectRoot -LogPath $logPath -RuntimeRoot $runtime
    if ($result.ExitCode -ne 0 -or (Test-Sm2GodotOutput $result.Text)) { throw "UI checks failed; exit $($result.ExitCode). Log: $logPath" }
    $report = [IO.File]::ReadAllText((Join-Path $outputPath 'report.json')) | ConvertFrom-Json
    if ($report.passed -isnot [bool] -or -not $report.passed -or $report.checks -le 0 -or @($report.failures).Count -ne 0) { throw 'UI report does not confirm success.' }
    Write-Output "UI checks passed: $($report.checks). Report: $outputPath\report.json. Log: $logPath"
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
