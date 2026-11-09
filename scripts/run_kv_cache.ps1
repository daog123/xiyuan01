[CmdletBinding()]
param(
    [string]$VivadoBin='E:\AMDDesignTools\2025.2\Vivado\bin',
    [string]$Python='python',
    [switch]$ReferenceOnly,[switch]$CorruptExpected,[switch]$TimeoutProbe,
    [switch]$SkipBRegression,[switch]$Synthesize
)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
function Invoke-Checked([string]$Executable,[string[]]$Arguments,[string]$Log) {
    ('& "'+$Executable+'" '+(($Arguments|ForEach-Object {'"'+$_+'"'}) -join ' ')) | Add-Content commands.txt
    & $Executable @Arguments 2>&1 | Tee-Object -FilePath $Log | Out-Host
    if($LASTEXITCODE -ne 0) {throw "$Executable exited $LASTEXITCODE"}
}
& $Python (Join-Path $taskRoot 'model\kv_cache_reference.py') --out (Join-Path $taskRoot 'build\kv_vectors')
if($LASTEXITCODE -ne 0) {throw 'KV reference failed'}
if($ReferenceOnly){Write-Host 'REFERENCE_ONLY: KV RTL and tensor handoff NOT executed';return}
foreach($tool in @('xvlog.bat','xelab.bat','xsim.bat')) {
    if(!(Test-Path -LiteralPath (Join-Path $VivadoBin $tool))){throw "Missing EDA tool: $tool; RTL NOT validated"}
}
$names=@('w4a8_memory_pkg','w4a8_memory_validate','w4a8_tensor_dependency','kv_cache_pkg','kv_cache_address','storage_axi_byte_write','w4a8_axi_read','kv_cache')
$rtl=$names|ForEach-Object {Join-Path $taskRoot "rtl\$_.sv"}
$sources=$rtl+@(Join-Path $taskRoot 'tb\storage_axi_memory.sv')+@(Join-Path $taskRoot 'tb\tb_kv_cache.sv')+@(Join-Path $taskRoot 'tb\tb_w4a8_tensor_dependency.sv')
$tops=@('tb_w4a8_tensor_dependency','tb_kv_cache','tb_kv_cache_group3')
if($CorruptExpected -or $TimeoutProbe){$tops=@('tb_kv_cache')}
foreach($top in $tops) {
    $name=$top;if($CorruptExpected){$name+='_negative'};if($TimeoutProbe){$name+='_timeout'}
    $work=Join-Path $taskRoot "build\$name";New-Item -ItemType Directory -Force $work|Out-Null
    Copy-Item -LiteralPath (Join-Path $taskRoot 'build\kv_vectors\kv_vectors.txt') -Destination $work -Force
    $hashes=[ordered]@{}
    foreach($source in ($sources+@(Join-Path $taskRoot 'model\kv_cache_reference.py'))) {
        $hashes[$source.Substring($taskRoot.Length+1).Replace('\','/')]=(Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant()
    }
    [ordered]@{top=$top;files=$hashes}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $work 'source_inputs.json')
    Push-Location $work
    try {
        if(Test-Path PASS.txt){Remove-Item -LiteralPath PASS.txt}
        Set-Content commands.txt '# Actual follow-up storage XSim commands'
        Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--sv')+$sources) 'compile.log'
        Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @($top,'-s','followup_sim','-timescale','1ns/1ps') 'elaborate.log'
        $simargs=@('followup_sim','-tclbatch',((Join-Path $taskRoot 'scripts\run_w4a8_memory_xsim.tcl').Replace('\','/')))
        if($CorruptExpected){$simargs+=@('-testplusarg','corrupt_expected')}
        if($TimeoutProbe){$simargs+=@('-testplusarg','timeout_probe')}
        Invoke-Checked (Join-Path $VivadoBin 'xsim.bat') $simargs 'run.log'
        $log=Get-Content -Raw run.log
        $sentinel=if($top -eq 'tb_w4a8_tensor_dependency'){'TENSOR_DEPENDENCY_TESTS_PASS'}else{'KV_CACHE_TESTS_PASS'}
        if($log -notmatch $sentinel -or $log -match 'Fatal:|FAILED|TIMEOUT|(?m)^ERROR:'){throw "Storage self-check failed: $name"}
        Set-Content PASS.txt 'PASS'
    } finally {Pop-Location}
}
if(!$CorruptExpected -and !$TimeoutProbe) {
    foreach($probe in @('CorruptExpected','TimeoutProbe')) {
        $probeOut=Join-Path $taskRoot "build\kv_$probe.stdout.log";$probeErr=Join-Path $taskRoot "build\kv_$probe.stderr.log"
        $process=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),('-'+$probe),'-VivadoBin',('"'+$VivadoBin+'"'),'-Python',('"'+$Python+'"')) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $probeOut -RedirectStandardError $probeErr
        Set-Content (Join-Path $taskRoot "build\kv_$probe.exit.txt") $process.ExitCode
        $expected=if($probe -eq 'TimeoutProbe'){'command watchdog'}else{'KV_CHECK_FAILED read data/last exact'}
        if($process.ExitCode -eq 0 -or (Get-Content -Raw $probeOut) -notmatch $expected){throw "Nonzero probe failed: $probe"}
    }
    if(!$SkipBRegression) {
        & (Join-Path $taskRoot 'scripts\run_w4a8_memory.ps1') -Python $Python -VivadoBin $VivadoBin -SingleConfig
        if(!$? -or $LASTEXITCODE -ne 0){throw 'Preserved B regression failed'}
    }
    & $Python (Join-Path $taskRoot 'scripts\summarize_kv_cache.py')
    if($LASTEXITCODE -ne 0){throw 'KV evidence audit failed'}
}
if($Synthesize) {
    $work=Join-Path $taskRoot 'build\synth_kv_cache';New-Item -ItemType Directory -Force $work|Out-Null
    $synthSources=@('kv_cache_pkg','kv_cache_address','storage_axi_byte_write','w4a8_axi_read','kv_cache')|ForEach-Object {Join-Path $taskRoot "rtl\$_.sv"}
    $synthHashes=[ordered]@{}
    foreach($source in ($synthSources+@(Join-Path $taskRoot 'scripts\synth_kv_cache.tcl'))) {
        $synthHashes[$source.Substring($taskRoot.Length+1).Replace('\','/')]=(Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant()
    }
    [ordered]@{top='kv_cache';files=$synthHashes}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $work 'source_inputs.json')
    Push-Location $work
    try {
        Set-Content commands.txt '# Actual KV OOC synthesis attempt'
        Invoke-Checked (Join-Path $VivadoBin 'vivado.bat') @('-mode','batch','-source',((Join-Path $taskRoot 'scripts\synth_kv_cache.tcl').Replace('\','/')),'-tclargs',$taskRoot.Replace('\','/')) 'synth.console.log'
        if((Get-Content -Raw synth.console.log) -notmatch 'KV_SYNTHESIS_PASS'){throw 'KV synthesis incomplete'}
    } finally {Pop-Location}
    & $Python (Join-Path $taskRoot 'scripts\summarize_kv_cache.py')
    if($LASTEXITCODE -ne 0){throw 'Post-synthesis KV evidence audit failed'}
}
Write-Host 'STORAGE_FOLLOWUP_VALIDATION_PASS'
