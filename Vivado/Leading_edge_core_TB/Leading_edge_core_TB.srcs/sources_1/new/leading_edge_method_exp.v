// -----------------------------------------------------------------------------
// Method 1: exponential leading-edge reconstruction
// -----------------------------------------------------------------------------
// Works in logarithmic amplitude domain.  Samples 2 and 3 estimate tau, then
// sample 1 is projected back to the configured threshold:
//
//   tau = (t3 - t2) / (ln(a3) - ln(a2))
//   t0  = t1 - tau * (ln(a1) - ln(threshold))
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module leading_edge_method_exp (
    input  wire signed [31:0] t1,
    input  wire signed [31:0] dt32,
    input  wire signed [31:0] ln_a1,
    input  wire signed [31:0] ln_a2,
    input  wire signed [31:0] ln_a3,
    input  wire signed [31:0] ln_threshold,
    output wire signed [31:0] t0,
    output wire               overflow
);

`include "leading_edge_math.vh"

wire signed [31:0] dln32;
wire signed [31:0] tau;

assign dln32   = ln_a3 - ln_a2;
assign tau     = (dln32 != 32'sh0) ? q16_div(dt32, dln32) : Q16_MAX;
assign t0      = t1 - q16_mul(tau, ln_a1 - ln_threshold);
assign overflow = (dln32 == 32'sh0);

endmodule
