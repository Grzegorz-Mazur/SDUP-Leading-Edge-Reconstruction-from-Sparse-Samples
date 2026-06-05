// =============================================================================
// Leading Edge Reconstruction - AXI-Stream Extension (Phase 2)
//
// This module wraps the leading_edge_core with AXI4-Stream master/slave
// interfaces for DMA-based pipelined operation.
//
// Input stream (S_AXIS_IN):
//   Each beat is a 256-bit packet:
//     [255:224] event_id   (32-bit)
//     [223:192] t1         (Q16.16 signed)
//     [191:160] a1         (Q16.16)
//     [159:128] t2         (Q16.16 signed)
//     [127:96]  a2         (Q16.16)
//     [95:64]   t3         (Q16.16 signed, optional, set 0 if not used)
//     [63:32]   a3         (Q16.16, optional, set 0 if not used)
//     [31:0]    flags      [1:0]=mode_sel, [2]=has_t3
//
// Output stream (M_AXIS_OUT):
//   Each beat is a 128-bit packet:
//     [127:96]  event_id   (echoed)
//     [95:64]   t0_est     (Q16.16 signed)
//     [63:32]   amax_est   (Q16.16)
//     [31:1]    reserved
//     [0]       overflow
//
// The pipeline is fully pipelined: a new input can be accepted every cycle.
// Back-pressure is handled by holding S_AXIS_TREADY low when the output
// FIFO is near-full (not implemented here - tie tready high for now).
// =============================================================================

`timescale 1ns / 1ps

module leading_edge_axis #(
    parameter integer PIPELINE_DEPTH = 8
)(
    input  wire        aclk,
    input  wire        aresetn,

    // Slave AXI-Stream (input)
    input  wire [255:0] S_AXIS_TDATA,
    input  wire         S_AXIS_TVALID,
    output wire         S_AXIS_TREADY,
    input  wire         S_AXIS_TLAST,

    // Master AXI-Stream (output)
    output reg  [127:0] M_AXIS_TDATA,
    output reg          M_AXIS_TVALID,
    input  wire         M_AXIS_TREADY,
    output reg          M_AXIS_TLAST
);

    // Unpack input beat
    wire [31:0] ev_id_in  = S_AXIS_TDATA[255:224];
    wire [31:0] t1_in     = S_AXIS_TDATA[223:192];
    wire [31:0] a1_in     = S_AXIS_TDATA[191:160];
    wire [31:0] t2_in     = S_AXIS_TDATA[159:128];
    wire [31:0] a2_in     = S_AXIS_TDATA[127:96];
    wire [31:0] t3_in     = S_AXIS_TDATA[95:64];
    wire [31:0] a3_in     = S_AXIS_TDATA[63:32];
    wire [1:0]  mode_in   = S_AXIS_TDATA[1:0];
    wire        last_in   = S_AXIS_TLAST;

    // Accept input whenever core is not stalled
    assign S_AXIS_TREADY = aresetn;  // simplified: always ready

    wire start_core = S_AXIS_TVALID && S_AXIS_TREADY;

    // Propagate event_id and last through pipeline delay
    reg [31:0] evid_pipe [0:PIPELINE_DEPTH-1];
    reg        last_pipe [0:PIPELINE_DEPTH-1];
    integer    i;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            for (i = 0; i < PIPELINE_DEPTH; i = i + 1) begin
                evid_pipe[i] <= 32'h0;
                last_pipe[i] <= 1'b0;
            end
        end else begin
            evid_pipe[0] <= ev_id_in;
            last_pipe[0] <= last_in;
            for (i = 1; i < PIPELINE_DEPTH; i = i + 1) begin
                evid_pipe[i] <= evid_pipe[i-1];
                last_pipe[i] <= last_pipe[i-1];
            end
        end
    end

    // Core instance
    wire signed [31:0] t0_est_w, amax_est_w;
    wire               core_valid, core_ovf;

    // Fixed threshold for stream mode (can be made a register via AXI-Lite)
    localparam [31:0] DEFAULT_THRESH = 32'h00004CCD; // 0.3 in Q16.16

    leading_edge_core core_inst (
        .clk       (aclk),
        .rst_n     (aresetn),
        .start     (start_core),
        .mode_sel  (mode_in),
        .t1        ($signed(t1_in)),
        .a1        ($signed(a1_in)),
        .t2        ($signed(t2_in)),
        .a2        ($signed(a2_in)),
        .t3        ($signed(t3_in)),
        .a3        ($signed(a3_in)),
        .threshold ($signed(DEFAULT_THRESH)),
        .t0_est    (t0_est_w),
        .amax_est  (amax_est_w),
        .valid     (core_valid),
        .overflow  (core_ovf)
    );

    // Pack output beat
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            M_AXIS_TDATA  <= 128'h0;
            M_AXIS_TVALID <= 1'b0;
            M_AXIS_TLAST  <= 1'b0;
        end else begin
            M_AXIS_TVALID <= core_valid;
            M_AXIS_TLAST  <= last_pipe[PIPELINE_DEPTH-1];
            M_AXIS_TDATA  <= {
                evid_pipe[PIPELINE_DEPTH-1],  // [127:96]
                t0_est_w,                      // [95:64]
                amax_est_w,                    // [63:32]
                31'h0, core_ovf                // [31:0]
            };
        end
    end

endmodule
