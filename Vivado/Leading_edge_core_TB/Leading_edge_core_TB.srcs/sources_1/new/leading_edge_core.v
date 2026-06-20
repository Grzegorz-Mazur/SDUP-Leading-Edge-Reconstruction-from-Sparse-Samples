// -----------------------------------------------------------------------------
// Project: Leading Edge Reconstruction from Sparse PMT Samples
// Module:  leading_edge_core
// Format:  signed Q16.16 fixed-point
// -----------------------------------------------------------------------------
// File role:
//   This file is only the pipeline controller.
//
// Method implementation is deliberately kept in separate files:
//   mode 0 -> leading_edge_method_linear.v
//   mode 1 -> leading_edge_method_exp.v
//   mode 2 -> leading_edge_method_log.v
//
// Pipeline overview:
//   S0 input latch
//   S1 sample differences
//   S2 ln(A1), ln(A2), ln(A3)
//   S3 alignment register
//   S4 ln(threshold)
//   S5 select selected method result
//   S6 output register
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

 module leading_edge_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [1:0]  mode_sel,
    input  wire signed [31:0] t1, a1, t2, a2, t3, a3, threshold,
    output reg  signed [31:0] t0_est,
    output reg  signed [31:0] amax_est,
    output reg                valid,
    output reg                overflow
);

`include "leading_edge_math.vh"

localparam [1:0] MODE_LINEAR = 2'b00;
localparam [1:0] MODE_EXP    = 2'b01;
localparam [1:0] MODE_LOG    = 2'b10;

// -----------------------------------------------------------------------------
// S0: input latch
// -----------------------------------------------------------------------------

reg [1:0] s0_mode;
reg s0_valid;
reg signed [31:0] s0_t1, s0_a1, s0_t2, s0_a2, s0_t3, s0_a3, s0_threshold;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s0_valid <= 1'b0;
    end else begin
        s0_valid <= start;
        if (start) begin
            s0_mode      <= mode_sel;
            s0_t1        <= t1;
            s0_a1        <= a1;
            s0_t2        <= t2;
            s0_a2        <= a2;
            s0_t3        <= t3;
            s0_a3        <= a3;
            s0_threshold <= threshold;
        end
    end
end

// -----------------------------------------------------------------------------
// S1: sample differences used by all methods
// -----------------------------------------------------------------------------

reg [1:0] s1_mode;
reg s1_valid;
reg signed [31:0] s1_t1, s1_a1, s1_a2, s1_a3, s1_threshold;
reg signed [31:0] s1_dt21, s1_dt32, s1_da21;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s1_valid <= 1'b0;
    end else begin
        s1_valid    <= s0_valid;
        s1_mode     <= s0_mode;
        s1_t1       <= s0_t1;
        s1_a1       <= s0_a1;
        s1_a2       <= s0_a2;
        s1_a3       <= s0_a3;
        s1_threshold <= s0_threshold;

        s1_dt21     <= s0_t2 - s0_t1;
        s1_dt32     <= s0_t3 - s0_t2;
        s1_da21     <= s0_a2 - s0_a1;
    end
end

// -----------------------------------------------------------------------------
// S2: logarithms for methods that work in ln(A)
// -----------------------------------------------------------------------------

reg [1:0] s2_mode;
reg s2_valid;
reg signed [31:0] s2_t1, s2_a1, s2_a3, s2_threshold;
reg signed [31:0] s2_dt21, s2_dt32, s2_da21;
reg signed [31:0] s2_ln_a1, s2_ln_a2, s2_ln_a3;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s2_valid <= 1'b0;
    end else begin
        s2_valid     <= s1_valid;
        s2_mode      <= s1_mode;
        s2_t1        <= s1_t1;
        s2_a1        <= s1_a1;
        s2_a3        <= s1_a3;
        s2_threshold <= s1_threshold;
        s2_dt21      <= s1_dt21;
        s2_dt32      <= s1_dt32;
        s2_da21      <= s1_da21;

        s2_ln_a1     <= q16_ln(s1_a1[31:0]);
        s2_ln_a2     <= q16_ln(s1_a2[31:0]);
        s2_ln_a3     <= q16_ln(s1_a3[31:0]);
    end
end

// -----------------------------------------------------------------------------
// S3: alignment register
// -----------------------------------------------------------------------------

reg [1:0] s3_mode;
reg s3_valid;
reg signed [31:0] s3_t1, s3_a1, s3_a3, s3_threshold;
reg signed [31:0] s3_dt21, s3_dt32, s3_da21;
reg signed [31:0] s3_ln_a1, s3_ln_a2, s3_ln_a3;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s3_valid <= 1'b0;
    end else begin
        s3_valid     <= s2_valid;
        s3_mode      <= s2_mode;
        s3_t1        <= s2_t1;
        s3_a1        <= s2_a1;
        s3_a3        <= s2_a3;
        s3_threshold <= s2_threshold;
        s3_dt21      <= s2_dt21;
        s3_dt32      <= s2_dt32;
        s3_da21      <= s2_da21;
        s3_ln_a1     <= s2_ln_a1;
        s3_ln_a2     <= s2_ln_a2;
        s3_ln_a3     <= s2_ln_a3;
    end
end

// -----------------------------------------------------------------------------
// S4: threshold logarithm and final method inputs
// -----------------------------------------------------------------------------

reg [1:0] s4_mode;
reg s4_valid;
reg signed [31:0] s4_t1, s4_a1, s4_a3;
reg signed [31:0] s4_dt21, s4_dt32, s4_da21;
reg signed [31:0] s4_ln_a1, s4_ln_a2, s4_ln_a3, s4_ln_threshold;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s4_valid <= 1'b0;
    end else begin
        s4_valid        <= s3_valid;
        s4_mode         <= s3_mode;
        s4_t1           <= s3_t1;
        s4_a1           <= s3_a1;
        s4_a3           <= s3_a3;
        s4_dt21         <= s3_dt21;
        s4_dt32         <= s3_dt32;
        s4_da21         <= s3_da21;
        s4_ln_a1        <= s3_ln_a1;
        s4_ln_a2        <= s3_ln_a2;
        s4_ln_a3        <= s3_ln_a3;
        s4_ln_threshold <= q16_ln(s3_threshold[31:0]);
    end
end

// -----------------------------------------------------------------------------
// Method blocks: one block per algorithm, no mixed formulas here
// -----------------------------------------------------------------------------

wire signed [31:0] linear_t0;
wire               linear_overflow;

wire signed [31:0] exp_t0;
wire               exp_overflow;

wire signed [31:0] log_t0;
wire               log_overflow;

leading_edge_method_linear u_method_linear (
    .t1       (s4_t1),
    .a1       (s4_a1),
    .dt21     (s4_dt21),
    .da21     (s4_da21),
    .t0       (linear_t0),
    .overflow (linear_overflow)
);

leading_edge_method_exp u_method_exp (
    .t1           (s4_t1),
    .dt32         (s4_dt32),
    .ln_a1        (s4_ln_a1),
    .ln_a2        (s4_ln_a2),
    .ln_a3        (s4_ln_a3),
    .ln_threshold (s4_ln_threshold),
    .t0           (exp_t0),
    .overflow     (exp_overflow)
);

leading_edge_method_log u_method_log (
    .t1       (s4_t1),
    .dt21     (s4_dt21),
    .dt32     (s4_dt32),
    .ln_a1    (s4_ln_a1),
    .ln_a2    (s4_ln_a2),
    .ln_a3    (s4_ln_a3),
    .t0       (log_t0),
    .overflow (log_overflow)
);

// -----------------------------------------------------------------------------
// S5: select method result
// -----------------------------------------------------------------------------

reg s5_valid;
reg signed [31:0] s5_t0;
reg signed [31:0] s5_amax;
reg s5_overflow;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s5_valid    <= 1'b0;
        s5_t0       <= 32'sh0;
        s5_amax     <= 32'sh0;
        s5_overflow <= 1'b0;
    end else begin
        s5_valid <= s4_valid;
        s5_amax  <= s4_a3;

        case (s4_mode)
            MODE_LINEAR: begin
                s5_t0       <= linear_t0;
                s5_overflow <= linear_overflow;
            end

            MODE_EXP: begin
                s5_t0       <= exp_t0;
                s5_overflow <= exp_overflow;
            end

            MODE_LOG: begin
                s5_t0       <= log_t0;
                s5_overflow <= log_overflow;
            end

            default: begin
                s5_t0       <= 32'sh0;
                s5_overflow <= 1'b1;
            end
        endcase
    end
end

// -----------------------------------------------------------------------------
// S6: output register
// -----------------------------------------------------------------------------

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        t0_est   <= 32'sh0;
        amax_est <= 32'sh0;
        valid    <= 1'b0;
        overflow <= 1'b0;
    end else begin
        valid    <= s5_valid;
        overflow <= s5_overflow;

        if (s5_valid) begin
            t0_est   <= s5_t0;
            amax_est <= s5_amax;
        end
    end
end

endmodule
