// =============================================================================
// Leading Edge Reconstruction from Sparse PMT Samples
// Phase 1: AXI-Lite Register Interface
//
// Target: Xilinx ZCU106 (Zynq UltraScale+ MPSoC)
// Tool:   Vivado 2022.x
// PYNQ:   Access via mmio / register_map from Python notebook
//
// Register map (32-bit word addresses, byte-addressable AXI):
//
//   0x00  CTRL     [0]=start, [1]=mode_sel[0], [2]=mode_sel[1]
//                  mode_sel: 00=linear, 01=exponential, 10=logarithmic
//   0x04  STATUS   [0]=done, [1]=valid, [2]=overflow
//   0x08  T1       signed Q16.16 fixed-point, time sample 1 [ns]
//   0x0C  A1       unsigned Q16.16 fixed-point, amplitude sample 1
//   0x10  T2       signed Q16.16 fixed-point, time sample 2 [ns]
//   0x14  A2       unsigned Q16.16 fixed-point, amplitude sample 2
//   0x18  T3       signed Q16.16 fixed-point, time sample 3 [ns] (opt)
//   0x1C  A3       unsigned Q16.16 fixed-point, amplitude sample 3 (opt)
//   0x20  THRESH   unsigned Q16.16 fixed-point, discriminator threshold
//   0x24  T0_EST   signed Q16.16 fixed-point, reconstructed t0 [ns] (output)
//   0x28  AMAX_EST unsigned Q16.16 fixed-point, estimated amplitude (output)
//   0x2C  EVENT_ID read-only, echoed from last start
//
// Fixed-point convention Q16.16:
//   32-bit value = real_value * 65536
//   e.g. 18.284 ns -> 0x00124849 (approx)
//
// Latency: reconstruction completes within DONE_CYCLES clock cycles
//          after start pulse. DONE_CYCLES depends on mode:
//          linear: 2, exponential: 4, logarithmic: 6 (pipelined arithmetic)
// =============================================================================

`timescale 1ns / 1ps

module leading_edge_axi_lite #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6,   // covers 0x00..0x2C
    parameter integer DONE_CYCLES        = 8     // worst-case pipeline depth
)(
    // AXI4-Lite slave interface
    input  wire                             S_AXI_ACLK,
    input  wire                             S_AXI_ARESETN,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire [2:0]                       S_AXI_AWPROT,
    input  wire                             S_AXI_AWVALID,
    output wire                             S_AXI_AWREADY,

    input  wire [C_S_AXI_DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                             S_AXI_WVALID,
    output wire                             S_AXI_WREADY,

    output wire [1:0]                       S_AXI_BRESP,
    output wire                             S_AXI_BVALID,
    input  wire                             S_AXI_BREADY,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input  wire [2:0]                       S_AXI_ARPROT,
    input  wire                             S_AXI_ARVALID,
    output wire                             S_AXI_ARREADY,

    output wire [C_S_AXI_DATA_WIDTH-1:0]   S_AXI_RDATA,
    output wire [1:0]                       S_AXI_RRESP,
    output wire                             S_AXI_RVALID,
    input  wire                             S_AXI_RREADY
);

    // -------------------------------------------------------------------------
    // Internal register file (word-addressed, 12 registers = 0x00..0x2C)
    // -------------------------------------------------------------------------
    localparam REG_CTRL     = 4'd0;   // 0x00
    localparam REG_STATUS   = 4'd1;   // 0x04
    localparam REG_T1       = 4'd2;   // 0x08
    localparam REG_A1       = 4'd3;   // 0x0C
    localparam REG_T2       = 4'd4;   // 0x10
    localparam REG_A2       = 4'd5;   // 0x14
    localparam REG_T3       = 4'd6;   // 0x18
    localparam REG_A3       = 4'd7;   // 0x1C
    localparam REG_THRESH   = 4'd8;   // 0x20
    localparam REG_T0_EST   = 4'd9;   // 0x24
    localparam REG_AMAX_EST = 4'd10;  // 0x28
    localparam REG_EVENT_ID = 4'd11;  // 0x2C

    reg [31:0] regfile [0:11];

    // AXI handshake state
    reg        aw_en;
    reg [5:0]  axi_awaddr;
    reg        axi_awready;
    reg        axi_wready;
    reg [1:0]  axi_bresp;
    reg        axi_bvalid;
    reg [5:0]  axi_araddr;
    reg        axi_arready;
    reg [31:0] axi_rdata;
    reg [1:0]  axi_rresp;
    reg        axi_rvalid;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    // -------------------------------------------------------------------------
    // AXI Write address channel
    // -------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready <= 1'b0;
            aw_en       <= 1'b1;
        end else begin
            if (!axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awready <= 1'b1;
                aw_en       <= 1'b0;
                axi_awaddr  <= S_AXI_AWADDR;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                axi_awready <= 1'b0;
                aw_en       <= 1'b1;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end

    // AXI Write data channel
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_wready <= 1'b0;
        end else begin
            if (!axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en)
                axi_wready <= 1'b1;
            else
                axi_wready <= 1'b0;
        end
    end

    // Write response
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_bvalid <= 1'b0;
            axi_bresp  <= 2'b00;
        end else begin
            if (axi_awready && S_AXI_AWVALID && axi_wready && S_AXI_WVALID && !axi_bvalid) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b00; // OKAY
            end else if (S_AXI_BREADY && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    // Register file write
    integer i;
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            for (i = 0; i < 12; i = i + 1)
                regfile[i] <= 32'h0;
        end else if (axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID) begin
            // Word address from byte address [5:2]
            case (axi_awaddr[5:2])
                REG_CTRL,
                REG_T1, REG_A1, REG_T2, REG_A2,
                REG_T3, REG_A3, REG_THRESH:
                    regfile[axi_awaddr[5:2]] <= S_AXI_WDATA;
                // STATUS, T0_EST, AMAX_EST, EVENT_ID are read-only from AXI
                default: ; // ignore writes to read-only regs
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // AXI Read channel
    // -------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready <= 1'b0;
            axi_araddr  <= 6'h0;
        end else begin
            if (!axi_arready && S_AXI_ARVALID) begin
                axi_arready <= 1'b1;
                axi_araddr  <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_rvalid <= 1'b0;
            axi_rresp  <= 2'b00;
        end else begin
            if (axi_arready && S_AXI_ARVALID && !axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b00;
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_rdata <= 32'h0;
        else if (!axi_rvalid) begin
            // Route register file to read data bus
            case (axi_araddr[5:2])
                REG_CTRL:     axi_rdata <= regfile[REG_CTRL];
                REG_STATUS:   axi_rdata <= regfile[REG_STATUS];
                REG_T1:       axi_rdata <= regfile[REG_T1];
                REG_A1:       axi_rdata <= regfile[REG_A1];
                REG_T2:       axi_rdata <= regfile[REG_T2];
                REG_A2:       axi_rdata <= regfile[REG_A2];
                REG_T3:       axi_rdata <= regfile[REG_T3];
                REG_A3:       axi_rdata <= regfile[REG_A3];
                REG_THRESH:   axi_rdata <= regfile[REG_THRESH];
                REG_T0_EST:   axi_rdata <= regfile[REG_T0_EST];
                REG_AMAX_EST: axi_rdata <= regfile[REG_AMAX_EST];
                REG_EVENT_ID: axi_rdata <= regfile[REG_EVENT_ID];
                default:      axi_rdata <= 32'hDEAD_BEEF;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Reconstruction engine control
    // -------------------------------------------------------------------------
    wire        start        = regfile[REG_CTRL][0];
    wire [1:0]  mode_sel     = regfile[REG_CTRL][2:1];

    wire signed [31:0] t1     = $signed(regfile[REG_T1]);
    wire signed [31:0] a1     = $signed(regfile[REG_A1]);
    wire signed [31:0] t2     = $signed(regfile[REG_T2]);
    wire signed [31:0] a2     = $signed(regfile[REG_A2]);
    wire signed [31:0] t3     = $signed(regfile[REG_T3]);
    wire signed [31:0] a3     = $signed(regfile[REG_A3]);
    wire signed [31:0] thresh = $signed(regfile[REG_THRESH]);

    // Detect rising edge on start bit
    reg start_prev;
    wire start_pulse;
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) start_prev <= 1'b0;
        else                 start_prev <= start;
    end
    assign start_pulse = start && !start_prev;

    // Done counter
    reg [$clog2(DONE_CYCLES+1)-1:0] done_cnt;
    reg busy;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            done_cnt <= 0;
            busy     <= 1'b0;
        end else if (start_pulse) begin
            done_cnt <= DONE_CYCLES;
            busy     <= 1'b1;
            // Clear done flag on new start
            regfile[REG_STATUS] <= 32'h0;
        end else if (busy) begin
            if (done_cnt == 1) begin
                busy     <= 1'b0;
                done_cnt <= 0;
                regfile[REG_STATUS][0] <= 1'b1; // done
            end else begin
                done_cnt <= done_cnt - 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Reconstruction core instance
    // -------------------------------------------------------------------------
    wire signed [31:0] t0_est_wire;
    wire signed [31:0] amax_est_wire;
    wire               result_valid;
    wire               result_overflow;

    leading_edge_core core_inst (
        .clk        (S_AXI_ACLK),
        .rst_n      (S_AXI_ARESETN),
        .start      (start_pulse),
        .mode_sel   (mode_sel),
        .t1         (t1),
        .a1         (a1),
        .t2         (t2),
        .a2         (a2),
        .t3         (t3),
        .a3         (a3),
        .threshold  (thresh),
        .t0_est     (t0_est_wire),
        .amax_est   (amax_est_wire),
        .valid      (result_valid),
        .overflow   (result_overflow)
    );

    // Capture outputs when core signals valid
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            regfile[REG_T0_EST]   <= 32'h0;
            regfile[REG_AMAX_EST] <= 32'h0;
        end else if (result_valid) begin
            regfile[REG_T0_EST]    <= t0_est_wire;
            regfile[REG_AMAX_EST]  <= amax_est_wire;
            regfile[REG_STATUS][1] <= 1'b1;
            regfile[REG_STATUS][2] <= result_overflow;
        end
    end

endmodule
