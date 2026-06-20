`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// AXI4-Lite smoke test for leading_edge_ip_lite
// -----------------------------------------------------------------------------
// This testbench verifies the current no-AXI-Stream milestone:
//   1. write samples and threshold through AXI-Lite registers
//   2. write CONTROL with mode and start pulse
//   3. poll STATUS.done
//   4. read T0_EST / AMAX_EST
// -----------------------------------------------------------------------------

module tb_leading_edge_ip_lite;

localparam integer CLOCK_PERIOD_NS = 10;
localparam integer Q16_SCALE       = 65536;

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

localparam [1:0] MODE_LINEAR = 2'b00;
localparam [1:0] MODE_EXP    = 2'b01;
localparam [1:0] MODE_LOG    = 2'b10;

reg clk;
reg rst_n;

reg [5:0] awaddr;
reg awvalid;
wire awready;

reg [31:0] wdata;
reg [3:0] wstrb;
reg wvalid;
wire wready;

wire [1:0] bresp;
wire bvalid;
reg bready;

reg [5:0] araddr;
reg arvalid;
wire arready;

wire [31:0] rdata;
wire [1:0] rresp;
wire rvalid;
reg rready;

wire irq;

integer pass_count;
integer fail_count;

leading_edge_ip_lite dut (
    .s_axi_aclk    (clk),
    .s_axi_aresetn (rst_n),
    .s_axi_awaddr  (awaddr),
    .s_axi_awvalid (awvalid),
    .s_axi_awready (awready),
    .s_axi_wdata   (wdata),
    .s_axi_wstrb   (wstrb),
    .s_axi_wvalid  (wvalid),
    .s_axi_wready  (wready),
    .s_axi_bresp   (bresp),
    .s_axi_bvalid  (bvalid),
    .s_axi_bready  (bready),
    .s_axi_araddr  (araddr),
    .s_axi_arvalid (arvalid),
    .s_axi_arready (arready),
    .s_axi_rdata   (rdata),
    .s_axi_rresp   (rresp),
    .s_axi_rvalid  (rvalid),
    .s_axi_rready  (rready),
    .irq           (irq)
);

initial begin
    clk = 1'b0;
    forever #(CLOCK_PERIOD_NS / 2) clk = ~clk;
end

function signed [31:0] q16;
    input real value;
    real scaled;
    begin
        scaled = value * Q16_SCALE;
        if (scaled >= 0.0)
            q16 = $rtoi(scaled + 0.5);
        else
            q16 = $rtoi(scaled - 0.5);
    end
endfunction

function real fq16;
    input signed [31:0] value;
    begin
        fq16 = $itor(value) / Q16_SCALE;
    end
endfunction

function real abs_real;
    input real value;
    begin
        abs_real = (value < 0.0) ? -value : value;
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
        if (abs_real(error) <= tolerance) begin
            pass_count = pass_count + 1;
            $display("PASS: %0s actual=%0.6f expected=%0.6f", name, actual, expected);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: %0s actual=%0.6f expected=%0.6f error=%0.6f",
                     name, actual, expected, error);
        end
    end
endtask

task expect_word;
    input [8*80-1:0] name;
    input [31:0] actual;
    input [31:0] expected;
    begin
        if (actual == expected) begin
            pass_count = pass_count + 1;
            $display("PASS: %0s actual=0x%08h", name, actual);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: %0s actual=0x%08h expected=0x%08h", name, actual, expected);
        end
    end
endtask

task axi_write;
    input [5:0] addr;
    input [31:0] data;
    begin
        @(negedge clk);
        awaddr  = addr;
        wdata   = data;
        wstrb   = 4'hF;
        awvalid = 1'b1;
        wvalid  = 1'b1;
        bready  = 1'b1;

        @(posedge clk);
        while (!(awready && wready)) @(posedge clk);

        @(negedge clk);
        awvalid = 1'b0;
        wvalid  = 1'b0;

        @(posedge clk);
        while (!bvalid) @(posedge clk);

        if (bresp != 2'b00) begin
            fail_count = fail_count + 1;
            $display("FAIL: AXI write response addr=0x%02h bresp=%0d", addr, bresp);
        end

        @(negedge clk);
        bready = 1'b0;
    end
endtask

task axi_read;
    input [5:0] addr;
    output [31:0] data;
    begin
        @(negedge clk);
        araddr  = addr;
        arvalid = 1'b1;
        rready  = 1'b1;

        @(posedge clk);
        while (!arready) @(posedge clk);

        @(negedge clk);
        arvalid = 1'b0;

        @(posedge clk);
        while (!rvalid) @(posedge clk);
        data = rdata;

        if (rresp != 2'b00) begin
            fail_count = fail_count + 1;
            $display("FAIL: AXI read response addr=0x%02h rresp=%0d", addr, rresp);
        end

        @(negedge clk);
        rready = 1'b0;
    end
endtask

task wait_done;
    output [31:0] status;
    integer i;
    begin
        status = 32'h0;
        for (i = 0; i < 50; i = i + 1) begin
            axi_read(ADDR_STATUS, status);
            if (status[1])
                i = 50;
        end

        if (!status[1]) begin
            fail_count = fail_count + 1;
            $display("FAIL: timeout waiting for STATUS.done");
        end
    end
endtask

task run_linear_case;
    reg [31:0] status;
    reg [31:0] t0_word;
    reg [31:0] amax_word;
    begin
        axi_write(ADDR_THRESHOLD, q16(0.5));
        axi_write(ADDR_T1,        q16(10.0));
        axi_write(ADDR_A1,        q16(1.0));
        axi_write(ADDR_T2,        q16(12.0));
        axi_write(ADDR_A2,        q16(3.0));
        axi_write(ADDR_T3,        q16(14.0));
        axi_write(ADDR_A3,        q16(5.0));

        // CONTROL[2:1] = mode, CONTROL[0] = start pulse
        axi_write(ADDR_CONTROL, {29'h0, MODE_LINEAR, 1'b1});
        wait_done(status);

        if (status[2]) begin
            fail_count = fail_count + 1;
            $display("FAIL: unexpected overflow in AXI-Lite linear case");
        end

        axi_read(ADDR_T0_EST, t0_word);
        axi_read(ADDR_AMAX_EST, amax_word);

        expect_real("AXI-Lite linear t0", fq16(t0_word), 9.0, 0.020);
        expect_real("AXI-Lite linear amax", fq16(amax_word), 5.0, 0.001);
    end
endtask

initial begin
    pass_count = 0;
    fail_count = 0;

    rst_n   = 1'b0;
    awaddr  = 6'h0;
    awvalid = 1'b0;
    wdata   = 32'h0;
    wstrb   = 4'h0;
    wvalid  = 1'b0;
    bready  = 1'b0;
    araddr  = 6'h0;
    arvalid = 1'b0;
    rready  = 1'b0;

    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);

    begin : version_check
        reg [31:0] version;
        axi_read(ADDR_VERSION, version);
        expect_word("AXI-Lite VERSION", version, 32'h00010000);
    end

    run_linear_case();

    repeat (5) @(posedge clk);

    if (fail_count == 0)
        $display("tb_leading_edge_ip_lite complete: %0d PASS, 0 FAIL", pass_count);
    else
        $display("tb_leading_edge_ip_lite complete: %0d PASS, %0d FAIL", pass_count, fail_count);

    $finish;
end

endmodule
