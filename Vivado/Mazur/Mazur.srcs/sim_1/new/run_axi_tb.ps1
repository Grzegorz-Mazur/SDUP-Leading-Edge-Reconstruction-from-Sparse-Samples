# Run AXI-Lite testbench with Icarus Verilog (iverilog) on Windows
$ErrorActionPreference = "Stop"
$Root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$Src  = Join-Path $Root "Leading_Edge_Reconstruction.srcs\sources_1\new"
$Sim  = $PSScriptRoot
$Build = Join-Path $Sim "build"
New-Item -ItemType Directory -Force -Path $Build | Out-Null

$files = @(
    (Join-Path $Src "leading_edge_core.v"),
    (Join-Path $Src "myip_leading_edge_axi_lite_v1_1_S00_AXI.v"),
    (Join-Path $Src "myip_leading_edge_axi_lite_v1_1.v"),
    (Join-Path $Sim "TB_axi_leading_edge.v")
)

$out = Join-Path $Build "TB_axi_leading_edge.vvp"
& iverilog -g2012 -o $out @files
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& vvp $out
exit $LASTEXITCODE
