`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Unit testbench for the split leading-edge implementation
// -----------------------------------------------------------------------------
// Test sections:
//   1. shared math helpers from leading_edge_math.vh
//   2. leading_edge_method_linear
//   3. leading_edge_method_exp
//   4. leading_edge_method_log
//   5. full leading_edge_core pipeline in all three modes
// -----------------------------------------------------------------------------

module tb_leading_edge_core_unit;

`include "leading_edge_math.vh"

localparam integer CLOCK_PERIOD_NS = 10;
localparam integer Q16_SCALE       = 65536;
localparam integer TIMEOUT_CYCLES  = 40;

localparam [1:0] MODE_LINEAR = 2'b00;
localparam [1:0] MODE_EXP    = 2'b01;
localparam [1:0] MODE_LOG    = 2'b10;

integer pass_count;
integer fail_count;

// -----------------------------------------------------------------------------
// Conversion and assertion helpers
// -----------------------------------------------------------------------------

function signed [31:0] tb_q16;
    input real value;
    real scaled;
    begin
        scaled = value * Q16_SCALE;
        if (scaled >= 0.0)
            tb_q16 = $rtoi(scaled + 0.5);
        else
            tb_q16 = $rtoi(scaled - 0.5);
    end
endfunction

function real tb_fq16;
    input signed [31:0] value;
    begin
        tb_fq16 = $itor(value) / Q16_SCALE;
    end
endfunction

function real tb_abs;
    input real value;
    begin
        tb_abs = (value < 0.0) ? -value : value;
    end
endfunction

task expect_real;
    input [8*80-1:0] name;
    input real actual;
    input real expected;
    input real tolerance;
    real error;
    begin
        error = actual - expected;
        if (tb_abs(error) <= tolerance) begin
            pass_count = pass_count + 1;
            $display("PASS: %0s actual=%0.6f expected=%0.6f", name, actual, expected);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: %0s actual=%0.6f expected=%0.6f error=%0.6f tol=%0.6f",
                     name, actual, expected, error, tolerance);
        end
    end
endtask

task expect_int;
    input [8*80-1:0] name;
    input integer actual;
    input integer expected;
    begin
        if (actual == expected) begin
            pass_count = pass_count + 1;
            $display("PASS: %0s actual=%0d expected=%0d", name, actual, expected);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: %0s actual=%0d expected=%0d", name, actual, expected);
        end
    end
endtask

// -----------------------------------------------------------------------------
// Direct method module instances
// -----------------------------------------------------------------------------

reg signed [31:0] m_t1;
reg signed [31:0] m_a1;
reg signed [31:0] m_dt21;
reg signed [31:0] m_dt32;
reg signed [31:0] m_da21;
reg signed [31:0] m_ln_a1;
reg signed [31:0] m_ln_a2;
reg signed [31:0] m_ln_a3;
reg signed [31:0] m_ln_threshold;

wire signed [31:0] linear_t0;
wire linear_overflow;
wire signed [31:0] exp_t0;
wire exp_overflow;
wire signed [31:0] log_t0;
wire log_overflow;

leading_edge_method_linear method_linear (
    .t1       (m_t1),
    .a1       (m_a1),
    .dt21     (m_dt21),
    .da21     (m_da21),
    .t0       (linear_t0),
    .overflow (linear_overflow)
);

leading_edge_method_exp method_exp (
    .t1           (m_t1),
    .dt32         (m_dt32),
    .ln_a1        (m_ln_a1),
    .ln_a2        (m_ln_a2),
    .ln_a3        (m_ln_a3),
    .ln_threshold (m_ln_threshold),
    .t0           (exp_t0),
    .overflow     (exp_overflow)
);

leading_edge_method_log method_log (
    .t1       (m_t1),
    .dt21     (m_dt21),
    .dt32     (m_dt32),
    .ln_a1    (m_ln_a1),
    .ln_a2    (m_ln_a2),
    .ln_a3    (m_ln_a3),
    .t0       (log_t0),
    .overflow (log_overflow)
);

// -----------------------------------------------------------------------------
// Full core instance
// -----------------------------------------------------------------------------

reg clk;
reg rst_n;
reg start;
reg [1:0] mode_sel;
reg signed [31:0] t1;
reg signed [31:0] a1;
reg signed [31:0] t2;
reg signed [31:0] a2;
reg signed [31:0] t3;
reg signed [31:0] a3;
reg signed [31:0] threshold;

wire signed [31:0] t0_est;
wire signed [31:0] amax_est;
wire valid;
wire overflow;

leading_edge_core dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .start     (start),
    .mode_sel  (mode_sel),
    .t1        (t1),
    .a1        (a1),
    .t2        (t2),
    .a2        (a2),
    .t3        (t3),
    .a3        (a3),
    .threshold (threshold),
    .t0_est    (t0_est),
    .amax_est  (amax_est),
    .valid     (valid),
    .overflow  (overflow)
);

initial begin
    clk = 1'b0;
    forever #(CLOCK_PERIOD_NS / 2) clk = ~clk;
end

// -----------------------------------------------------------------------------
// Section 1: shared math tests
// -----------------------------------------------------------------------------

task test_math_helpers;
    begin
        $display("--- math helpers ---");

        expect_real("q16_mul 2.5 * -1.25",
                    tb_fq16(q16_mul(tb_q16(2.5), tb_q16(-1.25))),
                    -3.125, 0.0001);

        expect_real("q16_div 7.5 / 2.5",
                    tb_fq16(q16_div(tb_q16(7.5), tb_q16(2.5))),
                    3.0, 0.0001);

        expect_int("q16_find_msb 0x00010000", q16_find_msb(32'h00010000), 16);
        expect_int("q16_find_msb 0x80000000", q16_find_msb(32'h80000000), 31);

        expect_real("q16_ln 1.0", tb_fq16(q16_ln(tb_q16(1.0))), 0.0, 0.020);
        expect_real("q16_ln 2.0", tb_fq16(q16_ln(tb_q16(2.0))), 0.693, 0.020);
        expect_real("q16_ln 4.0", tb_fq16(q16_ln(tb_q16(4.0))), 1.386, 0.030);
    end
endtask

// -----------------------------------------------------------------------------
// Section 2: linear method tests
// -----------------------------------------------------------------------------

task test_linear_method;
    begin
        $display("--- method 0 linear ---");

        m_t1   = tb_q16(10.0);
        m_a1   = tb_q16(1.0);
        m_dt21 = tb_q16(2.0);
        m_da21 = tb_q16(2.0);
        #1;

        expect_real("linear method t0", tb_fq16(linear_t0), 9.0, 0.001);
        expect_int("linear method overflow", linear_overflow, 0);

        m_da21 = tb_q16(0.0);
        #1;
        expect_int("linear divide-by-zero overflow", linear_overflow, 1);
    end
endtask

// -----------------------------------------------------------------------------
// Section 3: exponential method tests
// -----------------------------------------------------------------------------

task test_exp_method;
    begin
        $display("--- method 1 exponential ---");

        m_t1           = tb_q16(10.0);
        m_dt32         = tb_q16(2.0);
        m_ln_a1        = tb_q16(0.5);
        m_ln_a2        = tb_q16(1.0);
        m_ln_a3        = tb_q16(1.5);
        m_ln_threshold = tb_q16(0.0);
        #1;

        expect_real("exponential method t0", tb_fq16(exp_t0), 8.0, 0.001);
        expect_int("exponential method overflow", exp_overflow, 0);

        m_ln_a3 = m_ln_a2;
        #1;
        expect_int("exponential zero dln overflow", exp_overflow, 1);
    end
endtask

// -----------------------------------------------------------------------------
// Section 4: logarithmic / Gaussian-domain method tests
// -----------------------------------------------------------------------------

task test_log_method;
    begin
        $display("--- method 2 logarithmic ---");

        m_t1    = tb_q16(10.0);
        m_dt21  = tb_q16(2.0);
        m_dt32  = tb_q16(2.0);
        m_ln_a1 = tb_q16(3.5);
        m_ln_a2 = tb_q16(4.0);
        m_ln_a3 = tb_q16(3.5);
        #1;

        expect_real("log method t0", tb_fq16(log_t0), 12.0, 0.002);
        expect_int("log method overflow", log_overflow, 0);

        m_ln_a3 = tb_q16(4.5);
        #1;
        expect_int("log non-peak overflow", log_overflow, 1);
    end
endtask

// -----------------------------------------------------------------------------
// Section 5: full core tests
// -----------------------------------------------------------------------------

task reset_core;
    begin
        start     = 1'b0;
        mode_sel  = MODE_LINEAR;
        t1        = 32'sh0;
        a1        = 32'sh0;
        t2        = 32'sh0;
        a2        = 32'sh0;
        t3        = 32'sh0;
        a3        = 32'sh0;
        threshold = 32'sh0;

        rst_n = 1'b0;
        repeat (6) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
    end
endtask

task wait_for_core_valid;
    output integer timed_out;
    integer cycles;
    begin
        timed_out = 0;
        cycles = 0;
        @(posedge clk);
        #1;
        while (!valid && cycles < TIMEOUT_CYCLES) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end
        if (!valid)
            timed_out = 1;
    end
endtask

task run_core_case;
    input [8*80-1:0] name;
    input [1:0] mode;
    input real rt1;
    input real ra1;
    input real rt2;
    input real ra2;
    input real rt3;
    input real ra3;
    input real rthreshold;
    input real expected_t0;
    input real tolerance;
    integer timed_out;
    begin
        @(negedge clk);
        mode_sel  = mode;
        t1        = tb_q16(rt1);
        a1        = tb_q16(ra1);
        t2        = tb_q16(rt2);
        a2        = tb_q16(ra2);
        t3        = tb_q16(rt3);
        a3        = tb_q16(ra3);
        threshold = tb_q16(rthreshold);
        start     = 1'b1;

        @(negedge clk);
        start = 1'b0;

        wait_for_core_valid(timed_out);
        if (timed_out) begin
            fail_count = fail_count + 1;
            $display("FAIL: %0s timed out", name);
        end else if (overflow) begin
            fail_count = fail_count + 1;
            $display("FAIL: %0s overflow asserted", name);
        end else begin
            expect_real(name, tb_fq16(t0_est), expected_t0, tolerance);
        end
    end
endtask

task test_full_core;
    begin
        $display("--- full core pipeline ---");
        reset_core();

        run_core_case("core mode 0 linear",
                      MODE_LINEAR,
                      10.0, 1.0,
                      12.0, 3.0,
                      14.0, 5.0,
                      0.5,
                      9.0,
                      0.020);

        run_core_case("core mode 1 exponential",
                      MODE_EXP,
                      10.0, 1.648721,
                      12.0, 2.718282,
                      14.0, 4.481689,
                      1.0,
                      8.0,
                      0.250);

        run_core_case("core mode 2 logarithmic",
                      MODE_LOG,
                      10.0, 33.115452,
                      12.0, 54.598150,
                      14.0, 33.115452,
                      1.0,
                      12.0,
                      0.250);
    end
endtask

// -----------------------------------------------------------------------------
// Main scenario
// -----------------------------------------------------------------------------

initial begin
    pass_count = 0;
    fail_count = 0;
    rst_n = 1'b0;

    test_math_helpers();
    test_linear_method();
    test_exp_method();
    test_log_method();
    test_full_core();

    repeat (5) @(posedge clk);

    if (fail_count == 0)
        $display("tb_leading_edge_core_unit complete: %0d PASS, 0 FAIL", pass_count);
    else
        $display("tb_leading_edge_core_unit complete: %0d PASS, %0d FAIL", pass_count, fail_count);

    $finish;
end

endmodule
