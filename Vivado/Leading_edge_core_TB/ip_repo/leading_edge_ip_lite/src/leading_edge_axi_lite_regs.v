// -----------------------------------------------------------------------------
// AXI4-Lite register bank for leading_edge_ip_lite
// -----------------------------------------------------------------------------
// Register map, 32-bit words:
//
//   0x00 CONTROL    RW/W1P  [0] start pulse, [2:1] mode_sel, [8] clear_done
//   0x04 STATUS     RO      [0] busy, [1] done, [2] overflow, [3] core_valid
//   0x08 THRESHOLD  RW      signed Q16.16 threshold
//   0x0C T1         RW      signed Q16.16 sample time 1
//   0x10 A1         RW      signed Q16.16 sample amplitude 1
//   0x14 T2         RW      signed Q16.16 sample time 2
//   0x18 A2         RW      signed Q16.16 sample amplitude 2
//   0x1C T3         RW      signed Q16.16 sample time 3
//   0x20 A3         RW      signed Q16.16 sample amplitude 3
//   0x24 T0_EST     RO      signed Q16.16 reconstructed t0
//   0x28 AMAX_EST   RO      signed Q16.16 estimated maximum amplitude
//   0x2C VERSION    RO      0x0001_0000
//
// Notes:
//   * start is write-one-to-pulse and lasts one clock.
//   * done is sticky until CONTROL[8] is written as 1 or a new start is issued.
//   * WSTRB is honored for writable registers.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module leading_edge_axi_lite_regs #(
    parameter integer C_S_AXI_ADDR_WIDTH = 6
) (
    input  wire                          s_axi_aclk,
    input  wire                          s_axi_aresetn,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                          s_axi_awvalid,
    output reg                           s_axi_awready,

    input  wire [31:0]                   s_axi_wdata,
    input  wire [3:0]                    s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output reg                           s_axi_wready,

    output reg [1:0]                     s_axi_bresp,
    output reg                           s_axi_bvalid,
    input  wire                          s_axi_bready,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                          s_axi_arvalid,
    output reg                           s_axi_arready,

    output reg [31:0]                    s_axi_rdata,
    output reg [1:0]                     s_axi_rresp,
    output reg                           s_axi_rvalid,
    input  wire                          s_axi_rready,

    output reg                           core_start,
    output wire [1:0]                    core_mode_sel,
    output wire signed [31:0]            core_threshold,
    output wire signed [31:0]            core_t1,
    output wire signed [31:0]            core_a1,
    output wire signed [31:0]            core_t2,
    output wire signed [31:0]            core_a2,
    output wire signed [31:0]            core_t3,
    output wire signed [31:0]            core_a3,

    input  wire signed [31:0]            core_t0_est,
    input  wire signed [31:0]            core_amax_est,
    input  wire                          core_valid,
    input  wire                          core_overflow,

    output wire                          irq
);

localparam [5:0] ADDR_CONTROL   = 6'h00;
localparam [5:0] ADDR_STATUS    = 6'h04;
localparam [5:0] ADDR_THRESHOLD = 6'h08;
localparam [5:0] ADDR_T1        = 6'h0C;
localparam [5:0] ADDR_A1        = 6'h10;
localparam [5:0] ADDR_T2        = 6'h14;
localparam [5:0] ADDR_A2        = 6'h18;
localparam [5:0] ADDR_T3        = 6'h1C;
localparam [5:0] ADDR_A3        = 6'h20;
localparam [5:0] ADDR_T0_EST    = 6'h24;
localparam [5:0] ADDR_AMAX_EST  = 6'h28;
localparam [5:0] ADDR_VERSION   = 6'h2C;

localparam [31:0] IP_VERSION = 32'h0001_0000;

reg [1:0] mode_sel_reg;
reg signed [31:0] threshold_reg;
reg signed [31:0] t1_reg;
reg signed [31:0] a1_reg;
reg signed [31:0] t2_reg;
reg signed [31:0] a2_reg;
reg signed [31:0] t3_reg;
reg signed [31:0] a3_reg;

reg signed [31:0] t0_est_reg;
reg signed [31:0] amax_est_reg;
reg done_reg;
reg overflow_reg;
reg busy_reg;
reg core_valid_reg;

wire write_fire;
wire read_fire;
wire [5:0] write_addr;
wire [5:0] read_addr;

assign write_fire = s_axi_awready && s_axi_awvalid && s_axi_wready && s_axi_wvalid;
assign read_fire  = s_axi_arready && s_axi_arvalid;
assign write_addr = {s_axi_awaddr[C_S_AXI_ADDR_WIDTH-1:2], 2'b00};
assign read_addr  = {s_axi_araddr[C_S_AXI_ADDR_WIDTH-1:2], 2'b00};

assign core_mode_sel  = mode_sel_reg;
assign core_threshold = threshold_reg;
assign core_t1        = t1_reg;
assign core_a1        = a1_reg;
assign core_t2        = t2_reg;
assign core_a2        = a2_reg;
assign core_t3        = t3_reg;
assign core_a3        = a3_reg;
assign irq            = done_reg;

function automatic [31:0] apply_wstrb;
    input [31:0] old_value;
    input [31:0] new_value;
    input [3:0] strobe;
    begin
        apply_wstrb[7:0]   = strobe[0] ? new_value[7:0]   : old_value[7:0];
        apply_wstrb[15:8]  = strobe[1] ? new_value[15:8]  : old_value[15:8];
        apply_wstrb[23:16] = strobe[2] ? new_value[23:16] : old_value[23:16];
        apply_wstrb[31:24] = strobe[3] ? new_value[31:24] : old_value[31:24];
    end
endfunction

function automatic [31:0] status_word;
    input busy;
    input done;
    input overflow;
    input core_valid_seen;
    begin
        status_word = {28'h0, core_valid_seen, overflow, done, busy};
    end
endfunction

// AXI write channel: one simple outstanding transaction at a time.
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
        s_axi_awready <= 1'b0;
        s_axi_wready  <= 1'b0;
        s_axi_bvalid  <= 1'b0;
        s_axi_bresp   <= 2'b00;
    end else begin
        if (!s_axi_bvalid && !s_axi_awready && !s_axi_wready) begin
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b1;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
        end

        if (write_fire) begin
            s_axi_bvalid <= 1'b1;
            s_axi_bresp  <= 2'b00;
        end else if (s_axi_bvalid && s_axi_bready) begin
            s_axi_bvalid <= 1'b0;
        end
    end
end

// AXI read channel: read data is returned one cycle after AR handshake.
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
        s_axi_arready <= 1'b0;
        s_axi_rvalid  <= 1'b0;
        s_axi_rresp   <= 2'b00;
        s_axi_rdata   <= 32'h0;
    end else begin
        if (!s_axi_rvalid && !s_axi_arready) begin
            s_axi_arready <= 1'b1;
        end else begin
            s_axi_arready <= 1'b0;
        end

        if (read_fire) begin
            s_axi_rvalid <= 1'b1;
            s_axi_rresp  <= 2'b00;

            case (read_addr)
                ADDR_CONTROL:   s_axi_rdata <= {29'h0, mode_sel_reg, 1'b0};
                ADDR_STATUS:    s_axi_rdata <= status_word(busy_reg, done_reg, overflow_reg, core_valid_reg);
                ADDR_THRESHOLD: s_axi_rdata <= threshold_reg;
                ADDR_T1:        s_axi_rdata <= t1_reg;
                ADDR_A1:        s_axi_rdata <= a1_reg;
                ADDR_T2:        s_axi_rdata <= t2_reg;
                ADDR_A2:        s_axi_rdata <= a2_reg;
                ADDR_T3:        s_axi_rdata <= t3_reg;
                ADDR_A3:        s_axi_rdata <= a3_reg;
                ADDR_T0_EST:    s_axi_rdata <= t0_est_reg;
                ADDR_AMAX_EST:  s_axi_rdata <= amax_est_reg;
                ADDR_VERSION:   s_axi_rdata <= IP_VERSION;
                default:        s_axi_rdata <= 32'h0;
            endcase
        end else if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end
    end
end

// Register write side and core status capture.
always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
        mode_sel_reg   <= 2'b00;
        threshold_reg  <= 32'sh00008000; // 0.5 in Q16.16
        t1_reg         <= 32'sh0;
        a1_reg         <= 32'sh0;
        t2_reg         <= 32'sh0;
        a2_reg         <= 32'sh0;
        t3_reg         <= 32'sh0;
        a3_reg         <= 32'sh0;
        t0_est_reg     <= 32'sh0;
        amax_est_reg   <= 32'sh0;
        done_reg       <= 1'b0;
        overflow_reg   <= 1'b0;
        busy_reg       <= 1'b0;
        core_valid_reg <= 1'b0;
        core_start     <= 1'b0;
    end else begin
        core_start <= 1'b0;

        if (write_fire) begin
            case (write_addr)
                ADDR_CONTROL: begin
                    if (s_axi_wstrb[0]) begin
                        mode_sel_reg <= s_axi_wdata[2:1];

                        if (s_axi_wdata[0]) begin
                            core_start     <= 1'b1;
                            busy_reg       <= 1'b1;
                            done_reg       <= 1'b0;
                            overflow_reg   <= 1'b0;
                            core_valid_reg <= 1'b0;
                        end
                    end

                    if (s_axi_wstrb[1]) begin
                        if (s_axi_wdata[8]) begin
                            done_reg       <= 1'b0;
                            overflow_reg   <= 1'b0;
                            core_valid_reg <= 1'b0;
                        end
                    end
                end

                ADDR_THRESHOLD: threshold_reg <= apply_wstrb(threshold_reg, s_axi_wdata, s_axi_wstrb);
                ADDR_T1:        t1_reg        <= apply_wstrb(t1_reg,        s_axi_wdata, s_axi_wstrb);
                ADDR_A1:        a1_reg        <= apply_wstrb(a1_reg,        s_axi_wdata, s_axi_wstrb);
                ADDR_T2:        t2_reg        <= apply_wstrb(t2_reg,        s_axi_wdata, s_axi_wstrb);
                ADDR_A2:        a2_reg        <= apply_wstrb(a2_reg,        s_axi_wdata, s_axi_wstrb);
                ADDR_T3:        t3_reg        <= apply_wstrb(t3_reg,        s_axi_wdata, s_axi_wstrb);
                ADDR_A3:        a3_reg        <= apply_wstrb(a3_reg,        s_axi_wdata, s_axi_wstrb);
                default: begin
                end
            endcase
        end

        if (core_valid) begin
            t0_est_reg     <= core_t0_est;
            amax_est_reg   <= core_amax_est;
            overflow_reg   <= core_overflow;
            busy_reg       <= 1'b0;
            done_reg       <= 1'b1;
            core_valid_reg <= 1'b1;
        end
    end
end

endmodule
