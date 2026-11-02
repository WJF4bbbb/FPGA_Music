param(
    [string]$ProjectPath = (Join-Path $PSScriptRoot '..\gowin\MusicSynth_TangNano20K\MusicSynth_TangNano20K.gprj'),
    [string]$ReportPath = (Join-Path $PSScriptRoot '..\sim\board_constraints_audit.json')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$projectFile = [IO.Path]::GetFullPath($ProjectPath)
# Gowin writes version="1"; normalize its nonstandard XML declaration in memory.
$projectText = (Get-Content -LiteralPath $projectFile -Raw).Replace('<?xml version="1"', '<?xml version="1.0"')
[xml]$project = $projectText
function Resolve-ProjectPath([string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path (Split-Path $projectFile) $Path))
}
$enabled = @($project.Project.FileList.File | Where-Object { $_.enable -eq '1' })
$csts = @($enabled | Where-Object { $_.type -eq 'file.cst' })
if ($csts.Count -ne 1) { throw 'Exactly one enabled CST is required' }
$cst = Resolve-ProjectPath $csts[0].path
$expectedCst = [IO.Path]::GetFullPath((Join-Path $root 'gowin\MusicSynth_TangNano20K\src\MusicSynth_TangNano20K.cst'))
if ($cst -ne $expectedCst) { throw "Unexpected effective CST: $cst" }
if ($project.Project.Device.pn -ne 'GW2AR-LV18QN88C8/I7') { throw 'Unexpected FPGA part' }
$text = Get-Content -LiteralPath $cst -Raw
# Ignore comments so disabled/documentary bindings cannot satisfy this audit.
$text = [regex]::Replace($text, '(?m)//.*$', '')
$locations = @{}
$usedPins = @{}
foreach ($m in [regex]::Matches($text, 'IO_LOC\s+"([^"]+)"\s+(\d+)\s*;')) {
    $port = $m.Groups[1].Value
    $pin = [int]$m.Groups[2].Value
    if ($locations.ContainsKey($port) -or $usedPins.ContainsKey($pin)) { throw "Duplicate LOC or pin: $port/$pin" }
    $locations[$port] = $pin
    $usedPins[$pin] = $port
}
$properties = @{}
foreach ($m in [regex]::Matches($text, 'IO_PORT\s+"([^"]+)"\s+([^;]+);')) {
    $port = $m.Groups[1].Value
    if ($properties.ContainsKey($port)) { throw "Duplicate IO_PORT: $port" }
    $properties[$port] = $m.Groups[2].Value
}
$topText = Get-Content -LiteralPath (Join-Path $root 'rtl\top.v') -Raw
$ports = @()
foreach ($m in [regex]::Matches($topText, '(?m)^\s*(?:input|output)\s+(?:wire|reg)\s+(?:\[(\d+):(\d+)\]\s+)?(\w+)')) {
    $name = $m.Groups[3].Value
    if ($m.Groups[1].Success) {
        $high = [int]$m.Groups[1].Value; $low = [int]$m.Groups[2].Value
        for ($bit=$low; $bit -le $high; $bit++) { $ports += "$name[$bit]" }
    } else { $ports += $name }
}
if ($ports.Count -eq 0 -or $ports.Count -ne $locations.Count -or $ports.Count -ne $properties.Count) {
    throw 'Top/LOC/IO_PORT counts differ'
}
$pinMap = @{
    clk=4; rst_n=73; test_enable=74; ttp_scl=27; ttp_sdo=28;
    bclk=56; lrclk=55; i2s_data=54; pa_en=51
}
if ($ports.Count -ne 9) { throw 'Expected 9 physical ports: five panel GPIOs removed by user decision' }
foreach ($port in $ports) {
    if (-not $locations.ContainsKey($port) -or -not $properties.ContainsKey($port)) { throw "Unconstrained port: $port" }
    if ($locations[$port] -ne $pinMap[$port]) { throw "Unexpected provisional pin: $port=$($locations[$port])" }
    if ($properties[$port] -notmatch '\bIO_TYPE=LVCMOS33\b' -or $properties[$port] -notmatch '\bBANK_VCCIO=3\.3\b') {
        throw "Unexpected IO voltage: $port"
    }
    $pull = if ($port -in @('test_enable','pa_en')) { 'DOWN' } else { 'UP' }
    if ($properties[$port] -notmatch "\bPULL_MODE=$pull\b") { throw "Wrong default pull for $port; expected $pull" }
}
if ($topText -match 'KEY_ACTIVE_LOW|PANEL_ACTIVE_LOW' -or $topText -notmatch 'TTP_ACTIVE_LOW\s*=\s*1') {
    throw 'Touch polarity boundary/default changed; review reader and CST together'
}
if ($topText -notmatch 'TOUCH_CTRL_FILT\s*=\s*135000') { throw '5ms touch control filter changed; rerun latency proof' }
foreach ($entry in @(@('TTP_STARTUP_CYCLES',13500000),@('TTP_SCL_HALF_CYCLES',135),@('TTP_FRAME_GAP_CYCLES',81000))) {
    if ($topText -notmatch ($entry[0]+'\s*=\s*'+$entry[1]+'\b')) {
        throw "Default TTP229 timing changed: $($entry[0]); recheck protocol and latency"
    }
}
$configFile = Join-Path $root 'gowin\MusicSynth_TangNano20K\impl\MusicSynth_TangNano20K_process_config.json'
# Gowin JSON contains Show_All_Warnings/show_all_warnings, which Windows
# PowerShell5's case-insensitive ConvertFrom-Json cannot parse together.
$settingsFile = Join-Path $root 'gowin/MusicSynth_TangNano20K/project_settings.tcl'
$settingsText = Get-Content -LiteralPath $settingsFile -Raw
foreach ($option in @('use_sspi_as_gpio','use_mspi_as_gpio')) {
    if ($settingsText -notmatch ('(?m)^set_option -'+$option+' 1\s*$')) { throw "Portable project setting missing: $option" }
}
if ($settingsText -notmatch '(?m)^set_option -global_freq 27\s*$' -or
    $settingsText -notmatch '(?m)^set_option -top_module top\s*$') { throw 'Portable clock/top settings changed' }
if (Test-Path -LiteralPath $configFile) {
    $configText = Get-Content -LiteralPath $configFile -Raw
    if ($configText -cnotmatch '"SSPI"\s*:\s*true' -or $configText -cnotmatch '"MSPI"\s*:\s*true') {
        throw 'Existing local implementation disagrees with portable SSPI/MSPI settings'
    }
}
$formalSources = @(Get-Content -LiteralPath (Join-Path $root 'sources.f') | Where-Object { $_.Trim() -ne '' } |
    ForEach-Object { [IO.Path]::GetFullPath((Join-Path $root $_.Trim())) })
$projectSources = @($enabled | Where-Object type -eq 'file.verilog' |
    ForEach-Object { Resolve-ProjectPath $_.path })
if ($projectSources.Count -ne @($projectSources | Sort-Object -Unique).Count -or
    @(Compare-Object ($formalSources | Sort-Object) ($projectSources | Sort-Object)).Count -ne 0) {
    throw 'Gowin source list differs from sources.f or contains duplicates'
}
$sdcFiles = @($enabled | Where-Object type -eq 'file.sdc')
if ($sdcFiles.Count -ne 1) { throw 'Exactly one enabled SDC is required' }
$sdcPath = Resolve-ProjectPath $sdcFiles[0].path
$sdc = Get-Content -LiteralPath $sdcPath -Raw
if ($sdc -notmatch 'create_clock[^\r\n]+-period\s+37\.037037') { throw '27 MHz clock constraint missing' }
$report = [ordered]@{
    CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
    Project = $projectFile
    EffectiveCst = $cst
    CstSHA256 = (Get-FileHash -LiteralPath $cst -Algorithm SHA256).Hash
    ConfigurationStatus = 'PASS'
    PortCount = $ports.Count
    FormalSourceCount = $formalSources.Count
    PinMap = $pinMap
    SchematicReference = 'User-provided V3923 Rev1.3: GPIO27=J6-8, GPIO28=J6-9; Bank5 3.3V; PA51/53 unresolved'
    ElectricalStatus = 'SCHEMATIC CHECKED; physical straps/levels and PA51/53 continuity UNVERIFIED'
    ImplementationScope = 'Offline P&R authorized; no programming; external electrical signoff pending'
    SetupHoldStatus = 'See fresh TTP229 implementation report; this audit does not establish STA'
    BoardTestStatus = 'NOT RUN'
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Output "PASS: enabled CST, $($ports.Count) ports, unique provisional pin map, pulls, and formal sources"
Write-Output "EFFECTIVE_CST=$cst"
Write-Output 'PHYSICAL_AUDIT=UNVERIFIED; offline implementation only; no SRAM/Flash programming'
