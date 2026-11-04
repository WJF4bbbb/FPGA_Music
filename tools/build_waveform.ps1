param(
    [ValidateSet('wired','wireless')][string]$Target='wired',
    [string]$GowinBin=$env:GOWIN_BIN,
    [string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$releaseRoot=Split-Path $PSScriptRoot
if(-not $OutputDirectory) {
    $OutputDirectory=Join-Path $releaseRoot ('sim/waveform-build/'+$Target+'-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
}
$buildOutput=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $buildOutput) { throw "Preserve existing build; select a new OutputDirectory: $buildOutput" }
[void](New-Item -ItemType Directory -Path $buildOutput)
if($GowinBin) { $gowinShell=Join-Path $GowinBin 'gw_sh.exe' }
else { $gowinShell=(Get-Command gw_sh.exe -ErrorAction Stop).Source }
if(-not (Test-Path -LiteralPath $gowinShell)) { throw "Missing Gowin shell: $gowinShell" }
function TclPath([string]$value) { return '{'+([IO.Path]::GetFullPath($value).Replace('\','/'))+'}' }
$projectName='MusicSynth_Waveform_'+$Target
$constraints=if($Target -eq 'wired') { 'gowin/wired/wired.cst' } else { 'gowin/MusicSynth_TangNano20K/src/MusicSynth_TangNano20K.cst' }
$settings=Join-Path $releaseRoot 'gowin/MusicSynth_TangNano20K/project_settings.tcl'
$sources=@(Get-Content -LiteralPath (Join-Path $releaseRoot 'sources.f') | Where-Object { $_.Trim() } | ForEach-Object { Join-Path $releaseRoot $_.Trim() })
$lines=@(
    ('create_project -name '+$projectName+' -dir '+(TclPath $buildOutput)+' -pn GW2AR-LV18QN88C8/I7 -device_version C'),
    ('source '+(TclPath $settings))
)
foreach($file in $sources) { $lines+=('add_file -type verilog '+(TclPath $file)) }
$lines+=('add_file -type cst '+(TclPath (Join-Path $releaseRoot $constraints)))
$lines+=('add_file -type sdc '+(TclPath (Join-Path $releaseRoot 'constraints/top.sdc')))
$lines+='run all'
$tclFile=Join-Path $buildOutput 'build.tcl'
[IO.File]::WriteAllLines($tclFile,$lines,[Text.UTF8Encoding]::new($false))
$inputs=$sources+@($settings,(Join-Path $releaseRoot $constraints),(Join-Path $releaseRoot 'constraints/top.sdc'),(Join-Path $releaseRoot 'sources.f'))
Get-FileHash -LiteralPath $inputs -Algorithm SHA256 | Select-Object Path,Hash | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $buildOutput 'source-hashes.json')
$ErrorActionPreference='Continue'
& $gowinShell $tclFile 2>&1 | ForEach-Object { $_.ToString() } | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $buildOutput 'build.log')
$buildExit=$LASTEXITCODE
Get-Content -Encoding UTF8 -LiteralPath (Join-Path $buildOutput 'build.log') -Tail 22
[ordered]@{Target=$Target;ExitCode=$buildExit;Output=$buildOutput;Scope='Offline synthesis and P&R; no board programming'} |
    ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $buildOutput 'result.json')
Write-Output "WAVEFORM_BUILD_EXIT=$buildExit OUTPUT=$buildOutput"
exit $buildExit
