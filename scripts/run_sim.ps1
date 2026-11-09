[CmdletBinding()]
param(
    [string]$VivadoBin='E:\AMDDesignTools\2025.2\Vivado\bin',
    [string]$Python='python',
    [switch]$SingleConfig,
    [switch]$CorruptExpected,
    [switch]$UnitOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$vectorDir=Join-Path $root 'build\vectors'
New-Item -ItemType Directory -Force $vectorDir | Out-Null
& $Python (Join-Path $root 'model\generate_vectors.py') --out $vectorDir
if ($LASTEXITCODE -ne 0) {throw 'Reference generation failed'}
foreach ($name in 'xvlog','xelab','xsim') {
    if (!(Test-Path -LiteralPath (Join-Path $VivadoBin "$name.bat"))) {throw "Missing $name.bat in $VivadoBin"}
}
function Invoke-Checked {
    param([string]$Executable,[string[]]$Arguments,[string]$Log)
    ('& "'+$Executable+'" '+(($Arguments | ForEach-Object {'"'+$_+'"'}) -join ' ')) | Add-Content -Encoding utf8 commands.txt
    & $Executable @Arguments 2>&1 | Tee-Object -FilePath $Log | Out-Host
    $code=$LASTEXITCODE
    if ($code -ne 0) {throw "$Executable failed with exit code $code; see $Log"}
}
$configs=@([pscustomobject]@{Rows=4;Cols=4;K=8;Opt=1;DB=1;Gap=0;Top='tb_matmul'})
if (!$SingleConfig) {
    $configs+= [pscustomobject]@{Rows=2;Cols=3;K=5;Opt=1;DB=1;Gap=0;Top='tb_matmul_alt'}
    $configs+= [pscustomobject]@{Rows=2;Cols=3;K=5;Opt=1;DB=1;Gap=3;Top='tb_matmul_db_slow'}
    $configs+= [pscustomobject]@{Rows=2;Cols=1;K=3;Opt=1;DB=1;Gap=0;Top='tb_matmul_db_fast'}
    $configs+= [pscustomobject]@{Rows=4;Cols=4;K=8;Opt=1;DB=0;Gap=0;Top='tb_matmul_single'}
    $configs+= [pscustomobject]@{Rows=2;Cols=3;K=5;Opt=1;DB=0;Gap=0;Top='tb_matmul_alt_single'}
    $configs+= [pscustomobject]@{Rows=4;Cols=4;K=8;Opt=0;DB=0;Gap=0;Top='tb_matmul_baseline'}
    $configs+= [pscustomobject]@{Rows=2;Cols=3;K=5;Opt=0;DB=0;Gap=0;Top='tb_matmul_alt_baseline'}
}
if ($UnitOnly) {
    if ($CorruptExpected) {throw 'UnitOnly cannot be combined with CorruptExpected'}
    $configs=@()
}
foreach ($config in $configs) {
    $rows=$config.Rows; $cols=$config.Cols; $tk=$config.K
    $work=Join-Path $root "build\sim_${rows}x${cols}_k${tk}"
    if ($config.DB) {$work += "_db"} elseif ($config.Opt) {$work += "_opt"}
    if ($config.Gap) {$work += "_gap"+$config.Gap}
    if ($CorruptExpected) {$work += "_negative"}
    New-Item -ItemType Directory -Force $work | Out-Null
    Copy-Item -LiteralPath (Join-Path $vectorDir 'vectors.txt'),(Join-Path $vectorDir 'pe_vectors.txt') -Destination $work -Force
    Push-Location $work
    try {
        if (Test-Path -LiteralPath 'PASS.txt') {Remove-Item -LiteralPath 'PASS.txt'}
        Set-Content -Encoding utf8 commands.txt '# Actual commands; paths are quoted for PowerShell'
        if ($CorruptExpected) {
            $tokens=(Get-Content -Raw vectors.txt).Split([char[]]" `t`r`n",[System.StringSplitOptions]::RemoveEmptyEntries)
            $mm=[int]$tokens[2]; $nn=[int]$tokens[3]; $kk=[int]$tokens[4]
            $firstExpected=5+$mm*$kk+$kk*$nn
            $tokens[$firstExpected]=[string]([int]$tokens[$firstExpected]+1)
            Set-Content -Encoding ascii vectors.txt ($tokens -join ' ')
        }
        $sources=@('sync_sdp_ram','mac_pe','mac_array','tile_buffer','b_pingpong','matmul_top') | ForEach-Object {Join-Path $root "rtl\$_.sv"}
        $sources+=Join-Path $root 'tb\tb_matmul.sv'
        Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--sv')+$sources) 'compile.log'
        Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @($config.Top,'-s','matmul_sim','-timescale','1ns/1ps') 'elaborate.log'
        Invoke-Checked (Join-Path $VivadoBin 'xsim.bat') @('matmul_sim','-tclbatch',((Join-Path $root 'scripts\run_xsim.tcl').Replace('\','/'))) 'run.log'
        $log=Get-Content -Raw run.log
        if ($log -notmatch 'ALL_TESTS_PASS' -or $log -match 'Fatal:|CHECK_FAILED|MISMATCH|GLOBAL_TIMEOUT|ERROR:') {throw "Simulation did not pass: $work\run.log"}
        'PASS' | Set-Content -Encoding ascii PASS.txt
    } finally {Pop-Location}
}
if (!$CorruptExpected) {
    $work=Join-Path $root 'build\sim_pingpong_unit'
    New-Item -ItemType Directory -Force $work | Out-Null
    Push-Location $work
    try {
        if (Test-Path -LiteralPath 'PASS.txt') {Remove-Item -LiteralPath 'PASS.txt'}
        Set-Content -Encoding utf8 commands.txt '# Actual ping-pong unit-test commands'
        $sources=@('sync_sdp_ram','tile_buffer','b_pingpong') | ForEach-Object {Join-Path $root "rtl\$_.sv"}
        $sources+=Join-Path $root 'tb\tb_b_pingpong.sv'
        Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--sv')+$sources) 'compile.log'
        Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @('tb_b_pingpong','-s','pingpong_unit','-timescale','1ns/1ps') 'elaborate.log'
        Invoke-Checked (Join-Path $VivadoBin 'xsim.bat') @('pingpong_unit','-tclbatch',((Join-Path $root 'scripts\run_xsim.tcl').Replace('\','/'))) 'run.log'
        $log=Get-Content -Raw run.log
        if ($log -notmatch 'PINGPONG_UNIT_PASS' -or $log -match 'Fatal:|FAILED|TIMEOUT|ERROR:') {throw 'Ping-pong unit test failed'}
        'PASS' | Set-Content -Encoding ascii PASS.txt
    } finally {Pop-Location}
}
Write-Host 'SIMULATION_PASS: all requested configurations and unit test'



