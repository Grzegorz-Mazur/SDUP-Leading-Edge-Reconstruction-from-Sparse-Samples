// -----------------------------------------------------------------------------
// Method 0: linear leading-edge reconstruction
// -----------------------------------------------------------------------------
// Uses the first two samples and assumes a straight line between them:
//
//   slope_dt_per_amp = (t2 - t1) / (a2 - a1)
//   t0               = t1 - a1 * slope_dt_per_amp
//
// Inputs are already prepared by the core pipeline:
//   dt21 = t2 - t1
//   da21 = a2 - a1
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module leading_edge_method_linear (
    input  wire signed [31:0] t1,
    input  wire signed [31:0] a1,
    input  wire signed [31:0] dt21,
    input  wire signed [31:0] da21,
    output wire signed [31:0] t0,
    output wire               overflow
);

`include "leading_edge_math.vh"

wire signed [31:0] slope_dt_per_amp;

assign slope_dt_per_amp = (da21 != 32'sh0) ? q16_div(dt21, da21) : Q16_MAX;
assign t0               = t1 - q16_mul(a1, slope_dt_per_amp);
assign overflow         = (da21 == 32'sh0);

endmodule
