param(
    [string]$Suite = $env:OSS_CAD_SUITE,
    [switch]$UnitTests
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if ($Suite) {
    $ivl = Join-Path $Suite 'bin\iverilog.exe'
    $vvp = Join-Path $Suite 'bin\vvp.exe'
} else {
    $compiler = Get-Command iverilog.exe -ErrorAction Stop
    $ivl = $compiler.Source
    $vvp = Join-Path (Split-Path $ivl) 'vvp.exe'
}
foreach ($tool in @($ivl,$vvp)) {
    if (-not (Test-Path -LiteralPath $tool)) { throw "Missing tool: $tool" }
}
# Same installation, including matching C++ runtime before MSYS/other toolchains.
# Scope is this PowerShell process and its children; no machine PATH changes.
$env:IVL = Split-Path $ivl
$runtimeLib = Join-Path (Split-Path $env:IVL) 'lib'
$env:PATH = "$env:IVL;$runtimeLib;$env:PATH"
New-Item -ItemType Directory -Force -Path sim | Out-Null
Write-Output "Compiler: $ivl"
Write-Output "Runtime:  $vvp"
Write-Output "DLLs:     $runtimeLib"
$rtlFiles = @(Get-ChildItem -LiteralPath rtl -Filter '*.v' -File |
    Where-Object { $_.Name -notin @('clk_gen.v','top_i2s_test.v') } |
    Sort-Object Name | ForEach-Object { $_.FullName }) + @((Join-Path $PSScriptRoot 'tb\ttp229_model.v'))
$results = [System.Collections.Generic.List[object]]::new()
function Invoke-Test([string]$Name, [string[]]$Sources, [string]$SuccessPattern) {
    $compiled = Join-Path $PSScriptRoot "sim\$Name.vvp"
    $compileArgs = @('-g2012','-Wall','-s',$Name,'-o',$compiled) + $Sources + @("tb\$Name.v")
    Write-Output "=== $Name ==="
    Write-Output ('COMPILE: ' + $ivl + ' ' + ($compileArgs -join ' '))
    $ErrorActionPreference = 'Continue' # Native warnings are logged, not treated as PowerShell exceptions.
    & $ivl @compileArgs 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object -FilePath "sim\$Name.compile.log"
    $compileExit = $LASTEXITCODE
    if ($compileExit -ne 0) {
        $results.Add([pscustomobject]@{Test=$Name;CompileExit=$compileExit;RunExit=$null;Result='FAIL'})
        $results | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath 'sim\integration_results.tmp'
        Write-Output "COMPILE FAILED: $Name exit=$compileExit"
        exit $compileExit
    }
    Write-Output "RUN: $vvp $compiled"
    $output = @(& $vvp $compiled 2>&1 | ForEach-Object { $_.ToString() } |
        Tee-Object -FilePath "sim\$Name.run.log" | ForEach-Object { Write-Host $_; $_ })
    $runExit = $LASTEXITCODE
    $failedText = @($output | Where-Object { $_ -match '\bFAIL\b' }).Count -gt 0
    $succeeded = @($output | Where-Object { $_ -match $SuccessPattern }).Count -gt 0
    $result = if ($runExit -eq 0 -and -not $failedText -and $succeeded) { 'PASS' } else { 'FAIL' }
    $results.Add([pscustomobject]@{Test=$Name;CompileExit=$compileExit;RunExit=$runExit;Result=$result})
}
if ($UnitTests) {
    foreach ($name in @('audio_timing','i2s_tx','test_mode','sensor_frontend','control_panel','note_event',
                         'voice_alloc','osc_timbre','adsr','mixer','chain','contract_boundaries',
                         'top_board_inputs','top_input_polarity','top_pa_enable','ttp229_reader','ttp229_latency')) {
        Invoke-Test "tb_$name" $rtlFiles '(^PASS[: ]|^=== PASS \(0 errors\) ===$)'
    }
}
Invoke-Test 'tb_top_integration' $rtlFiles '^PASS: tb_top_integration all checks passed$'
$results | Format-Table -AutoSize | Out-Host
$results | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath 'sim\integration_results.tmp'
$failed = @($results | Where-Object Result -ne 'PASS').Count -gt 0
if ($failed) { Write-Output 'INTEGRATION_EXIT=1'; exit 1 }
Write-Output 'INTEGRATION_EXIT=0'
exit 0
