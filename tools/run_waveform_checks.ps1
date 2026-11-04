param(
    [string]$Python='python',
    [switch]$FullRegression
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
trap { Write-Output $_; exit 1 }
$releaseRoot=Split-Path $PSScriptRoot
Set-Location -LiteralPath $releaseRoot
$ivl=(Get-Command iverilog.exe -ErrorAction Stop).Source
$toolBin=Split-Path $ivl
$vvp=Join-Path $toolBin 'vvp.exe'
$env:PATH=$toolBin+';'+(Join-Path (Split-Path $toolBin) 'lib')+';'+$env:PATH
[void](New-Item -ItemType Directory -Force -Path sim)
$rtl=@(Get-ChildItem -LiteralPath rtl -Filter '*.v' -File | ForEach-Object { $_.FullName })
$fixtures=@('tb/ttp229_model.v','tb/fixtures/top_before_waveform.v','tb/fixtures/telemetry_before_waveform.v')
$results=@()
# Windows PowerShell 5 treats native stderr (including successful unittest
# progress) as ErrorRecords. Judge native tools by their exit code and checks.
$ErrorActionPreference='Continue'
foreach($name in @('wave_capture','wave_capture_mapped','telemetry_wave','wave_audio_equivalence','telemetry','uart_tx','uart_rx','bt_cmd_parse','top_bt_in','top_board_inputs','top_pa_enable')) {
    $test='tb_'+$name
    $compileArgs=@('-g2012','-s',$test,'-o',('sim/'+$test+'.vvp'))+$rtl+$fixtures+@('tb/'+$test+'.v')
    & $ivl @compileArgs 2>&1 | Out-File -Encoding UTF8 -LiteralPath ('sim/'+$test+'.wave-compile.log')
    if($LASTEXITCODE -ne 0) { throw "Compilation failed: $test (see sim/$test.wave-compile.log)" }
    $lines=@(& $vvp ('sim/'+$test+'.vvp') 2>&1 | ForEach-Object { $_.ToString() })
    $runExit=$LASTEXITCODE
    $lines | Out-File -Encoding UTF8 -LiteralPath ('sim/'+$test+'.wave-run.log')
    if($runExit -ne 0 -or ($lines -match '\b(FAIL(?:ED)?|FATAL)\b') -or -not ($lines -match 'PASS')) {
        $lines | Write-Output
        throw "Test failed: $test"
    }
    $summary=($lines | Where-Object { $_ -match 'PASS' }) -join '; '
    Write-Output $summary
    $results+=@{Test=$test;Result='PASS';Summary=$summary}
}
& node --test tools/test_wave_protocol.js tools/test_wave_ui.js
if($LASTEXITCODE -ne 0) { throw 'Node waveform tests failed' }
$unitRunner="import sys,unittest; suite=unittest.defaultTestLoader.discover('tools',pattern='test_wave*.py'); result=unittest.TextTestRunner(stream=sys.stdout,verbosity=1).run(suite); sys.exit(0 if result.wasSuccessful() else 1)"
& $Python -B -c $unitRunner
if($LASTEXITCODE -ne 0) { throw 'Python waveform tests failed' }
if($FullRegression) {
    & (Join-Path $releaseRoot 'run_integration.ps1') -UnitTests
    if($LASTEXITCODE -ne 0) { throw 'Full integration regression failed' }
}
$results | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -LiteralPath sim/waveform-checks.json
Write-Output 'WAVEFORM_CHECKS=PASS'
exit 0
