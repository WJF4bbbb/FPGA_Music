param([string]$GowinBin=$env:GOWIN_BIN)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Set-Location -LiteralPath $PSScriptRoot
$synth=if($GowinBin){Join-Path $GowinBin 'GowinSynthesis.exe'}else{(Get-Command GowinSynthesis.exe -ErrorAction Stop).Source}
if(-not(Test-Path -LiteralPath $synth)){throw "Missing synthesis executable: $synth"}
New-Item -ItemType Directory -Force -Path 'sim/gowin_top.tmp' | Out-Null
# Manufacturer specifies this exact device for Tang Nano 20K. No pin guesses.
# The standalone synthesis engine defaults to 100MHz unless global_freq is set.
$synthArgs=@('-if','sources.f','-top','top','-pn','GW2AR-LV18QN88C8/I7',
    '-verilog_language','verilog-2001','-sdc','constraints/top.sdc','-global_freq','27',
    '-o','sim/gowin_top.tmp/top.edf')
Write-Output ('SYNTHESIS: '+$synth+' '+($synthArgs -join ' '))
$ErrorActionPreference='Continue'
& $synth @synthArgs 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object -FilePath 'sim/gowin_top_synthesis.log'
$synExit=$LASTEXITCODE
Write-Output "GOWIN_TOP_SYNTHESIS_EXIT=$synExit"
Write-Output 'Synthesis only: no placement, routing, complete I/O timing or board programming.'
exit $synExit
