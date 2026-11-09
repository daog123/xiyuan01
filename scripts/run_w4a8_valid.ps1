[CmdletBinding()]
param(
    [string]$VivadoBin='E:\AMDDesignTools\2025.2\Vivado\bin',[string]$Python='python',
    [switch]$Synthesize,[switch]$Implement,[switch]$Regression,[switch]$AuditOnly,[switch]$SynthOnly,
    [switch]$ProbeChild,[switch]$CorruptExpected,[switch]$TimeoutProbe,
    [ValidateSet('all','directed','v4','v8','alt','one','single','words8','base4','base8')][string]$Simulation='all',
    [ValidateSet('all','v4','v8')][string]$EdaConfig='all'
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
    param([string]$Work,[string]$Top,[int]$Rows,[int]$Cols,[int]$Group,[int]$Valid,[string[]]$Sources)
    $hashes=[ordered]@{}
    foreach($source in $Sources){$hashes[$source.Substring($root.Length+1).Replace('\','/')]=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()}
    [ordered]@{top=$Top;rows=$Rows;cols=$Cols;group_size=$Group;valid_only=$Valid;files=$hashes}|ConvertTo-Json -Depth 5|Set-Content -Encoding utf8 (Join-Path $Work 'source_inputs.json')
}
try {
    if($AuditOnly){& $Python (Join-Path $root 'scripts\summarize_w4a8_valid.py');if($LASTEXITCODE -ne 0){throw 'Valid-slot audit failed'};return}
    if($SynthOnly -and !($Synthesize -or $Implement)){throw 'SynthOnly requires Synthesize/Implement'}
    if(!$ProbeChild -and !$SynthOnly){
        & $Python (Join-Path $root 'model\w4a8_reference.py') --out (Join-Path $root 'build\w4a8_vectors');if($LASTEXITCODE -ne 0){throw 'Preserved numerical reference failed'}
        & $Python (Join-Path $root 'model\w4a8_systolic_vectors.py');if($LASTEXITCODE -ne 0){throw 'Preserved vectors failed'}
        & $Python (Join-Path $root 'model\w4a8_valid_reference.py');if($LASTEXITCODE -ne 0){throw 'Independent coordinate model failed'}
    }
    $rtl=@('sync_sdp_ram','mac_pe','mac_array','systolic_pe','systolic_array','w4_unpack','w4a8_valid')|ForEach-Object {Join-Path $root ('rtl\'+$_+'.sv')}
    $sources=$rtl+@((Join-Path $root 'tb\w4a8_reuse_memory.sv'),(Join-Path $root 'tb\tb_w4a8_valid.sv'))
    $header=Join-Path $root 'tb\valid_slot_monitor.svh'
    $configs=@(
        [pscustomobject]@{Name='v4';Rows=4;Cols=4;Group=32;Valid=1;Top='tb_w4a8_valid'},
        [pscustomobject]@{Name='v8';Rows=8;Cols=8;Group=32;Valid=1;Top='tb_w4a8_valid8'},
        [pscustomobject]@{Name='alt';Rows=2;Cols=3;Group=12;Valid=1;Top='tb_w4a8_valid_alt'},
        [pscustomobject]@{Name='one';Rows=1;Cols=1;Group=32;Valid=1;Top='tb_w4a8_valid_one'},
        [pscustomobject]@{Name='single';Rows=4;Cols=4;Group=32;Valid=1;Top='tb_w4a8_valid_single'},
        [pscustomobject]@{Name='words8';Rows=8;Cols=8;Group=32;Valid=1;Top='tb_w4a8_valid_words8'},
        [pscustomobject]@{Name='base4';Rows=4;Cols=4;Group=32;Valid=0;Top='tb_w4a8_valid_base4'},
        [pscustomobject]@{Name='base8';Rows=8;Cols=8;Group=32;Valid=0;Top='tb_w4a8_valid_base8'})
    if($Simulation -eq 'directed'){$configs=@([pscustomobject]@{Name='directed';Rows=4;Cols=4;Group=32;Valid=1;Top='tb_w4a8_valid_directed'})}
    elseif($Simulation -ne 'all'){$configs=@($configs|Where-Object {$_.Name -eq $Simulation})}
    if($SynthOnly){$configs=@()}
    foreach($cfg in $configs){
        $name='sim_w4a8_valid_'+$cfg.Name;if($CorruptExpected){$name+='_negative'};if($TimeoutProbe){$name+='_timeout'}
        $work=Join-Path $root ('build\'+$name);New-Item -ItemType Directory -Force $work|Out-Null
        Copy-Item -LiteralPath (Join-Path $root ('build\w4a8_systolic_vectors\group'+$cfg.Group+'.txt')) -Destination (Join-Path $work 'vectors.txt') -Force
        Copy-Item -LiteralPath $header -Destination (Join-Path $work 'valid_slot_monitor.svh') -Force
        Save-Identity $work $cfg.Top $cfg.Rows $cfg.Cols $cfg.Group $cfg.Valid ($sources+@($header,(Join-Path $root 'model\w4a8_reference.py'),(Join-Path $root 'model\w4a8_systolic_vectors.py'),(Join-Path $root 'model\w4a8_valid_reference.py'),$PSCommandPath,(Join-Path $root 'scripts\run_xsim.tcl')))
        Push-Location $work
        try {
            if(Test-Path -LiteralPath PASS.txt){Remove-Item -LiteralPath PASS.txt};Set-Content -Encoding utf8 commands.txt '# Actual valid-slot XSim commands'
            if($CorruptExpected){
                $tokens=(Get-Content -Raw vectors.txt)-split '\s+'|Where-Object {$_ -ne ''}
                $mm=[int]$tokens[2];$nn=[int]$tokens[3];$kk=[int]$tokens[4];$gg=[int]$tokens[5]
                $offset=6+$mm*$kk+$nn*[int][math]::Ceiling($kk/2.0)+($mm+$nn)*$gg
                $tokens[$offset]=[string]([int]$tokens[$offset]+1);Set-Content -Encoding ascii vectors.txt ($tokens -join ' ')
            }
            Invoke-Checked (Join-Path $VivadoBin 'xvlog.bat') (@('--sv')+$sources) 'compile.log'
            Invoke-Checked (Join-Path $VivadoBin 'xelab.bat') @($cfg.Top,'-s','valid_sim','-timescale','1ns/1ps') 'elaborate.log'
            $simargs=@('valid_sim','-tclbatch',((Join-Path $root 'scripts\run_xsim.tcl').Replace('\','/')))
            if($TimeoutProbe){$simargs+=@('-testplusarg','FORCE_TIMEOUT')}
            Invoke-Checked (Join-Path $VivadoBin 'xsim.bat') $simargs 'run.log'
            $log=Get-Content -Raw run.log
            if($log -notmatch 'W4A8_VALID_TESTS_PASS' -or $log -match '(?m)^Fatal:|CHECK_FAILED|TIMEOUT|^ERROR:'){throw "Valid-slot simulation failed: $work"}
            Set-Content -Encoding ascii PASS.txt 'PASS'
        } finally {Pop-Location}
    }
    if(!$ProbeChild -and !$SynthOnly -and $Simulation -eq 'all'){
        foreach($kind in @('negative','timeout')){
            $switch=if($kind -eq 'negative'){'-CorruptExpected'}else{'-TimeoutProbe'}
            $out=Join-Path $root ('build\valid_'+$kind+'.stdout.log');$err=Join-Path $root ('build\valid_'+$kind+'.stderr.log')
            $p=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-ProbeChild','-Simulation','v4',$switch,'-VivadoBin',('"'+$VivadoBin+'"')) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
            Set-Content -Encoding ascii (Join-Path $root ('build\sim_w4a8_valid_v4_'+$kind+'\observed_exit_code.txt')) $p.ExitCode
            $marker=if($kind -eq 'negative'){'W4A8_VALID_CHECK_FAILED'}else{'W4A8_VALID_GLOBAL_TIMEOUT'}
            if($p.ExitCode -eq 0 -or (Get-Content -Raw $out) -notmatch $marker){throw 'Valid-slot expected failure missing'}
            Write-Host "VALID_EXPECTED_${kind}_EXIT=$($p.ExitCode)"
        }
    }
    if($Synthesize -or $Implement){
        foreach($size in @(4,8)){
            $name='v'+$size;if($EdaConfig -ne 'all' -and $EdaConfig -ne $name){continue}
            $work=Join-Path $root ('build\synth_w4a8_valid_'+$name);New-Item -ItemType Directory -Force $work|Out-Null
            Save-Identity $work 'w4a8_valid' $size $size 32 1 ($rtl+@((Join-Path $root 'constraints\clock.xdc'),(Join-Path $root 'scripts\synth_w4a8_valid.tcl')))
            Push-Location $work
            try {
                Set-Content -Encoding utf8 commands.txt '# Actual VU9P valid-slot commands'
                Invoke-Checked (Join-Path $VivadoBin 'vivado.bat') @('-mode','batch','-source',((Join-Path $root 'scripts\synth_w4a8_valid.tcl').Replace('\','/')),'-log','synth_w4a8_valid.log','-journal','synth_w4a8_valid.jou','-tclargs',$(if($Implement){'1'}else{'0'}),[string]$size) 'console.log'
                $log=Get-Content -Raw synth_w4a8_valid.log
                if($log -notmatch '(?m)^W4A8_VALID_SYNTHESIS_PASS' -or ($Implement -and $log -notmatch '(?m)^W4A8_VALID_OOC_FINISHED')){throw 'Valid-slot EDA incomplete'}
            } finally {Pop-Location}
        }
    }
    if($Regression){
        foreach($entry in @('run_w4a8_wave.ps1','run_dynamic.ps1')){
            & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root ('scripts\'+$entry)) -VivadoBin $VivadoBin -Python $Python
            if($LASTEXITCODE -ne 0){throw "Regression failed: $entry"}
        }
    }
    if(!$ProbeChild -and $Simulation -eq 'all'){& $Python (Join-Path $root 'scripts\summarize_w4a8_valid.py');if($LASTEXITCODE -ne 0){throw 'Valid-slot delivery audit failed'}}
    Write-Host 'W4A8_VALID_VALIDATION_PASS'
} catch {Write-Error $_;exit 1}
