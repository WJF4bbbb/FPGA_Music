param(
    [string]$GowinBin=$env:GOWIN_BIN,
    [string]$OutputName=('ttp229-implementation-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
if ($OutputName -notmatch '^ttp229[-A-Za-z0-9]+$') { throw 'OutputName must be a dedicated ttp229 name' }
$output=Join-Path (Join-Path $root 'sim') $OutputName
if (Test-Path -LiteralPath $output) { throw "Preserve previous implementation; choose a new OutputName: $output" }
New-Item -ItemType Directory -Path $output | Out-Null
$shellExe=if($GowinBin){Join-Path $GowinBin 'gw_sh.exe'}else{(Get-Command gw_sh.exe -ErrorAction Stop).Source}
if (-not (Test-Path -LiteralPath $shellExe)) { throw "Missing $shellExe" }
function TclPath([string]$Path) { return '{'+([IO.Path]::GetFullPath($Path).Replace('\','/'))+'}' }
$projectName='MusicSynth_TTP229'
$lines=@(
    ('create_project -name '+$projectName+' -dir '+(TclPath $output)+' -pn GW2AR-LV18QN88C8/I7 -device_version C'),
    ('source '+(TclPath (Join-Path $root 'gowin/MusicSynth_TangNano20K/project_settings.tcl')))
)
foreach ($source in Get-Content -LiteralPath (Join-Path $root 'sources.f')) {
    if ($source.Trim()) { $lines+=('add_file -type verilog '+(TclPath (Join-Path $root $source.Trim()))) }
}
$lines+=('add_file -type cst '+(TclPath (Join-Path $root 'gowin\MusicSynth_TangNano20K\src\MusicSynth_TangNano20K.cst')))
$lines+=('add_file -type sdc '+(TclPath (Join-Path $root 'constraints\top.sdc')))
$lines+='run all'
$tcl=Join-Path $output 'implement.tcl'
[IO.File]::WriteAllLines($tcl,$lines,[Text.UTF8Encoding]::new($false))
$inputs=@(Get-Content -LiteralPath (Join-Path $root 'sources.f') | Where-Object { $_.Trim() } |
    ForEach-Object { Get-FileHash -LiteralPath (Join-Path $root $_.Trim()) -Algorithm SHA256 })
$inputs+=Get-FileHash -LiteralPath (Join-Path $root 'constraints\top.sdc'),(Join-Path $root 'gowin\MusicSynth_TangNano20K\src\MusicSynth_TangNano20K.cst') -Algorithm SHA256
$inputs | Select-Object Path,Hash | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'input-hashes.json') -Encoding UTF8
Write-Output "OFFLINE_IMPLEMENTATION=$output"
$ErrorActionPreference='Continue'
& $shellExe $tcl 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object -FilePath (Join-Path $output 'transcript.log')
$result=$LASTEXITCODE
[ordered]@{ExitCode=$result;Output=$output;CompletedUtc=[DateTime]::UtcNow.ToString('o');Scope='Offline synthesis/P&R only. No hardware programming.'} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'result.json') -Encoding UTF8
Write-Output "GOWIN_IMPLEMENTATION_EXIT=$result"
exit $result
