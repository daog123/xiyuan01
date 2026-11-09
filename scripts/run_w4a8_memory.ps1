[CmdletBinding()]
param(
    [string]$VivadoBin='E:\AMDDesignTools\2025.2\Vivado\bin',
    [string]$Python='python',
    [switch]$ReferenceOnly,[switch]$Synthesize,[switch]$CorruptExpected,[switch]$TimeoutProbe,[switch]$SingleConfig,
    [switch]$SkipWaveRegression
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
function Invoke-Checked([string]$Executable,[string[]]$Arguments,[string]$Log) {
    ('& "'+$Executable+'" '+(($Arguments|ForEach-Object {'"'+$_+'"'}) -join ' ')) | Add-Content commands.txt
    & $Executable @Arguments 2>&1 | Tee-Object -FilePath $Log | Out-Host
    if($LASTEXITCODE -ne 0) {throw "$Executable exited $LASTEXITCODE"}
}
New-Item -ItemType Directory -Force (Join-Path $root 'build') | Out-Null
& $Python (Join-Path $root 'model\w4a8_memory_vectors.py') --out (Join-Path $root 'build\w4a8_memory_vectors')
if($LASTEXITCODE -ne 0) {throw 'Memory reference failed'}
if($ReferenceOnly) {Write-Host 'REFERENCE_ONLY: RTL simulation/synthesis NOT executed';return}
foreach($tool in @('xvlog.bat','xelab.bat','xsim.bat')) {
    if(!(Test-Path -LiteralPath (Join-Path $VivadoBin $tool))) {throw "Missing EDA tool: $tool; reference generated, RTL NOT validated"}
}
$rtl=@('w4a8_memory_pkg','w4a8_memory_validate','w4a8_axi_read','w4a8_axi_write','w4a8_memory_packet','w4a8_memory_bridge',
    'sync_sdp_ram','mac_pe','mac_array','systolic_pe','systolic_array','w4_unpack','w4a8_wave') | ForEach-Object {Join-Path $root "rtl\$_.sv"}
$sources=$rtl+@(Join-Path $root 'tb\w4a8_axi_memory.sv')+@(Join-Path $root 'tb\tb_w4a8_memory.sv')
$configs=@('tb_w4a8_memory','tb_w4a8_memory8','tb_w4a8_memory_alt','tb_w4a8_memory_unit')
if($SingleConfig -or $CorruptExpected -or $TimeoutProbe) {$configs=@('tb_w4a8_memory')}
foreach($top in $configs) {
    $name=$top;if($CorruptExpected) {$name+='_negative'};if($TimeoutProbe){$name+='_timeout'}
    $work=Join-Path $root "build\$name";New-Item -ItemType Directory -Force $work | Out-Null
    Copy-Item -Path (Join-Path $root 'build\w4a8_memory_vectors\g*_job*.*') -Destination $work -Force
    $evidenceFiles=$sources+@((Join-Path $root 'model\w4a8_memory_vectors.py'),(Join-Path $root 'model\w4a8_reference.py'))
    $hashes=[ordered]@{};foreach($source in $evidenceFiles){$hashes[$source.Substring($root.Length+1).Replace('\','/')]=(Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant()}
    [ordered]@{top=$top;files=$hashes}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $work 'source_inputs.json')
    Push-Location $work
    try {
        if(Test-Path PASS.txt){Remove-Item -LiteralPath PASS.txt}
        Set-Content commands.txt '# Actual XSim commands'
        Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--sv')+$sources) 'compile.log'
        Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @($top,'-s','memory_sim','-timescale','1ns/1ps') 'elaborate.log'
        $simargs=@('memory_sim','-tclbatch',((Join-Path $root 'scripts\run_w4a8_memory_xsim.tcl').Replace('\','/')))
        if($CorruptExpected){$simargs+=@('-testplusarg','corrupt_expected')}
        if($TimeoutProbe){$simargs+=@('-testplusarg','timeout_probe')}
        Invoke-Checked (Join-Path $VivadoBin 'xsim.bat') $simargs 'run.log'
        $log=Get-Content -Raw run.log
        if($log -notmatch 'W4A8_MEMORY_TESTS_PASS' -or $log -match 'Fatal:|FAILED|TIMEOUT|(?m)^ERROR:') {throw "Memory self-check failed: $work"}
        Set-Content PASS.txt 'PASS'
    } finally {Pop-Location}
}
if(!$CorruptExpected -and !$TimeoutProbe -and !$SingleConfig) {
    $probeOut=Join-Path $root 'build\memory_negative.stdout.log';$probeErr=Join-Path $root 'build\memory_negative.stderr.log'
    $process=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-CorruptExpected','-VivadoBin',('"'+$VivadoBin+'"'),'-Python',('"'+$Python+'"')) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $probeOut -RedirectStandardError $probeErr
    Set-Content (Join-Path $root 'build\memory_negative_exit.txt') $process.ExitCode
    if($process.ExitCode -eq 0 -or (Get-Content -Raw $probeOut) -notmatch 'W4A8_MEMORY_CHECK_FAILED') {throw 'Expected nonzero failure probe failed'}
    $timeoutOut=Join-Path $root 'build\memory_timeout.stdout.log';$timeoutErr=Join-Path $root 'build\memory_timeout.stderr.log'
    $process=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-TimeoutProbe','-VivadoBin',('"'+$VivadoBin+'"'),'-Python',('"'+$Python+'"')) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $timeoutOut -RedirectStandardError $timeoutErr
    Set-Content (Join-Path $root 'build\memory_timeout_exit.txt') $process.ExitCode
    if($process.ExitCode -eq 0 -or (Get-Content -Raw $timeoutOut) -notmatch 'per-task watchdog') {throw 'Expected nonzero timeout probe failed'}
    if(!$SkipWaveRegression) {
        & (Join-Path $root 'scripts\run_w4a8_wave.ps1') -VivadoBin $VivadoBin -Python $Python
        if(!$? -or $LASTEXITCODE -ne 0) {throw 'Preserved wave regression failed'}
    }
}
if($Synthesize) {
    $work=Join-Path $root 'build\synth_w4a8_memory';New-Item -ItemType Directory -Force $work|Out-Null
    $hashes=[ordered]@{}
    foreach($source in (($rtl | Select-Object -First 6)+@((Join-Path $root 'scripts\synth_w4a8_memory.tcl')))) {
        $hashes[$source.Substring($root.Length+1).Replace('\','/')]=(Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant()
    }
    [ordered]@{top='w4a8_memory_bridge';files=$hashes}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $work 'source_inputs.json')
    Push-Location $work
    try {
        Set-Content commands.txt '# Actual storage OOC synthesis command'
        Invoke-Checked (Join-Path $VivadoBin 'vivado.bat') @('-mode','batch','-source',((Join-Path $root 'scripts\synth_w4a8_memory.tcl').Replace('\','/')),'-tclargs',$root.Replace('\','/')) 'synth.console.log'
        $log=Get-Content -Raw synth.console.log
        if($log -notmatch 'W4A8_MEMORY_SYNTHESIS_PASS' -or $log -match '(?m)^ERROR:') {throw 'Storage synthesis incomplete'}
    } finally {Pop-Location}
}
if(!$CorruptExpected -and !$TimeoutProbe){& $Python (Join-Path $root 'scripts\summarize_w4a8_memory.py');if($LASTEXITCODE -ne 0){throw 'Memory evidence audit failed'}}
Write-Host 'W4A8_MEMORY_VALIDATION_PASS'
