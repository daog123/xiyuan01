[CmdletBinding()]
param(
    [string]$VivadoBin='E:\AMDDesignTools\2025.2\Vivado\bin',[string]$Python='python',
    [switch]$Synthesize,[switch]$Implement,[switch]$Regression,[switch]$ProbeChild,
    [switch]$CorruptExpected,[switch]$TimeoutProbe,[switch]$AuditOnly,[switch]$SynthOnly,[switch]$SimOnly,
    [ValidateSet('all','unit','protocol','ffn32','ffn12')][string]$Simulation='all'
)
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
function Invoke-Checked {
    param([string]$Executable,[string[]]$Arguments,[string]$Log)
    ('& "'+$Executable+'" '+(($Arguments|ForEach-Object {'"'+$_+'"'})-join ' '))|Add-Content -Encoding utf8 commands.txt
    & $Executable @Arguments 2>&1 | Tee-Object -FilePath $Log | Out-Host
    $code=$LASTEXITCODE;Set-Content -Encoding ascii ($Log+'.exit_code.txt') $code
    if($code -ne 0){throw "$Executable exited $code"}
}
function Save-Identity {
    param([string]$Work,[string]$Top,[int]$Group,[string[]]$Sources)
    $hashes=[ordered]@{}
    foreach($source in $Sources){$hashes[$source.Substring($root.Length+1).Replace('\','/')]=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()}
    $actualCapacity=if($Top -eq 'tb_ffn_protocol'){8}elseif($Top -eq 'tb_swiglu_element'){0}else{512}
    [ordered]@{top=$Top;group_size=$Group;capacity=$actualCapacity;files=$hashes}|ConvertTo-Json -Depth 5|Set-Content -Encoding utf8 (Join-Path $Work 'source_inputs.json')
}
try {
    if($AuditOnly){& $Python (Join-Path $root 'scripts\summarize_ffn.py');if($LASTEXITCODE -ne 0){throw 'FFN audit failed'};return}
    if($SynthOnly -and !($Synthesize -or $Implement)){throw 'SynthOnly requires Synthesize/Implement'}
    $vec=Join-Path $root 'build\ffn_vectors'
    if(!$ProbeChild -and !$SynthOnly){
        New-Item -ItemType Directory -Force $vec|Out-Null;Push-Location $vec
        try {Set-Content -Encoding utf8 commands.txt '# FFN reference';Invoke-Checked $Python @((Join-Path $root 'model\vector\ffn_reference.py'),'--out',$vec) 'model.log'} finally {Pop-Location}
    }
    $rtl=@('sync_sdp_ram','mac_pe','mac_array','systolic_pe','systolic_array','w4_unpack','w4a8_wave','vector\requant_group','vector\requant_dynamic','vector\silu_sigmoid_lut','vector\swiglu_element','vector\ffn_bridge')|ForEach-Object {Join-Path $root ('rtl\'+$_+'.sv')}
    $sources=$rtl+@((Join-Path $root 'tb\w4a8_reuse_memory.sv'),(Join-Path $root 'tb\vector\tb_w4a8_two_layer.sv'),(Join-Path $root 'tb\vector\tb_swiglu_element.sv'),(Join-Path $root 'tb\vector\tb_w4a8_ffn.sv'),(Join-Path $root 'tb\vector\tb_ffn_protocol.sv'))
    $models=@('model\vector\ffn_reference.py','model\vector\dynamic_reference.py','model\vector\requant_reference.py','model\w4a8_reference.py','scripts\run_ffn.ps1','scripts\run_xsim.tcl')|ForEach-Object {Join-Path $root $_}
    $configs=@(
        [pscustomobject]@{Name='unit';Group=0;Top='tb_swiglu_element';Marker='SWIGLU_TESTS_PASS'},
        [pscustomobject]@{Name='protocol';Group=12;Top='tb_ffn_protocol';Marker='FFN_PROTOCOL_TESTS_PASS'},
        [pscustomobject]@{Name='ffn32';Group=32;Top='tb_w4a8_ffn';Marker='FFN_TESTS_PASS'},
        [pscustomobject]@{Name='ffn12';Group=12;Top='tb_w4a8_ffn12';Marker='FFN_TESTS_PASS'})
    if($Simulation -ne 'all'){$configs=@($configs|Where-Object {$_.Name -eq $Simulation})}
    if($SynthOnly){$configs=@()}
    foreach($cfg in $configs){
        $name='sim_ffn_'+$cfg.Name;if($CorruptExpected){$name+='_negative'};if($TimeoutProbe){$name+='_timeout'}
        $work=Join-Path $root ('build\'+$name);New-Item -ItemType Directory -Force $work|Out-Null
        if($cfg.Name -ne 'protocol'){Copy-Item -LiteralPath (Join-Path $vec ($cfg.Name+'.txt')) -Destination (Join-Path $work 'vectors.txt') -Force}
        Save-Identity $work $cfg.Top $cfg.Group ($sources+$models)
        Push-Location $work
        try {
            if(Test-Path -LiteralPath PASS.txt){Remove-Item -LiteralPath PASS.txt};Set-Content -Encoding utf8 commands.txt '# Actual FFN XSim commands'
            Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--sv')+$sources) 'compile.log'
            Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @($cfg.Top,'-s','ffn_sim','-timescale','1ns/1ps') 'elaborate.log'
            $simargs=@('ffn_sim','-tclbatch',((Join-Path $root 'scripts\run_xsim.tcl').Replace('\','/')))
            if($CorruptExpected){$simargs+=@('-testplusarg','CORRUPT_EXPECTED')};if($TimeoutProbe){$simargs+=@('-testplusarg','FORCE_TIMEOUT')}
            Invoke-Checked (Join-Path $VivadoBin 'xsim.bat') $simargs 'run.log'
            $log=Get-Content -Raw run.log
            if($log -notmatch $cfg.Marker -or $log -match '(?m)^Fatal:|CHECK_FAILED|_TIMEOUT|^ERROR:'){throw "FFN simulation failed: $work"}
            Set-Content -Encoding ascii PASS.txt 'PASS'
        } finally {Pop-Location}
    }
    if(!$ProbeChild -and !$SynthOnly -and $Simulation -eq 'all'){
        foreach($probeSpec in @(@('unit','negative'),@('ffn32','negative'),@('ffn32','timeout'))){
            $sim=$probeSpec[0];$kind=$probeSpec[1];$switch=if($kind -eq 'negative'){'-CorruptExpected'}else{'-TimeoutProbe'}
            $out=Join-Path $root ('build\ffn_'+$sim+'_'+$kind+'.stdout.log');$err=Join-Path $root ('build\ffn_'+$sim+'_'+$kind+'.stderr.log')
            $p=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-ProbeChild','-Simulation',$sim,$switch,'-VivadoBin',('"'+$VivadoBin+'"')) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
            Set-Content -Encoding ascii (Join-Path $root ('build\sim_ffn_'+$sim+'_'+$kind+'\observed_exit_code.txt')) $p.ExitCode
            $marker=if($kind -eq 'negative'){'CHECK_FAILED'}else{'FFN_TIMEOUT'}
            if($p.ExitCode -eq 0 -or (Get-Content -Raw $out) -notmatch $marker){throw 'FFN failure probe missing'}
            Write-Host "FFN_EXPECTED_${sim}_${kind}_EXIT=$($p.ExitCode)"
        }
    }
    if($Synthesize -or $Implement){
        foreach($g in @(32,12)){
            $work=Join-Path $root ('build\synth_ffn_g'+$g);New-Item -ItemType Directory -Force $work|Out-Null
            $eda=@($rtl[0])+$rtl[7..11]+@((Join-Path $root 'constraints\clock.xdc'),(Join-Path $root 'scripts\synth_ffn.tcl'))
            Save-Identity $work 'ffn_bridge' $g $eda
            Push-Location $work
            try {
                Set-Content -Encoding utf8 commands.txt '# Actual VU9P FFN bridge commands'
                Invoke-Checked (Join-Path $VivadoBin 'vivado.bat') @('-mode','batch','-source',((Join-Path $root 'scripts\synth_ffn.tcl').Replace('\','/')),'-log','synth_ffn.log','-journal','synth_ffn.jou','-tclargs',$(if($Implement){'1'}else{'0'}),[string]$g) 'console.log'
                $log=Get-Content -Raw synth_ffn.log
                if($log -notmatch '(?m)^FFN_SYNTHESIS_PASS' -or ($Implement -and $log -notmatch '(?m)^FFN_OOC_FINISHED')){throw 'FFN EDA incomplete'}
            } finally {Pop-Location}
        }
    }
    if($Regression){
        & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\run_dynamic.ps1') -Regression -VivadoBin $VivadoBin -Python $Python
        if($LASTEXITCODE -ne 0){throw 'FFN baseline regression failed'}
    }
    if(!$ProbeChild -and $Simulation -eq 'all'){
        $auditargs=@((Join-Path $root 'scripts\summarize_ffn.py'));if($SimOnly){$auditargs+='--SimOnly'}
        & $Python @auditargs;if($LASTEXITCODE -ne 0){throw 'FFN delivery audit failed'}
    }
    Write-Host 'FFN_VALIDATION_PASS'
} catch {Write-Error $_;exit 1}
