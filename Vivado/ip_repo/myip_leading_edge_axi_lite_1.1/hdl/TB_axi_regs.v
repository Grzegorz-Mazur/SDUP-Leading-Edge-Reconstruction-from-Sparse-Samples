// Projekt: Leading Edge Reconstruction from Sparse PMT Samples
// Modul:   TB_axi_regs - weryfikacja dostepu AXI do rejestrow
// Opis:    Sprawdza czy kazdy rejestr zapisuje i odczytuje poprawna wartosc
//          Mapa: reg0=CTRL  reg1=STATUS(RO)  reg2=T1  reg3=A1
//                reg4=T2    reg5=A2           reg6=T3  reg7=A3
//                reg8=THRESH  reg9=T0_EST(RO)  reg10=AMAX_EST(RO)  reg11=EVENT_ID(RO)

`timescale 1ns / 1ps

module TB_axi_regs;
    localparam CLK_PERIOD = 10;

    reg clk = 0, rstn = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    initial begin rstn = 0; repeat(10) @(posedge clk); rstn = 1; end

    reg  [5:0]  awaddr=0; reg  awvalid=0; wire awready;
    reg  [31:0] wdata=0;  reg  [3:0] wstrb=0; reg wvalid=0; wire wready;
    wire [1:0]  bresp;    wire bvalid;   reg  bready=0;
    reg  [5:0]  araddr=0; reg  arvalid=0; wire arready;
    wire [31:0] rdata;    wire [1:0] rresp; wire rvalid; reg rready=0;

    myip_leading_edge_axi_lite_v1_1_S00_AXI #(
        .C_S_AXI_DATA_WIDTH(32), .C_S_AXI_ADDR_WIDTH(6)
    ) dut (
        .S_AXI_ACLK(clk),    .S_AXI_ARESETN(rstn),
        .S_AXI_AWADDR(awaddr),.S_AXI_AWPROT(3'b0),.S_AXI_AWVALID(awvalid),.S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata),  .S_AXI_WSTRB(wstrb),.S_AXI_WVALID(wvalid),  .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp),  .S_AXI_BVALID(bvalid),.S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr),.S_AXI_ARPROT(3'b0),.S_AXI_ARVALID(arvalid),.S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata),  .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready)
    );

    // ----------------------------------------------------------------
    // AXI tasks
    // ----------------------------------------------------------------
    task axi_write; input [5:0] addr; input [31:0] data;
        begin
            @(posedge clk); #1;
            awaddr=addr; awvalid=1; wdata=data; wstrb=4'hF; wvalid=1; bready=1;
            @(posedge clk); while(!(awready&&wready)) @(posedge clk); #1;
            awvalid=0; wvalid=0;
            while(!bvalid) @(posedge clk); @(posedge clk); #1; bready=0;
        end
    endtask

    task axi_read; input [5:0] addr; output [31:0] data;
        begin
            @(posedge clk); #1; araddr=addr; arvalid=1; rready=1;
            @(posedge clk); while(!arready) @(posedge clk); #1; arvalid=0;
            while(!rvalid) @(posedge clk); data=rdata;
            @(posedge clk); #1; rready=0;
        end
    endtask

    // ----------------------------------------------------------------
    // Pomocnicze
    // ----------------------------------------------------------------
    integer pass_cnt, fail_cnt;
    reg [31:0] rd;

    task check_reg;
        input [63:0] name_unused; // tylko dla czytelnosci w display
        input [5:0]  addr;
        input [31:0] expected;
        input [31:0] mask;        // maska bitow ktore sprawdzamy
        begin
            axi_read(addr, rd);
            if ((rd & mask) === (expected & mask)) begin
                $display("  PASS  addr=0x%02X  odczyt=0x%08X  oczekiwano=0x%08X", addr, rd, expected);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  addr=0x%02X  odczyt=0x%08X  oczekiwano=0x%08X  maska=0x%08X",
                          addr, rd, expected, mask);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Test
    // ----------------------------------------------------------------
    initial begin
        pass_cnt = 0; fail_cnt = 0;
        wait(rstn); repeat(5) @(posedge clk);

        $display("=== TB_axi_regs: weryfikacja rejestrow AXI-Lite ===");
        $display("");

        // ---- 1. Reset - wszystkie rejestry = 0 ----
        $display("--- [1] Sprawdzenie wartosci po resecie ---");
        check_reg("CTRL    ", 6'h00, 32'h0, 32'hFFFFFFFF);
        check_reg("STATUS  ", 6'h04, 32'h0, 32'hFFFFFFFF);
        check_reg("T1      ", 6'h08, 32'h0, 32'hFFFFFFFF);
        check_reg("A1      ", 6'h0C, 32'h0, 32'hFFFFFFFF);
        check_reg("T2      ", 6'h10, 32'h0, 32'hFFFFFFFF);
        check_reg("A2      ", 6'h14, 32'h0, 32'hFFFFFFFF);
        check_reg("T3      ", 6'h18, 32'h0, 32'hFFFFFFFF);
        check_reg("A3      ", 6'h1C, 32'h0, 32'hFFFFFFFF);
        check_reg("THRESH  ", 6'h20, 32'h0, 32'hFFFFFFFF);
        check_reg("T0_EST  ", 6'h24, 32'h0, 32'hFFFFFFFF);
        check_reg("AMAX_EST", 6'h28, 32'h0, 32'hFFFFFFFF);
        check_reg("EVENT_ID", 6'h2C, 32'h0, 32'hFFFFFFFF);

        // ---- 2. Zapis rejestrow wejsciowych i odczyt ----
        $display("");
        $display("--- [2] Zapis i odczyt rejestrow wejsciowych ---");

        axi_write(6'h08, 32'hDEADBEEF); check_reg("T1      ", 6'h08, 32'hDEADBEEF, 32'hFFFFFFFF);
        axi_write(6'h0C, 32'h00010000); check_reg("A1      ", 6'h0C, 32'h00010000, 32'hFFFFFFFF);
        axi_write(6'h10, 32'h000F8000); check_reg("T2      ", 6'h10, 32'h000F8000, 32'hFFFFFFFF);
        axi_write(6'h14, 32'h00038000); check_reg("A2      ", 6'h14, 32'h00038000, 32'hFFFFFFFF);
        axi_write(6'h18, 32'h00120000); check_reg("T3      ", 6'h18, 32'h00120000, 32'hFFFFFFFF);
        axi_write(6'h1C, 32'h00050000); check_reg("A3      ", 6'h1C, 32'h00050000, 32'hFFFFFFFF);
        axi_write(6'h20, 32'h00004CCC); check_reg("THRESH  ", 6'h20, 32'h00004CCC, 32'hFFFFFFFF);

        // ---- 3. CTRL: zapis mode_sel, bit start auto-kasowany ----
        $display("");
        $display("--- [3] CTRL: mode_sel i auto-kasowanie bitu start ---");

        // mode=01 (EXP), start=1 -> bit[0] powinien byc skasowany po pulseie
        axi_write(6'h00, 32'h3); // mode=01, start=1
        repeat(20) @(posedge clk);
        axi_read(6'h00, rd);
        if (rd[0] === 1'b0) begin
            $display("  PASS  CTRL[0] auto-skasowany po start_pulse");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  CTRL[0] nie zostal skasowany po start_pulse (=0x%08X)", rd);
            fail_cnt = fail_cnt + 1;
        end
        // mode_sel powinien pozostac
        if (rd[2:1] === 2'b01) begin
            $display("  PASS  CTRL[2:1]=01 (EXP) zachowany");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  CTRL[2:1]=%b zamiast 01", rd[2:1]);
            fail_cnt = fail_cnt + 1;
        end

        // ---- 4. STATUS: done/valid po wykonaniu ----
        $display("");
        $display("--- [4] STATUS: done i valid po wykonaniu ---");
        repeat(200) @(posedge clk);
        axi_read(6'h04, rd);
        if (rd[0] === 1'b1) begin
            $display("  PASS  STATUS[0]=done=1");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  STATUS[0]=done=0 (timeout?)");
            fail_cnt = fail_cnt + 1;
        end
        if (rd[1] === 1'b1) begin
            $display("  PASS  STATUS[1]=valid=1");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  STATUS[1]=valid=0");
            fail_cnt = fail_cnt + 1;
        end

        // ---- 5. T0_EST i AMAX_EST niezerowe po obliczeniu ----
        $display("");
        $display("--- [5] T0_EST i AMAX_EST niezerowe po obliczeniu ---");
        axi_read(6'h24, rd);
        if (rd !== 32'h0) begin
            $display("  PASS  T0_EST=0x%08X (niezerowy)", rd);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  T0_EST=0 (oczekiwano wyniku)");
            fail_cnt = fail_cnt + 1;
        end
        axi_read(6'h28, rd);
        if (rd !== 32'h0) begin
            $display("  PASS  AMAX_EST=0x%08X (niezerowy)", rd);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  AMAX_EST=0 (oczekiwano wyniku)");
            fail_cnt = fail_cnt + 1;
        end

        // ---- 6. STATUS kasowany przy nowym starcie ----
        $display("");
        $display("--- [6] STATUS kasowany przy nowym start_pulse ---");
        axi_write(6'h00, 32'h1); // start=1
        repeat(3) @(posedge clk);
        axi_read(6'h04, rd);
        if (rd[0] === 1'b0) begin
            $display("  PASS  STATUS skasowany po nowym start_pulse");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  STATUS[0] nie skasowany (=0x%08X)", rd);
            fail_cnt = fail_cnt + 1;
        end

        // ---- Podsumowanie ----
        $display("");
        $display("===================================================");
        $display("WYNIK: %0d PASS,  %0d FAIL", pass_cnt, fail_cnt);
        $display("===================================================");
        $finish;
    end

    initial begin $dumpfile("tb_axi_regs.vcd"); $dumpvars(0, TB_axi_regs); end
endmodule