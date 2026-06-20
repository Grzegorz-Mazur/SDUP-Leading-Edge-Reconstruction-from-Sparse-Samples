`timescale 1 ns / 1 ps

module myip_leading_edge_axi_stream_v1_0 #
(
    // Users to add parameters here

    // User parameters ends
    // Do not modify the parameters beyond this line

    // Parameters of Axi Slave Bus Interface S00_AXIS
    parameter integer C_S00_AXIS_TDATA_WIDTH = 32,

    // Parameters of Axi Master Bus Interface M00_AXIS
    parameter integer C_M00_AXIS_TDATA_WIDTH = 32,
    parameter integer C_M00_AXIS_START_COUNT = 32
)
(
    // Users to add ports here

    // User ports ends
    // Do not modify the ports beyond this line

    // Ports of Axi Slave Bus Interface S00_AXIS
    input wire  s00_axis_aclk,
    input wire  s00_axis_aresetn,
    output wire s00_axis_tready,
    input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] s00_axis_tdata,
    input wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0] s00_axis_tstrb,
    input wire  s00_axis_tlast,
    input wire  s00_axis_tvalid,

    // Ports of Axi Master Bus Interface M00_AXIS
    input wire  m00_axis_aclk,
    input wire  m00_axis_aresetn,
    output wire m00_axis_tvalid,
    output wire [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata,
    output wire [(C_M00_AXIS_TDATA_WIDTH/8)-1 : 0] m00_axis_tstrb,
    output wire m00_axis_tlast,
    input wire  m00_axis_tready
);

    // -------------------------------------------------------------------------
    // Internal user signals between S00_AXIS, leading_edge_core and M00_AXIS
    // -------------------------------------------------------------------------

    wire [1:0] usr_mode_sel;
    wire signed [31:0] usr_t1;
    wire signed [31:0] usr_a1;
    wire signed [31:0] usr_t2;
    wire signed [31:0] usr_a2;
    wire signed [31:0] usr_t3;
    wire signed [31:0] usr_a3;
    wire signed [31:0] usr_threshold;

    wire usr_frame_done;
    wire usr_frame_error;
    wire usr_frame_clear;

    reg  core_start;
    wire signed [31:0] core_t0_est;
    wire signed [31:0] core_amax_est;
    wire core_valid;
    wire core_overflow;

    wire usr_result_done;

    // -------------------------------------------------------------------------
    // Instantiation of Axi Bus Interface S00_AXIS
    // Receives 8 words:
    // word 0: mode_sel [1:0]
    // word 1: t1
    // word 2: a1
    // word 3: t2
    // word 4: a2
    // word 5: t3
    // word 6: a3
    // word 7: threshold, TLAST = 1
    // -------------------------------------------------------------------------

    myip_leading_edge_axi_stream_v1_0_S00_AXIS # (
        .C_S_AXIS_TDATA_WIDTH(C_S00_AXIS_TDATA_WIDTH)
    ) myip_leading_edge_axi_stream_v1_0_S00_AXIS_inst (
        .S_AXIS_ACLK    (s00_axis_aclk),
        .S_AXIS_ARESETN (s00_axis_aresetn),
        .S_AXIS_TREADY  (s00_axis_tready),
        .S_AXIS_TDATA   (s00_axis_tdata),
        .S_AXIS_TSTRB   (s00_axis_tstrb),
        .S_AXIS_TLAST   (s00_axis_tlast),
        .S_AXIS_TVALID  (s00_axis_tvalid),

        .usr_mode_sel    (usr_mode_sel),
        .usr_t1          (usr_t1),
        .usr_a1          (usr_a1),
        .usr_t2          (usr_t2),
        .usr_a2          (usr_a2),
        .usr_t3          (usr_t3),
        .usr_a3          (usr_a3),
        .usr_threshold   (usr_threshold),
        .usr_frame_done  (usr_frame_done),
        .usr_frame_error (usr_frame_error),
        .usr_frame_clear (usr_frame_clear)
    );

    // -------------------------------------------------------------------------
    // Leading Edge computational core
    // IMPORTANT: s00_axis_aclk and m00_axis_aclk should be connected
    // to the same clock in Block Design.
    // -------------------------------------------------------------------------

    leading_edge_core leading_edge_core_inst (
        .clk       (s00_axis_aclk),
        .rst_n     (s00_axis_aresetn),
        .start     (core_start),
        .mode_sel  (usr_mode_sel),
        .t1        (usr_t1),
        .a1        (usr_a1),
        .t2        (usr_t2),
        .a2        (usr_a2),
        .t3        (usr_t3),
        .a3        (usr_a3),
        .threshold (usr_threshold),
        .t0_est    (core_t0_est),
        .amax_est  (core_amax_est),
        .valid     (core_valid),
        .overflow  (core_overflow)
    );

    // -------------------------------------------------------------------------
    // Generate one-cycle start pulse for leading_edge_core after full frame
    // -------------------------------------------------------------------------

    reg frame_done_d;

    always @(posedge s00_axis_aclk)
    begin
        if (!s00_axis_aresetn)
        begin
            frame_done_d <= 1'b0;
            core_start   <= 1'b0;
        end
        else
        begin
            frame_done_d <= usr_frame_done;
            core_start   <= usr_frame_done & ~frame_done_d;
        end
    end

    // Clear input frame after output stream sends all result words
    assign usr_frame_clear = usr_result_done;

    // -------------------------------------------------------------------------
    // Instantiation of Axi Bus Interface M00_AXIS
    // Sends 3 words:
    // word 0: t0_est
    // word 1: amax_est
    // word 2: status {29'd0, frame_error, overflow, valid}, TLAST = 1
    // -------------------------------------------------------------------------

    myip_leading_edge_axi_stream_v1_0_M00_AXIS # (
        .C_M_AXIS_TDATA_WIDTH(C_M00_AXIS_TDATA_WIDTH),
        .C_M_START_COUNT(C_M00_AXIS_START_COUNT)
    ) myip_leading_edge_axi_stream_v1_0_M00_AXIS_inst (
        .M_AXIS_ACLK    (m00_axis_aclk),
        .M_AXIS_ARESETN (m00_axis_aresetn),
        .M_AXIS_TVALID  (m00_axis_tvalid),
        .M_AXIS_TDATA   (m00_axis_tdata),
        .M_AXIS_TSTRB   (m00_axis_tstrb),
        .M_AXIS_TLAST   (m00_axis_tlast),
        .M_AXIS_TREADY  (m00_axis_tready),

        .usr_result_valid (core_valid),
        .usr_t0_est       (core_t0_est),
        .usr_amax_est     (core_amax_est),
        .usr_overflow     (core_overflow),
        .usr_frame_error  (usr_frame_error),
        .usr_result_done  (usr_result_done)
    );

endmodule
