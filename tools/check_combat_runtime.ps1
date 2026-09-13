[CmdletBinding()]
param([string]$RuntimeRoot='',[string]$OutputDirectory='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'find_godot.ps1')
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
if(-not $RuntimeRoot){$RuntimeRoot='.local/combat-runtime-1/'+$stamp}
if(-not $OutputDirectory){$OutputDirectory='outputs/combat-runtime-1/'+$stamp}
$resolvedOutput=if([IO.Path]::IsPathRooted($OutputDirectory)){[IO.Path]::GetFullPath($OutputDirectory)}else{[IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))}
if(Test-Path -LiteralPath (Join-Path $resolvedOutput 'report.json')){throw 'Choose a fresh output directory; prior measurements are preserved.'}
$runtime=Initialize-Sm2Runtime -ProjectRoot $projectRoot -RuntimeRoot $RuntimeRoot
$outputRoot=Initialize-Sm2Runtime -ProjectRoot $projectRoot -RuntimeRoot $OutputDirectory
$log=Join-Path $outputRoot 'checks.log'
$godot=Resolve-Sm2Godot -ProjectRoot $projectRoot -RuntimeRoot $runtime -LogPath $log
Invoke-Sm2Import -Godot $godot -ProjectRoot $projectRoot -RuntimeRoot $runtime -LogPath $log
$result=Invoke-Sm2Process -Executable $godot -Arguments @('--headless','--path',$projectRoot,'--script','res://tools/check_combat_runtime.gd','--','--output',$outputRoot) -WorkingDirectory $projectRoot -RuntimeRoot $runtime -LogPath $log
if($result.ExitCode -ne 0 -or (Test-Sm2GodotOutput $result.Text)){throw "Combat runtime audit failed: $log"}
Write-Output "Combat runtime audit passed: $outputRoot"
