# Vivado batch simulation for AXI-Lite testbench
# Usage: vivado -mode batch -source run_axi_tb_vivado.tcl

set proj_dir [file normalize [file join [file dirname [info script]] ../../..]]
set src_dir  [file join $proj_dir Leading_Edge_Reconstruction.srcs/sources_1/new]
set sim_dir  [file join $proj_dir Leading_Edge_Reconstruction.srcs/sim_1/new]
set out_dir  [file join $sim_dir build_vivado]

file mkdir $out_dir

set src_files [list \
    [file join $src_dir leading_edge_core.v] \
    [file join $src_dir myip_leading_edge_axi_lite_v1_1_S00_AXI.v] \
    [file join $src_dir myip_leading_edge_axi_lite_v1_1.v] \
    [file join $sim_dir TB_axi_leading_edge.v] \
]

foreach f $src_files {
    if {![file exists $f]} {
        error "Missing source file: $f"
    }
}

create_project -force axi_leading_edge_sim $out_dir -part xczu7ev-ffvc1156-2-e
set_property target_language Verilog [current_project]

foreach f $src_files {
    add_files -norecurse $f
}

set_property top TB_axi_leading_edge [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {50us} -objects [get_filesets sim_1]

launch_simulation
run 50us

set sim_log [file join $out_dir axi_leading_edge_sim.sim/sim_1/behav/xsim/simulate.log]
if {[file exists $sim_log]} {
    set fh [open $sim_log r]
    set txt [read $fh]
    close $fh
    puts $txt
    if {[string match *"ALL TESTS PASSED"* $txt]} {
        puts "=== VIVADO SIM: PASS ==="
        close_sim -force
        exit 0
    }
    if {[string match *"FAIL:"* $txt]} {
        puts "=== VIVADO SIM: FAIL ==="
        close_sim -force
        exit 1
    }
}

puts "=== VIVADO SIM: finished (check Tcl Console / simulate.log) ==="
close_sim -force
exit 0
