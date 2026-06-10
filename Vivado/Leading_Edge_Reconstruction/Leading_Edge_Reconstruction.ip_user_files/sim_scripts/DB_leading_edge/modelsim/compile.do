vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xilinx_vip
vlib modelsim_lib/msim/xpm
vlib modelsim_lib/msim/axi_infrastructure_v1_1_0
vlib modelsim_lib/msim/axi_vip_v1_1_12
vlib modelsim_lib/msim/zynq_ultra_ps_e_vip_v1_0_12
vlib modelsim_lib/msim/xil_defaultlib
vlib modelsim_lib/msim/generic_baseblocks_v2_1_0
vlib modelsim_lib/msim/axi_register_slice_v2_1_26
vlib modelsim_lib/msim/fifo_generator_v13_2_7
vlib modelsim_lib/msim/axi_data_fifo_v2_1_25
vlib modelsim_lib/msim/axi_crossbar_v2_1_27
vlib modelsim_lib/msim/lib_cdc_v1_0_2
vlib modelsim_lib/msim/proc_sys_reset_v5_0_13
vlib modelsim_lib/msim/axi_protocol_converter_v2_1_26
vlib modelsim_lib/msim/axi_clock_converter_v2_1_25
vlib modelsim_lib/msim/blk_mem_gen_v8_4_5
vlib modelsim_lib/msim/axi_dwidth_converter_v2_1_26

vmap xilinx_vip modelsim_lib/msim/xilinx_vip
vmap xpm modelsim_lib/msim/xpm
vmap axi_infrastructure_v1_1_0 modelsim_lib/msim/axi_infrastructure_v1_1_0
vmap axi_vip_v1_1_12 modelsim_lib/msim/axi_vip_v1_1_12
vmap zynq_ultra_ps_e_vip_v1_0_12 modelsim_lib/msim/zynq_ultra_ps_e_vip_v1_0_12
vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib
vmap generic_baseblocks_v2_1_0 modelsim_lib/msim/generic_baseblocks_v2_1_0
vmap axi_register_slice_v2_1_26 modelsim_lib/msim/axi_register_slice_v2_1_26
vmap fifo_generator_v13_2_7 modelsim_lib/msim/fifo_generator_v13_2_7
vmap axi_data_fifo_v2_1_25 modelsim_lib/msim/axi_data_fifo_v2_1_25
vmap axi_crossbar_v2_1_27 modelsim_lib/msim/axi_crossbar_v2_1_27
vmap lib_cdc_v1_0_2 modelsim_lib/msim/lib_cdc_v1_0_2
vmap proc_sys_reset_v5_0_13 modelsim_lib/msim/proc_sys_reset_v5_0_13
vmap axi_protocol_converter_v2_1_26 modelsim_lib/msim/axi_protocol_converter_v2_1_26
vmap axi_clock_converter_v2_1_25 modelsim_lib/msim/axi_clock_converter_v2_1_25
vmap blk_mem_gen_v8_4_5 modelsim_lib/msim/blk_mem_gen_v8_4_5
vmap axi_dwidth_converter_v2_1_26 modelsim_lib/msim/axi_dwidth_converter_v2_1_26

vlog -work xilinx_vip  -incr -mfcu -sv -L axi_vip_v1_1_12 -L zynq_ultra_ps_e_vip_v1_0_12 -L xilinx_vip "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"E:/Xilinx/Vivado/2022.1/data/xilinx_vip/hdl/axi4stream_vip_axi4streampc.sv" \
"E:/Xilinx/Vivado/2022.1/data/xilinx_vip/hdl/axi_vip_axi4pc.sv" \
"E:/Xilinx/Vivado/2022.1/data/xilinx_vip/hdl/xil_common_vip_pkg.sv" \
"E:/Xilinx/Vivado/2022.1/data/xilinx_vip/hdl/axi4stream_vip_pkg.sv" \
"E:/Xilinx/Vivado/2022.1/data/xilinx_vip/hdl/axi_vip_pkg.sv" \
"E:/Xilinx/Vivado/2022.1/data/xilinx_vip/hdl/axi4stream_vip_if.sv" \
"E:/Xilinx/Vivado/2022.1/data/xilinx_vip/hdl/axi_vip_if.sv" \
"E:/Xilinx/Vivado/2022.1/data/xilinx_vip/hdl/clk_vip_if.sv" \
"E:/Xilinx/Vivado/2022.1/data/xilinx_vip/hdl/rst_vip_if.sv" \

vlog -work xpm  -incr -mfcu -sv -L axi_vip_v1_1_12 -L zynq_ultra_ps_e_vip_v1_0_12 -L xilinx_vip "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"E:/Xilinx/Vivado/2022.1/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"E:/Xilinx/Vivado/2022.1/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm  -93 \
"E:/Xilinx/Vivado/2022.1/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work axi_infrastructure_v1_1_0  -incr -mfcu "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl/axi_infrastructure_v1_1_vl_rfs.v" \

vlog -work axi_vip_v1_1_12  -incr -mfcu -sv -L axi_vip_v1_1_12 -L zynq_ultra_ps_e_vip_v1_0_12 -L xilinx_vip "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/1033/hdl/axi_vip_v1_1_vl_rfs.sv" \

vlog -work zynq_ultra_ps_e_vip_v1_0_12  -incr -mfcu -sv -L axi_vip_v1_1_12 -L zynq_ultra_ps_e_vip_v1_0_12 -L xilinx_vip "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl/zynq_ultra_ps_e_vip_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib  -incr -mfcu "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../bd/DB_leading_edge/ip/DB_leading_edge_zynq_ultra_ps_e_0_0/sim/DB_leading_edge_zynq_ultra_ps_e_0_0_vip_wrapper.v" \

vlog -work generic_baseblocks_v2_1_0  -incr -mfcu "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/b752/hdl/generic_baseblocks_v2_1_vl_rfs.v" \

vlog -work axi_register_slice_v2_1_26  -incr -mfcu "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/0a3f/hdl/axi_register_slice_v2_1_vl_rfs.v" \

vlog -work fifo_generator_v13_2_7  -incr -mfcu "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/83df/simulation/fifo_generator_vlog_beh.v" \

vcom -work fifo_generator_v13_2_7  -93 \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/83df/hdl/fifo_generator_v13_2_rfs.vhd" \

vlog -work fifo_generator_v13_2_7  -incr -mfcu "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/83df/hdl/fifo_generator_v13_2_rfs.v" \

vlog -work axi_data_fifo_v2_1_25  -incr -mfcu "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/5390/hdl/axi_data_fifo_v2_1_vl_rfs.v" \

vlog -work axi_crossbar_v2_1_27  -incr -mfcu "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/3fa0/hdl/axi_crossbar_v2_1_vl_rfs.v" \

vlog -work xil_defaultlib  -incr -mfcu "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../bd/DB_leading_edge/ip/DB_leading_edge_xbar_0/sim/DB_leading_edge_xbar_0.v" \

vcom -work lib_cdc_v1_0_2  -93 \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ef1e/hdl/lib_cdc_v1_0_rfs.vhd" \

vcom -work proc_sys_reset_v5_0_13  -93 \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8842/hdl/proc_sys_reset_v5_0_vh_rfs.vhd" \

vcom -work xil_defaultlib  -93 \
"../../../bd/DB_leading_edge/ip/DB_leading_edge_rst_ps8_0_99M_0/sim/DB_leading_edge_rst_ps8_0_99M_0.vhd" \

vlog -work xil_defaultlib  -incr -mfcu "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../bd/DB_leading_edge/ipshared/28de/hdl/leading_edge_core.v" \
"../../../bd/DB_leading_edge/ipshared/28de/hdl/myip_leading_edge_axi_lite_v1_0_S00_AXI.v" \
"../../../bd/DB_leading_edge/ipshared/28de/hdl/myip_leading_edge_axi_lite_v1_0.v" \
"../../../bd/DB_leading_edge/ip/DB_leading_edge_myip_leading_edge_ax_0_0_1/sim/DB_leading_edge_myip_leading_edge_ax_0_0.v" \

vlog -work axi_protocol_converter_v2_1_26  -incr -mfcu "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/90c8/hdl/axi_protocol_converter_v2_1_vl_rfs.v" \

vlog -work axi_clock_converter_v2_1_25  -incr -mfcu "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/e893/hdl/axi_clock_converter_v2_1_vl_rfs.v" \

vlog -work blk_mem_gen_v8_4_5  -incr -mfcu "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/25a8/simulation/blk_mem_gen_v8_4.v" \

vlog -work axi_dwidth_converter_v2_1_26  -incr -mfcu "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/b3c7/hdl/axi_dwidth_converter_v2_1_vl_rfs.v" \

vlog -work xil_defaultlib  -incr -mfcu "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/ec67/hdl" "+incdir+../../../../Leading_Edge_Reconstruction.gen/sources_1/bd/DB_leading_edge/ipshared/8cdf/hdl" "+incdir+E:/Xilinx/Vivado/2022.1/data/xilinx_vip/include" \
"../../../bd/DB_leading_edge/ip/DB_leading_edge_auto_ds_0/sim/DB_leading_edge_auto_ds_0.v" \
"../../../bd/DB_leading_edge/ip/DB_leading_edge_auto_pc_0/sim/DB_leading_edge_auto_pc_0.v" \
"../../../bd/DB_leading_edge/ip/DB_leading_edge_auto_ds_1/sim/DB_leading_edge_auto_ds_1.v" \
"../../../bd/DB_leading_edge/ip/DB_leading_edge_auto_pc_1/sim/DB_leading_edge_auto_pc_1.v" \
"../../../bd/DB_leading_edge/sim/DB_leading_edge.v" \

vlog -work xil_defaultlib \
"glbl.v"

