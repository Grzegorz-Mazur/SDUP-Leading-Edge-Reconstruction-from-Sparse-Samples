// Projekt: Leading Edge Reconstruction from Sparse PMT Samples
// Modul:   TB_leading_edge_core - testbench bezposrednio na leading_edge_core
// Opis:    Weryfikacja 15 przypadkow testowych (5 zdarzen x 3 metody)
//          Bez AXI - bezposrednie podanie sygnalow

`timescale 1ns / 1ps

module TB_leading_edge_core;
    localparam CLK_PERIOD = 10;

    reg clk = 0, rst_n = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    initial begin rst_n = 0; repeat(10) @(posedge clk); rst_n = 1; end

    // Porty modulu
    reg         start = 0;
    reg  [1:0]  mode_sel = 0;
    reg  signed [31:0] t1, a1, t2, a2, t3, a3, threshold;
    wire signed [31:0] t0_est, amax_est;
    wire        valid, overflow;

    leading_edge_core dut (
        .clk(clk), .rst_n(rst_n), .start(start), .mode_sel(mode_sel),
        .t1(t1), .a1(a1), .t2(t2), .a2(a2), .t3(t3), .a3(a3),
        .threshold(threshold),
        .t0_est(t0_est), .amax_est(amax_est),
        .valid(valid), .overflow(overflow)
    );

    // Q16.16 konwersje
    function [31:0] q16; input real v; q16 = $rtoi(v * 65536.0) & 32'hFFFF_FFFF; endfunction
    function real fq; input [31:0] v; reg signed [31:0] s; begin s = v; fq = $itor(s) / 65536.0; end endfunction

    // Dane testowe
    real tv_t1[5], tv_a1[5], tv_t2[5], tv_a2[5], tv_t3[5], tv_a3[5];
    real ref_lin[5], ref_exp[5], ref_log[5];

    integer pass_cnt, fail_cnt, ev, mode, n;
    real t0, ref_val, err;

    localparam DONE_CYCLES = 10;

    initial begin
        tv_t1[0]=13.441488; tv_a1[0]=1.248941; tv_t2[0]=15.903052; tv_a2[0]=3.651062; tv_t3[0]=18.009984; tv_a3[0]=5.065083;
        tv_t1[1]=15.622099; tv_a1[1]=1.032775; tv_t2[1]=17.450997; tv_a2[1]=1.957657; tv_t3[1]=20.473995; tv_a3[1]=2.620367;
        tv_t1[2]=13.400637; tv_a1[2]=0.958252; tv_t2[2]=15.813172; tv_a2[2]=2.797585; tv_t3[2]=18.161888; tv_a3[2]=4.307609;
        tv_t1[3]=13.262626; tv_a1[3]=0.581050; tv_t2[3]=15.566904; tv_a2[3]=1.844554; tv_t3[3]=17.892898; tv_a3[3]=2.811370;
        tv_t1[4]=15.480329; tv_a1[4]=0.772686; tv_t2[4]=18.522173; tv_a2[4]=3.071598; tv_t3[4]=20.205404; tv_a3[4]=4.120738;

        ref_lin[0]=12.1617; ref_lin[1]=13.5799; ref_lin[2]=12.1438; ref_lin[3]=12.2029; ref_lin[4]=14.4579;
        ref_exp[0]= 4.5033; ref_exp[1]= 2.4356; ref_exp[2]= 6.9792; ref_exp[3]= 9.5033; ref_exp[4]= 9.8965;
        ref_log[0]=18.2697; ref_log[1]=19.8705; ref_log[2]=18.6272; ref_log[3]=17.9939; ref_log[4]=20.7619;

        pass_cnt = 0; fail_cnt = 0;
        wait(rst_n); repeat(5) @(posedge clk);

        $display("=== Leading Edge Reconstruction - Core Direct Test ===");
        $display("%-3s %-4s %10s %10s %8s %s","Ev","Mode","FPGA[ns]","Ref[ns]","Err[ns]","Result");
        $display("-------------------------------------------------------------------");

        for (ev = 0; ev < 5; ev = ev + 1) begin
            for (mode = 0; mode < 3; mode = mode + 1) begin

                // Ustaw wejscia
                t1 = q16(tv_t1[ev]); a1 = q16(tv_a1[ev]);
                t2 = q16(tv_t2[ev]); a2 = q16(tv_a2[ev]);
                t3 = q16(tv_t3[ev]); a3 = q16(tv_a3[ev]);
                threshold = q16(0.3);
                mode_sel = mode[1:0];

                // Puls start
                @(posedge clk); #1;
                start = 1;
                @(posedge clk); #1;
                start = 0;

                // Czekaj na valid (maks DONE_CYCLES cykli)
                n = 0;
                while (!valid && n < 500) begin
                    @(posedge clk); n = n + 1;
                end

                if (!valid) begin
                    $display(" %0d  %-4s  TIMEOUT FAIL", ev,
                        (mode==0)?"LIN":(mode==1)?"EXP":"LOG");
                    fail_cnt = fail_cnt + 1;
                end else begin
                    t0      = fq(t0_est);
                    ref_val = (mode==0) ? ref_lin[ev] : (mode==1) ? ref_exp[ev] : ref_log[ev];
                    err     = t0 - ref_val;
                    if (err < 0.0) err = -err;

                    if ((mode==0 && err<0.10)||(mode==1 && err<0.55)||(mode==2 && err<0.15)) begin
                        $display(" %0d  %-4s %10.4f %10.4f %8.4f  PASS", ev,
                            (mode==0)?"LIN":(mode==1)?"EXP":"LOG", t0, ref_val, err);
                        pass_cnt = pass_cnt + 1;
                    end else begin
                        $display(" %0d  %-4s %10.4f %10.4f %8.4f  FAIL", ev,
                            (mode==0)?"LIN":(mode==1)?"EXP":"LOG", t0, ref_val, err);
                        fail_cnt = fail_cnt + 1;
                    end
                end

                repeat(5) @(posedge clk);
            end
        end

        $display("-------------------------------------------------------------------");
        $display("WYNIK: %0d PASS,  %0d FAIL  (na 15 testow)", pass_cnt, fail_cnt);
        $display("Tolerancje: LIN=0.10ns  EXP=0.55ns  LOG=0.15ns");
        $finish;
    end

    initial begin $dumpfile("tb_core.vcd"); $dumpvars(0, TB_leading_edge_core); end
endmodule