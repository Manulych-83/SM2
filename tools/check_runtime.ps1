[CmdletBinding()]
param([string]$RuntimeRoot='.local/runtime-2/baseline',[string]$OutputDirectory='outputs/runtime-2/baseline')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'find_godot.ps1')
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runtime=Initialize-Sm2Runtime -ProjectRoot $projectRoot -RuntimeRoot $RuntimeRoot
$outputRoot=Initialize-Sm2Runtime -ProjectRoot $projectRoot -RuntimeRoot $OutputDirectory
$destination=Join-Path $runtime 'appdata\SM2\runtime_slots'
if(Test-Path -LiteralPath $destination){throw 'Use a fresh runtime for this audit.'}
[void][IO.Directory]::CreateDirectory($destination)
$source=Join-Path $projectRoot '.local\checkpoint-1\verified\appdata\SM2\checkpoint-scale'
Copy-Item -LiteralPath (Join-Path $source 'survival_tissues.json') -Destination $destination
Copy-Item -LiteralPath (Join-Path $source 'history_blocks') -Destination $destination -Recurse
$log=Join-Path $outputRoot 'checks.log'
$godot=Resolve-Sm2Godot -ProjectRoot $projectRoot -RuntimeRoot $runtime -LogPath $log
Invoke-Sm2Import -Godot $godot -ProjectRoot $projectRoot -RuntimeRoot $runtime -LogPath $log
$result=Invoke-Sm2Process -Executable $godot -Arguments @('--headless','--path',$projectRoot,'--script','res://tools/check_runtime.gd','--','--report',(Join-Path $outputRoot 'report.json')) -WorkingDirectory $projectRoot -RuntimeRoot $runtime -LogPath $log
if($result.ExitCode -ne 0 -or (Test-Sm2GodotOutput $result.Text)){throw "Runtime audit failed: $log"}
Write-Output "Runtime audit passed: $outputRoot"
