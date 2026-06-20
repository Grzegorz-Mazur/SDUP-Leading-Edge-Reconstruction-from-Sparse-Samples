# -----------------------------------------------------------------------------
# Create integration project: Leading_edge_AXI
#
# This project is separate from Leading_edge_core_TB.  The old project remains
# the IP development/package project, while this one is the system Block Design.
# -----------------------------------------------------------------------------

set base_dir      {C:/Users/grzeg/Desktop/SDUP/Vivado}
set project_name  {Leading_edge_AXI}
set project_dir   [file join $base_dir $project_name]
set ip_repo_dir   {C:/Users/grzeg/Desktop/SDUP/Vivado/Leading_edge_core_TB/ip_repo}
set part_name     {xczu7ev-ffvc1156-2-e}
set board_part    {xilinx.com:zcu106:part0:2.6}
set bd_name       {leading_edge_axi_bd}

file mkdir $base_dir

if {[file exists $project_dir]} {
    puts "Project directory already exists, reusing: $project_dir"
} else {
    file mkdir $project_dir
}

create_project $project_name $project_dir -part $part_name -force
set_property board_part $board_part [current_project]
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set_property ip_repo_paths [list $ip_repo_dir] [current_project]
update_ip_catalog

create_bd_design $bd_name

# Processing System: Zynq UltraScale+ MPSoC from the ZCU106 board preset.
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* zynq_ultra_ps_e_0]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "1"} \
    $ps

# Keep the diagram intentionally small: one PS AXI master for AXI-Lite.
# The ZCU106 board preset may enable HPM1 as well, so turn it off when the
# property exists.  Different Vivado revisions expose both names below.
foreach prop_name {
    CONFIG.PSU__USE__M_AXI_GP1
    CONFIG.PSU__USE__S_AXI_GP1
    CONFIG.PSU__USE__M_AXI_HPM1_FPD
} {
    if {[lsearch -exact [list_property $ps] $prop_name] >= 0} {
        set_property $prop_name 0 $ps
    }
}

if {[lsearch -exact [list_property $ps] CONFIG.PSU__USE__M_AXI_GP0] >= 0} {
    set_property CONFIG.PSU__USE__M_AXI_GP0 1 $ps
}
if {[lsearch -exact [list_property $ps] CONFIG.PSU__USE__M_AXI_HPM0_FPD] >= 0} {
    set_property CONFIG.PSU__USE__M_AXI_HPM0_FPD 1 $ps
}

# User IP: AXI-Lite version of the leading-edge core.
set le_ip [create_bd_cell -type ip -vlnv user.org:user:leading_edge_ip_lite:1.0 leading_edge_ip_lite_0]

# Connect the IP as an AXI-Lite peripheral to the PS master interface.
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {
        Clk_master {/zynq_ultra_ps_e_0/pl_clk0 (100 MHz)}
        Clk_slave {/zynq_ultra_ps_e_0/pl_clk0 (100 MHz)}
        Clk_xbar {/zynq_ultra_ps_e_0/pl_clk0 (100 MHz)}
        Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD}
        Slave {/leading_edge_ip_lite_0/s_axi}
        intc_ip {New AXI Interconnect}
        master_apm {0}
    } \
    [get_bd_intf_pins leading_edge_ip_lite_0/s_axi]

# If Vivado leaves an unused HPM1 clock pin after the board preset, tie it to the
# PS PL clock so validation does not fail.  The interface itself remains unused.
set hpm1_clk_pin [get_bd_pins -quiet zynq_ultra_ps_e_0/maxihpm1_fpd_aclk]
set pl_clk_pin   [get_bd_pins -quiet zynq_ultra_ps_e_0/pl_clk0]
if {[llength $hpm1_clk_pin] > 0 && [llength $pl_clk_pin] > 0} {
    catch {connect_bd_net $pl_clk_pin $hpm1_clk_pin}
}

# Keep the first system simple: software can poll STATUS.done.  The IRQ remains
# visible on the diagram, but intentionally unconnected for now.

assign_bd_address
validate_bd_design
save_bd_design

make_wrapper -files [get_files [file join $project_dir $project_name.srcs sources_1 bd $bd_name ${bd_name}.bd]] -top
add_files -norecurse [file join $project_dir $project_name.gen sources_1 bd $bd_name hdl ${bd_name}_wrapper.v]
update_compile_order -fileset sources_1

puts "Created project: $project_dir"
puts "Created Block Design: $bd_name"
puts "IP repository used: $ip_repo_dir"
