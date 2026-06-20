# -----------------------------------------------------------------------------
# Create a clean AXI-Lite Block Design for leading_edge_ip_lite.
#
# Project:
#   C:/Users/grzeg/Desktop/SDUP/Vivado/Leading_edge_AXI/Leading_edge_AXI.xpr
#
# Architecture:
#   Zynq UltraScale+ PS M_AXI_HPM0_FPD
#       -> AXI SmartConnect
#       -> leading_edge_ip_lite_0/s_axi
#
# The design intentionally contains only the AXI-Lite control path. AXI-Stream is
# not instantiated in this version.
# -----------------------------------------------------------------------------

set project_file {C:/Users/grzeg/Desktop/SDUP/Vivado/Leading_edge_AXI/Leading_edge_AXI.xpr}
set ip_repo_dir  {C:/Users/grzeg/Desktop/SDUP/Vivado/Leading_edge_core_TB/ip_repo}
set bd_name      {leading_edge_axi_lite_bd}
set base_addr    {0xA0000000}
set addr_range   {4K}

open_project $project_file
set_property ip_repo_paths [list $ip_repo_dir] [current_project]
update_ip_catalog

if {[llength [get_files -quiet */${bd_name}.bd]] > 0} {
    puts "Removing existing Block Design: $bd_name"
    remove_files [get_files -quiet */${bd_name}.bd]
}

create_bd_design $bd_name
current_bd_design $bd_name

# Processing System configured from the ZCU106 board preset.
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* processing_system]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "1"} \
    $ps

# Keep one PS AXI master for the register-mapped peripheral.
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

# User IP and the minimal AXI-Lite interconnect.
set le_ip [create_bd_cell -type ip -vlnv user.org:user:leading_edge_ip_lite:1.0 leading_edge_ip_lite_0]
set axi   [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* axi_lite_smartconnect]
set rst   [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* axi_lite_reset]

set_property -dict [list \
    CONFIG.NUM_SI {1} \
    CONFIG.NUM_MI {1} \
] $axi

# AXI-Lite data path.
connect_bd_intf_net [get_bd_intf_pins processing_system/M_AXI_HPM0_FPD] [get_bd_intf_pins axi_lite_smartconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_lite_smartconnect/M00_AXI] [get_bd_intf_pins leading_edge_ip_lite_0/s_axi]

# Clocking: one PL clock for PS AXI, SmartConnect and the custom IP.
connect_bd_net [get_bd_pins processing_system/pl_clk0] [get_bd_pins processing_system/maxihpm0_fpd_aclk]
connect_bd_net [get_bd_pins processing_system/pl_clk0] [get_bd_pins axi_lite_smartconnect/aclk]
connect_bd_net [get_bd_pins processing_system/pl_clk0] [get_bd_pins axi_lite_reset/slowest_sync_clk]
connect_bd_net [get_bd_pins processing_system/pl_clk0] [get_bd_pins leading_edge_ip_lite_0/s_axi_aclk]

# Reset path. The existing project uses pl_resetn0 directly as ext_reset_in; keep
# that convention for consistency with the validated design.
connect_bd_net [get_bd_pins processing_system/pl_resetn0] [get_bd_pins axi_lite_reset/ext_reset_in]
connect_bd_net [get_bd_pins axi_lite_reset/peripheral_aresetn] [get_bd_pins axi_lite_smartconnect/aresetn]
connect_bd_net [get_bd_pins axi_lite_reset/peripheral_aresetn] [get_bd_pins leading_edge_ip_lite_0/s_axi_aresetn]

assign_bd_address

set seg [get_bd_addr_segs -quiet processing_system/Data/SEG_leading_edge_ip_lite_0_reg0]
if {[llength $seg] > 0} {
    set_property offset $base_addr $seg
    set_property range  $addr_range $seg
}

validate_bd_design -force
save_bd_design

set wrapper_file [make_wrapper -files [get_files [file join [get_property DIRECTORY [current_project]] Leading_edge_AXI.srcs sources_1 bd $bd_name ${bd_name}.bd]] -top]
add_files -norecurse $wrapper_file
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

regenerate_bd_layout
save_bd_design
close_project

puts "Created clean AXI-Lite Block Design: $bd_name"
puts "Address map: leading_edge_ip_lite_0 at $base_addr, range $addr_range"
