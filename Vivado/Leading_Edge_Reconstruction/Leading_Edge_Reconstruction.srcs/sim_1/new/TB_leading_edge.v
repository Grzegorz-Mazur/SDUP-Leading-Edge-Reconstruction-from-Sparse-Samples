// Projekt: Leading Edge Reconstruction from Sparse PMT Samples
// Modul:   TB_leading_edge - testbench behawioralny
// Opis:    Weryfikacja 15 przypadkow testowych (5 zdarzen x 3 metody)
//          Referencje z modelu Python, format Q16.16

`timescale 1ns / 1ps

module TB_leading_edge;
    localparam CLK_PERIOD = 10;
    reg clk=0, rstn=0;
    always #(CLK_PERIOD/2) clk=~clk;
    initial begin rstn=0; repeat(10) @(posedge clk); rstn=1; end

    reg [5:0] awaddr=0; reg awvalid=0; wire awready;
    reg [31:0] wdata=0; reg [3:0] wstrb=0; reg wvalid=0; wire wready;
    wire [1:0] bresp; wire bvalid; reg bready=0;
    reg [5:0] araddr=0; reg arvalid=0; wire arready;
    wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready=0;

    leading_edge_axi_lite #(.DONE_CYCLES(10)) dut (
        .S_AXI_ACLK(clk),.S_AXI_ARESETN(rstn),
        .S_AXI_AWADDR(awaddr),.S_AXI_AWPROT(3'b0),.S_AXI_AWVALID(awvalid),.S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata),.S_AXI_WSTRB(wstrb),.S_AXI_WVALID(wvalid),.S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp),.S_AXI_BVALID(bvalid),.S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr),.S_AXI_ARPROT(3'b0),.S_AXI_ARVALID(arvalid),.S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata),.S_AXI_RRESP(rresp),.S_AXI_RVALID(rvalid),.S_AXI_RREADY(rready)
    );

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

    task wait_done; output reg ok; integer n; reg [31:0] s;
        begin ok=0; for(n=0;n<500;n=n+1) begin axi_read(6'h04,s); if(s[0]) begin ok=1; n=500; end end end
    endtask

    function [31:0] q16; input real v; q16=$rtoi(v*65536.0)&32'hFFFF_FFFF; endfunction
    function real fq; input [31:0] v; reg signed[31:0] s; begin s=v; fq=$itor(s)/65536.0; end endfunction

    real tv_t1[0:4],tv_a1[0:4],tv_t2[0:4],tv_a2[0:4],tv_t3[0:4],tv_a3[0:4];

    // Referencje obliczone przez Python z identyczn LUT 64-segmentow
    real ref_lin[0:4], ref_exp[0:4], ref_log[0:4];

    integer pass_cnt,fail_cnt,ev,mode;
    reg [31:0] t0_raw; real t0,ref,err; reg ok;

    initial begin
        tv_t1[0]=13.441488; tv_a1[0]=1.248941; tv_t2[0]=15.903052; tv_a2[0]=3.651062; tv_t3[0]=18.009984; tv_a3[0]=5.065083;
        tv_t1[1]=15.622099; tv_a1[1]=1.032775; tv_t2[1]=17.450997; tv_a2[1]=1.957657; tv_t3[1]=20.473995; tv_a3[1]=2.620367;
        tv_t1[2]=13.400637; tv_a1[2]=0.958252; tv_t2[2]=15.813172; tv_a2[2]=2.797585; tv_t3[2]=18.161888; tv_a3[2]=4.307609;
        tv_t1[3]=13.262626; tv_a1[3]=0.581050; tv_t2[3]=15.566904; tv_a2[3]=1.844554; tv_t3[3]=17.892898; tv_a3[3]=2.811370;
        tv_t1[4]=15.480329; tv_a1[4]=0.772686; tv_t2[4]=18.522173; tv_a2[4]=3.071598; tv_t3[4]=20.205404; tv_a3[4]=4.120738;

        ref_lin[0]=12.1617; ref_lin[1]=13.5799; ref_lin[2]=12.1438; ref_lin[3]=12.2029; ref_lin[4]=14.4579;
        ref_exp[0]= 4.5033; ref_exp[1]= 2.4356; ref_exp[2]= 6.9792; ref_exp[3]= 9.5033; ref_exp[4]= 9.8965;
        ref_log[0]=18.2697; ref_log[1]=19.8705; ref_log[2]=18.6272; ref_log[3]=17.9939; ref_log[4]=20.7619;

        pass_cnt=0; fail_cnt=0;
        wait(rstn); repeat(5) @(posedge clk);

        $display("=== Leading Edge Reconstruction - FPGA v8 vs Python (64-seg LUT) ===");
        $display("%-3s %-4s %10s %10s %8s %s","Ev","Mode","FPGA[ns]","Ref[ns]","Err[ns]","Result");
        $display("-------------------------------------------------------------------");

        for (ev=0;ev<5;ev=ev+1) begin
            for (mode=0;mode<3;mode=mode+1) begin
                axi_write(6'h20, q16(0.3));
                axi_write(6'h08, q16(tv_t1[ev])); axi_write(6'h0C, q16(tv_a1[ev]));
                axi_write(6'h10, q16(tv_t2[ev])); axi_write(6'h14, q16(tv_a2[ev]));
                axi_write(6'h18, q16(tv_t3[ev])); axi_write(6'h1C, q16(tv_a3[ev]));
                axi_write(6'h00, (mode<<1)|1);
                wait_done(ok);
                if (!ok) begin
                    $display(" %0d  %-4s  TIMEOUT FAIL",ev,(mode==0)?"LIN":(mode==1)?"EXP":"LOG");
                    fail_cnt=fail_cnt+1;
                end else begin
                    axi_read(6'h24, t0_raw); t0=fq(t0_raw);
                    ref=(mode==0)?ref_lin[ev]:(mode==1)?ref_exp[ev]:ref_log[ev];
                    err=t0-ref; if(err<0.0) err=-err;
                    // Tolerancje: LIN=0.10ns, EXP=0.55ns (metoda wrazliwa na blad ln), LOG=0.15ns
                    if ((mode==0 && err<0.10)||(mode==1 && err<0.55)||(mode==2 && err<0.15)) begin
                        $display(" %0d  %-4s %10.4f %10.4f %8.4f  PASS",ev,(mode==0)?"LIN":(mode==1)?"EXP":"LOG",t0,ref,err);
                        pass_cnt=pass_cnt+1;
                    end else begin
                        $display(" %0d  %-4s %10.4f %10.4f %8.4f  FAIL",ev,(mode==0)?"LIN":(mode==1)?"EXP":"LOG",t0,ref,err);
                        fail_cnt=fail_cnt+1;
                    end
                end
                axi_write(6'h00,32'h0); repeat(5) @(posedge clk);
            end
        end

        $display("-------------------------------------------------------------------");
        $display("WYNIK: %0d PASS,  %0d FAIL  (na 15 testow)", pass_cnt, fail_cnt);
        $display("Tolerancje: LIN=0.10ns  EXP=0.55ns  LOG=0.15ns");
        $display("Referencje: Python golden model z 64-segmentowa LUT ln");
        $finish;
    end
    initial begin $dumpfile("tb.vcd"); $dumpvars(0,TB_leading_edge); end
endmodule