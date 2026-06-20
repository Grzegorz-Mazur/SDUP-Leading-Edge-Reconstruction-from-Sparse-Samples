`timescale 1ns / 1ps

// AXI-Lite testbench for myip_leading_edge_axi_lite
// Tests: register write/readback, START pulse, core computation (LIN/EXP/LOG)

module TB_axi_leading_edge;

    localparam CLK_PERIOD = 10;

    reg         aclk;
    reg         aresetn;
    reg  [5:0]  awaddr;
    reg  [2:0]  awprot;
    reg         awvalid;
    wire        awready;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;
    reg         wvalid;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready;
    reg  [5:0]  araddr;
    reg  [2:0]  arprot;
    reg         arvalid;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready;

    integer pass_count;
    integer fail_count;

    myip_leading_edge_axi_lite_v1_1 #(
        .C_S00_AXI_DATA_WIDTH(32),
        .C_S00_AXI_ADDR_WIDTH(6)
    ) dut (
        .s00_axi_aclk    (aclk),
        .s00_axi_aresetn (aresetn),
        .s00_axi_awaddr  (awaddr),
        .s00_axi_awprot  (awprot),
        .s00_axi_awvalid (awvalid),
        .s00_axi_awready (awready),
        .s00_axi_wdata   (wdata),
        .s00_axi_wstrb   (wstrb),
        .s00_axi_wvalid  (wvalid),
        .s00_axi_wready  (wready),
        .s00_axi_bresp   (bresp),
        .s00_axi_bvalid  (bvalid),
        .s00_axi_bready  (bready),
        .s00_axi_araddr  (araddr),
        .s00_axi_arprot  (arprot),
        .s00_axi_arvalid (arvalid),
        .s00_axi_arready (arready),
        .s00_axi_rdata   (rdata),
        .s00_axi_rresp   (rresp),
        .s00_axi_rvalid  (rvalid),
        .s00_axi_rready  (rready)
    );

    initial aclk = 1'b0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    task automatic axi_write(input [5:0] addr, input [31:0] data);
        begin
            @(posedge aclk);
            awaddr  <= addr;
            awprot  <= 3'b000;
            awvalid <= 1'b1;
            wdata   <= data;
            wstrb   <= 4'hF;
            wvalid  <= 1'b1;
            bready  <= 1'b1;
            @(posedge aclk);
            while (!(awready && wready)) @(posedge aclk);
            awvalid <= 1'b0;
            wvalid  <= 1'b0;
            while (!bvalid) @(posedge aclk);
            @(posedge aclk);
        end
    endtask

    task automatic axi_read(input [5:0] addr, output [31:0] data);
        begin
            @(posedge aclk);
            araddr  <= addr;
            arprot  <= 3'b000;
            arvalid <= 1'b1;
            rready  <= 1'b1;
            @(posedge aclk);
            while (!arready) @(posedge aclk);
            arvalid <= 1'b0;
            while (!rvalid) @(posedge aclk);
            data = rdata;
            @(posedge aclk);
        end
    endtask

    function automatic real fq16(input [31:0] v);
        integer signed s;
        begin
            s = v;
            fq16 = s / 65536.0;
        end
    endfunction

    function automatic integer to_q16(input real v);
        begin
            if (v >= 0.0)
                to_q16 = $rtoi(v * 65536.0 + 0.5);
            else
                to_q16 = $rtoi(v * 65536.0 - 0.5);
        end
    endfunction

    task automatic check_readback(
        input [255:0] name,
        input [5:0]     addr,
        input [31:0]    expected
    );
        reg [31:0] got;
        begin
            axi_read(addr, got);
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("PASS: %s  addr=0x%02X  got=0x%08X", name, addr, got);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %s  addr=0x%02X  expected=0x%08X  got=0x%08X", name, addr, expected, got);
            end
        end
    endtask

    task automatic wait_done(input integer max_cycles);
        integer i;
        reg [31:0] status;
        begin
            for (i = 0; i < max_cycles; i = i + 1) begin
                axi_read(6'h04, status);
                if (status[0]) begin
                    $display("INFO: STATUS done after %0d cycles, status=0x%08X", i + 1, status);
                    i = max_cycles;
                end else
                    @(posedge aclk);
            end
            if (!status[0]) begin
                fail_count = fail_count + 1;
                $display("FAIL: timeout waiting for STATUS.done");
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        awaddr = 0; awvalid = 0; wdata = 0; wstrb = 0; wvalid = 0;
        araddr = 0; arvalid = 0; bready = 1; rready = 1;
        aresetn = 1'b0;
        repeat (8) @(posedge aclk);
        aresetn = 1'b1;
        repeat (4) @(posedge aclk);

        $display("=== TB AXI-Lite: Leading Edge Reconstruction ===");

        // Test 1: write/readback scratch on T1
        axi_write(6'h08, 32'hDEADBEEF);
        check_readback("T1 write/readback", 6'h08, 32'hDEADBEEF);

        // Test 2: STATUS is read-only (write ignored)
        axi_write(6'h04, 32'hFFFFFFFF);
        check_readback("STATUS read-only", 6'h04, 32'h00000000);

        // Test 3: full LIN computation (event 0 from README)
        axi_write(6'h20, to_q16(0.3));       // THRESH
        axi_write(6'h08, to_q16(13.44));     // T1
        axi_write(6'h0C, to_q16(1.25));      // A1
        axi_write(6'h10, to_q16(15.90));     // T2
        axi_write(6'h14, to_q16(3.65));      // A2
        axi_write(6'h18, to_q16(18.01));     // T3
        axi_write(6'h1C, to_q16(5.07));      // A3
        axi_write(6'h00, 32'h00000001);      // CTRL: mode=LIN, start=1

        wait_done(64);

        begin : lin_check
            reg [31:0] t0_q16;
            real       t0_ns;
            real       err;
            axi_read(6'h24, t0_q16);
            t0_ns = fq16(t0_q16);
            err = t0_ns - 12.1617;
            if (err < 0) err = -err;
            if (err < 0.10) begin
                pass_count = pass_count + 1;
                $display("PASS: LIN t0_est = %.4f ns (ref 12.1617, err %.4f)", t0_ns, err);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: LIN t0_est = %.4f ns (ref 12.1617, err %.4f)", t0_ns, err);
            end
        end

        // Test 4: EXP mode
        axi_write(6'h00, 32'h00000000);
        repeat (4) @(posedge aclk);
        axi_write(6'h00, 32'h00000003);      // mode=EXP(01), start=1
        wait_done(64);
        begin : exp_check
            reg [31:0] t0_q16;
            real       t0_ns;
            real       err;
            axi_read(6'h24, t0_q16);
            t0_ns = fq16(t0_q16);
            err = t0_ns - 4.5033;
            if (err < 0) err = -err;
            if (err < 0.55) begin
                pass_count = pass_count + 1;
                $display("PASS: EXP t0_est = %.4f ns (ref 4.5033, err %.4f)", t0_ns, err);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: EXP t0_est = %.4f ns (ref 4.5033, err %.4f)", t0_ns, err);
            end
        end

        // Test 5: LOG mode
        axi_write(6'h00, 32'h00000000);
        repeat (4) @(posedge aclk);
        axi_write(6'h00, 32'h00000005);      // mode=LOG(10), start=1
        wait_done(64);
        begin : log_check
            reg [31:0] t0_q16;
            real       t0_ns;
            real       err;
            axi_read(6'h24, t0_q16);
            t0_ns = fq16(t0_q16);
            err = t0_ns - 18.2697;
            if (err < 0) err = -err;
            if (err < 0.15) begin
                pass_count = pass_count + 1;
                $display("PASS: LOG t0_est = %.4f ns (ref 18.2697, err %.4f)", t0_ns, err);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: LOG t0_est = %.4f ns (ref 18.2697, err %.4f)", t0_ns, err);
            end
        end

        $display("-------------------------------------------------------------------");
        $display("WYNIK: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("=== ALL TESTS PASSED ===");
        else
            $display("=== SOME TESTS FAILED ===");

        #100;
        $finish;
    end

endmodule
