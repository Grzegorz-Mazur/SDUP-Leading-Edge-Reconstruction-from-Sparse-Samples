# -----------------------------------------------------------------------------
# Package leading_edge_ip_lite as a reusable Vivado IP.
#
# Usage from Vivado Tcl Console:
#   cd C:/Users/grzeg/Desktop/SDUP/Vivado/Leading_edge_core_TB
#   source ./scripts/package_leading_edge_ip_lite.tcl
#
# Output:
#   ./ip_repo/leading_edge_ip_lite
# -----------------------------------------------------------------------------

set project_dir [file normalize [pwd]]
set ip_repo_dir [file join $project_dir ip_repo]
set ip_dir      [file join $ip_repo_dir leading_edge_ip_lite]

file mkdir $ip_repo_dir
file delete -force $ip_dir
file mkdir $ip_dir

# Package the current Vivado project.  Vivado imports the project sources into
# the IP directory, so we do not add external file paths afterwards.
ipx::package_project \
    -root_dir $ip_dir \
    -vendor user.org \
    -library user \
    -taxonomy /UserIP \
    -import_files \
    -set_current false

set core [ipx::open_core [file join $ip_dir component.xml]]

set_property name leading_edge_ip_lite $core
set_property display_name {Leading Edge IP Lite} $core
set_property description {Leading-edge reconstruction core with AXI4-Lite control/status. AXI-Stream is intentionally not implemented in this milestone.} $core
set_property version 1.0 $core

set_property model_name leading_edge_ip_lite [ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects $core]
set_property model_name leading_edge_ip_lite [ipx::get_file_groups xilinx_anylanguagebehavioralsimulation -of_objects $core]

# The initial package_project call already infers AXI-Lite, clock, reset and IRQ
# interfaces.  Re-run AXI inference only to refresh the memory map after metadata
# edits.  Avoid reset_rtl/clock_rtl here: Vivado 2022.1 does not expose the same
# property names on those bus_interface objects in every installation.
ipx::infer_bus_interfaces xilinx.com:interface:aximm_rtl:1.0 $core

set axi_if [ipx::get_bus_interfaces s_axi -of_objects $core]
if {[llength $axi_if] > 0} {
    set_property interface_mode slave $axi_if
}

ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core

set_property ip_repo_paths [list $ip_repo_dir] [current_project]
update_ip_catalog

puts "Packaged leading_edge_ip_lite into: $ip_dir"
