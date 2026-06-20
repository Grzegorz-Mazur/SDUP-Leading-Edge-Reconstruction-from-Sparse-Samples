// -----------------------------------------------------------------------------
// Leading Edge IP, AXI4-Lite control/status variant
// -----------------------------------------------------------------------------
// This is the packaging-friendly top module for the current milestone.
//
// Implemented now:
//   * AXI4-Lite register interface
//   * software-written input samples
//   * leading_edge_core start/result/status path
//
// Intentionally not implemented yet:
//   * AXI-Stream input/output data movers
//
// AXI-Stream can be added later beside this register bank.  The math core stays
// unchanged because it already has a clean start/input/result interface.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module leading_edge_ip_lite #(
    parameter integer C_S_AXI_ADDR_WIDTH = 6
) (
    input  wire                          s_axi_aclk,
    input  wire                          s_axi_aresetn,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                          s_axi_awvalid,
    output wire                          s_axi_awready,

    input  wire [31:0]                   s_axi_wdata,
    input  wire [3:0]                    s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output wire                          s_axi_wready,

    output wire [1:0]                    s_axi_bresp,
    output wire                          s_axi_bvalid,
    input  wire                          s_axi_bready,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                          s_axi_arvalid,
    output wire                          s_axi_arready,

    output wire [31:0]                   s_axi_rdata,
    output wire [1:0]                    s_axi_rresp,
    output wire                          s_axi_rvalid,
    input  wire                          s_axi_rready,

    output wire                          irq
);

wire core_start;
wire [1:0] core_mode_sel;
wire signed [31:0] core_threshold;
wire signed [31:0] core_t1;
wire signed [31:0] core_a1;
wire signed [31:0] core_t2;
wire signed [31:0] core_a2;
wire signed [31:0] core_t3;
wire signed [31:0] core_a3;
wire signed [31:0] core_t0_est;
wire signed [31:0] core_amax_est;
wire core_valid;
wire core_overflow;

leading_edge_axi_lite_regs #(
    .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH)
) u_axi_lite_regs (
    .s_axi_aclk      (s_axi_aclk),
    .s_axi_aresetn   (s_axi_aresetn),
    .s_axi_awaddr    (s_axi_awaddr),
    .s_axi_awvalid   (s_axi_awvalid),
    .s_axi_awready   (s_axi_awready),
    .s_axi_wdata     (s_axi_wdata),
    .s_axi_wstrb     (s_axi_wstrb),
    .s_axi_wvalid    (s_axi_wvalid),
    .s_axi_wready    (s_axi_wready),
    .s_axi_bresp     (s_axi_bresp),
    .s_axi_bvalid    (s_axi_bvalid),
    .s_axi_bready    (s_axi_bready),
    .s_axi_araddr    (s_axi_araddr),
    .s_axi_arvalid   (s_axi_arvalid),
    .s_axi_arready   (s_axi_arready),
    .s_axi_rdata     (s_axi_rdata),
    .s_axi_rresp     (s_axi_rresp),
    .s_axi_rvalid    (s_axi_rvalid),
    .s_axi_rready    (s_axi_rready),
    .core_start      (core_start),
    .core_mode_sel   (core_mode_sel),
    .core_threshold  (core_threshold),
    .core_t1         (core_t1),
    .core_a1         (core_a1),
    .core_t2         (core_t2),
    .core_a2         (core_a2),
    .core_t3         (core_t3),
    .core_a3         (core_a3),
    .core_t0_est     (core_t0_est),
    .core_amax_est   (core_amax_est),
    .core_valid      (core_valid),
    .core_overflow   (core_overflow),
    .irq             (irq)
);

leading_edge_core u_core (
    .clk       (s_axi_aclk),
    .rst_n     (s_axi_aresetn),
    .start     (core_start),
    .mode_sel  (core_mode_sel),
    .t1        (core_t1),
    .a1        (core_a1),
    .t2        (core_t2),
    .a2        (core_a2),
    .t3        (core_t3),
    .a3        (core_a3),
    .threshold (core_threshold),
    .t0_est    (core_t0_est),
    .amax_est  (core_amax_est),
    .valid     (core_valid),
    .overflow  (core_overflow)
);

endmodule
