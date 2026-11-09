[CmdletBinding()]
param(
    [string]$VivadoBin='E:\AMDDesignTools\2025.2\Vivado\bin',
    [switch]$Implement,
    [switch]$ResumeReports,
    [switch]$Baseline,
    [switch]$SingleBuffer
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$vivado=Join-Path $VivadoBin 'vivado.bat'
if (!(Test-Path -LiteralPath $vivado)) {throw "Missing $vivado"}
$mode=if ($Baseline) {'0'} else {'1'}
$dbMode=if ($Baseline -or $SingleBuffer) {'0'} else {'1'}
$work=Join-Path $root $(if ($Baseline) {'build\synth'} elseif ($SingleBuffer) {'build\synth_opt'} else {'build\synth_db'})
New-Item -ItemType Directory -Force $work | Out-Null
# Bind a checkpoint to its actual RTL, constraints and mode.
$inputHashes=[ordered]@{}
# Hash only files actually read by synth.tcl. NPU wrapper has its own flow.
$coreInputNames=@('rtl/sync_sdp_ram.sv','rtl/mac_pe.sv','rtl/mac_array.sv',
    'rtl/tile_buffer.sv','rtl/b_pingpong.sv','rtl/matmul_top.sv','constraints/clock.xdc')
foreach ($key in $coreInputNames) {
    $inputHashes[$key]=(Get-FileHash -LiteralPath (Join-Path $root $key) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$provenancePath=Join-Path $work 'source_inputs.json'
if ($ResumeReports) {
    if (!(Test-Path -LiteralPath $provenancePath)) {throw 'Checkpoint provenance absent; run full synthesis first'}
    $saved=Get-Content -Raw -LiteralPath $provenancePath | ConvertFrom-Json
    if ([int]$saved.OPTIMIZED -ne [int]$mode -or [int]$saved.DOUBLE_BUFFER -ne [int]$dbMode) {throw 'Checkpoint mode differs; run full synthesis'}
    foreach ($key in $inputHashes.Keys) {
        if ($saved.files.$key -ne $inputHashes[$key]) {throw "Checkpoint source differs: $key; run full synthesis"}
    }
} else {
    [ordered]@{OPTIMIZED=[int]$mode;DOUBLE_BUFFER=[int]$dbMode;B_LOAD_GAP=0;scope='RTL and constraints before tool execution';files=$inputHashes} |
        ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 -LiteralPath $provenancePath
}
Push-Location $work
try {
    Set-Content -Encoding utf8 commands.txt '# Actual Vivado invocations'
    $stages=@('query_parts',$(if ($ResumeReports) {'resume_reports'} else {'synth'}))
    foreach ($scriptName in $stages) {
        $arguments=@('-mode','batch','-source',((Join-Path $root "scripts\$scriptName.tcl").Replace('\','/')),'-log',"$scriptName.log",'-journal',"$scriptName.jou")
        if ($scriptName -ne 'query_parts') {$arguments+=@('-tclargs',$(if ($Implement) {'1'} else {'0'}),$mode,$dbMode)}
        ('& "'+$vivado+'" '+(($arguments | ForEach-Object {'"'+$_+'"'}) -join ' ')) | Add-Content -Encoding utf8 commands.txt
        & $vivado @arguments 2>&1 | Tee-Object -FilePath "$scriptName.console.log" | Out-Host
        if ($LASTEXITCODE -ne 0) {throw "$scriptName failed; see $work\$scriptName.log"}
    }
} finally {Pop-Location}

