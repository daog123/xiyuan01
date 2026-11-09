param([string]$VivadoBin = "E:\AMDDesignTools\2025.2\Vivado\bin")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root "build\w4a8_system"
New-Item -ItemType Directory -Force -Path $build | Out-Null
$env:TEMP = $build
$env:TMP = $build
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
if (!(Test-Path $xvlog) -or !(Test-Path $xelab) -or !(Test-Path $xsim)) { throw "Vivado simulation tools not found at $VivadoBin" }
$files = @(
    "$root\rtl\task_desc_pkg.sv", "$root\rtl\sync_sdp_ram.sv", "$root\rtl\w4_unpack.sv",
    "$root\rtl\mac_pe.sv", "$root\rtl\mac_array.sv", "$root\rtl\w4a8_stream.sv",
    "$root\rtl\task_controller.sv", "$root\rtl\w4a8_system_top.sv",
    "$root\tb\w4a8_stream_memory.sv", "$root\tb\tb_w4a8_system.sv"
)
Push-Location $build
try {
    & $xvlog -sv @files 2>&1 | Tee-Object -FilePath "system_xvlog_console.log"
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed: $LASTEXITCODE" }
    & $xelab tb_w4a8_system -s tb_w4a8_system_sim -mt off 2>&1 | Tee-Object -FilePath "system_xelab_console.log"
    if ($LASTEXITCODE -ne 0) { throw "xelab failed: $LASTEXITCODE" }
    & $xsim tb_w4a8_system_sim -runall -log system_xsim.log
    if ($LASTEXITCODE -ne 0) { throw "xsim failed: $LASTEXITCODE" }
    if (!(Select-String -Path "system_xsim.log" -Pattern "W4A8_SYSTEM_PASS" -Quiet)) { throw "system test pass marker missing" }
} finally { Pop-Location }
