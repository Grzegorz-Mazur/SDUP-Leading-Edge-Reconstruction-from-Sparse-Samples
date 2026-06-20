// -----------------------------------------------------------------------------
// Method 2: logarithmic / Gaussian-domain reconstruction
// -----------------------------------------------------------------------------
// Fits a parabola to ln(A) using three samples:
//
//   ln(A(t)) = c2*t^2 + c1*t + c0
//
// The pulse maximum is at:
//
//   t0 = -c1 / (2*c2)
//
// A valid Gaussian-like peak requires c2 < 0.  If c2 cannot be computed or is
// non-negative, the module reports overflow and returns t1 as a safe fallback.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module leading_edge_method_log (
    input  wire signed [31:0] t1,
    input  wire signed [31:0] dt21,
    input  wire signed [31:0] dt32,
    input  wire signed [31:0] ln_a1,
    input  wire signed [31:0] ln_a2,
    input  wire signed [31:0] ln_a3,
    output wire signed [31:0] t0,
    output wire               overflow
);

`include "leading_edge_math.vh"

wire signed [31:0] dt31;
wire signed [31:0] dln21;
wire signed [31:0] dln31;
wire signed [31:0] c2_num;
wire signed [31:0] c2_den;
wire signed [31:0] c2;
wire signed [31:0] c1;
wire               c2_valid;

assign dt31   = dt21 + dt32;
assign dln21  = ln_a2 - ln_a1;
assign dln31  = ln_a3 - ln_a1;

assign c2_num = q16_mul(dln31, dt21) - q16_mul(dln21, dt31);
assign c2_den = q16_mul(q16_mul(dt31, dt21), dt31 - dt21);
assign c2     = (c2_den != 32'sh0) ? q16_div(c2_num, c2_den) : Q16_MAX;
assign c1     = q16_div(dln21, dt21) - q16_mul(c2, t1 + t1 + dt21);

assign c2_valid = (c2_den != 32'sh0) && (c2 != 32'sh0) && ($signed(c2) < 32'sh0);
assign t0       = c2_valid ? q16_div(-c1, c2 + c2) : t1;
assign overflow = !c2_valid;

endmodule
