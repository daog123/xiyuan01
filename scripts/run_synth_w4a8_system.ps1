param([string]$VivadoBin = "E:\AMDDesignTools\2025.2\Vivado\bin")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root "build\synth_w4a8_system"
New-Item -ItemType Directory -Force -Path $build | Out-Null
$vivado = Join-Path $VivadoBin "vivado.bat"
Push-Location $root
try {
    & $vivado -mode batch -source "$PSScriptRoot\synth_w4a8_system.tcl" -nolog -nojournal 2>&1 |
        Tee-Object -FilePath (Join-Path $build "synthesis_console.log")
    if ($LASTEXITCODE -ne 0) { throw "Vivado synthesis failed: $LASTEXITCODE" }
} finally { Pop-Location }
