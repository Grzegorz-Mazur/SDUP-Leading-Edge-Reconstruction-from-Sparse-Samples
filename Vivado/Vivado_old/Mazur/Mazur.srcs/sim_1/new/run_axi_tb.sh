#!/bin/bash
# Run AXI-Lite testbench with Icarus Verilog (iverilog)
set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="$ROOT/Leading_Edge_Reconstruction.srcs/sources_1/new"
SIM="$ROOT/Leading_Edge_Reconstruction.srcs/sim_1/new"
BUILD="$SIM/build"

mkdir -p "$BUILD"
iverilog -g2012 -o "$BUILD/TB_axi_leading_edge.vvp" \
    "$SRC/leading_edge_core.v" \
    "$SRC/myip_leading_edge_axi_lite_v1_1_S00_AXI.v" \
    "$SRC/myip_leading_edge_axi_lite_v1_1.v" \
    "$SIM/TB_axi_leading_edge.v"

vvp "$BUILD/TB_axi_leading_edge.vvp"
