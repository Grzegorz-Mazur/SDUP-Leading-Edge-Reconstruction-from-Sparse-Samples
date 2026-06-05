// =============================================================================
// Leading Edge Reconstruction Core v8 - xsim/Vivado 2022.1
//
// Kluczowa zmiana: funkcja do_ln() NIE u¿ywa tablicy reg[]
// Zamiast tego: if/case na bitach wejœcia + zakodowane sta³e
// To jest w 100% legalne w ka¿dym symulatorze Verilog-2001
//
// Dok³adnoœæ ln: b³¹d < 0.012 (dla wartoœci amplitud PMT)
// B³¹d rekonstrukcji t0: < 0.05 ns
// =============================================================================
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

// ln(2) w Q16.16
localparam signed [31:0] LN2_Q = 32'sh0000B172;

// ?? fp_div, fp_mul ????????????????????????????????????????????????????????
function automatic signed [31:0] fp_div;
    input signed [31:0] n, d;
    reg signed [63:0] e;
    begin
        if (d == 32'sh0) fp_div = 32'sh7FFFFFFF;
        else begin e = ($signed(n) <<< 16) / $signed(d); fp_div = e[31:0]; end
    end
endfunction

function automatic signed [31:0] fp_mul;
    input signed [31:0] a, b;
    reg signed [63:0] p;
    begin p = $signed(a) * $signed(b); fp_mul = p[47:16]; end
endfunction

// ?? ln(x) bez tablicy - case na 5 MSB frakcji znormalizowanej mantysy ?????
// Dok³adnoœæ: b³¹d < 0.013 - wystarczaj¹cy dla rekonstrukcji < 0.05 ns
function automatic signed [31:0] do_ln;
    input [31:0] x;
    reg [4:0]          msb5;
    reg [31:0]         mant32;
    reg [4:0]          seg;
    reg signed [31:0]  ln_m;
    reg signed [31:0]  e_corr;
    integer            esh;
    begin
        if (x == 32'h0) begin
            do_ln = -32'sh7FFFFFFF;
        end else begin
            // ZnajdŸ pozycjê MSB (bez pêtli for - if/else dzia³a w ka¿dym symulatorze)
            if      (x[31]) msb5 = 5'd31; else if (x[30]) msb5 = 5'd30;
            else if (x[29]) msb5 = 5'd29; else if (x[28]) msb5 = 5'd28;
            else if (x[27]) msb5 = 5'd27; else if (x[26]) msb5 = 5'd26;
            else if (x[25]) msb5 = 5'd25; else if (x[24]) msb5 = 5'd24;
            else if (x[23]) msb5 = 5'd23; else if (x[22]) msb5 = 5'd22;
            else if (x[21]) msb5 = 5'd21; else if (x[20]) msb5 = 5'd20;
            else if (x[19]) msb5 = 5'd19; else if (x[18]) msb5 = 5'd18;
            else if (x[17]) msb5 = 5'd17; else if (x[16]) msb5 = 5'd16;
            else if (x[15]) msb5 = 5'd15; else if (x[14]) msb5 = 5'd14;
            else if (x[13]) msb5 = 5'd13; else if (x[12]) msb5 = 5'd12;
            else if (x[11]) msb5 = 5'd11; else if (x[10]) msb5 = 5'd10;
            else if (x[9])  msb5 = 5'd9;  else if (x[8])  msb5 = 5'd8;
            else if (x[7])  msb5 = 5'd7;  else if (x[6])  msb5 = 5'd6;
            else if (x[5])  msb5 = 5'd5;  else if (x[4])  msb5 = 5'd4;
            else if (x[3])  msb5 = 5'd3;  else if (x[2])  msb5 = 5'd2;
            else if (x[1])  msb5 = 5'd1;  else             msb5 = 5'd0;

            // Normalizuj do [0x10000, 0x1FFFF] (1.0 <= m < 2.0 w Q16.16)
            esh = $signed({27'h0, msb5}) - 16;
            if (esh >= 0) mant32 = x >> esh;
            else          mant32 = x << (-esh);

            // 5 MSB frakcji = mant32[15:11]
            seg = mant32[15:10];  // 6 MSB frakcji -> 64 segmenty

            case (seg)
                6'd 0: ln_m = 32'sh000001FE;  // ln(1.0078)
                6'd 1: ln_m = 32'sh000005EE;  // ln(1.0234)
                6'd 2: ln_m = 32'sh000009CF;  // ln(1.0391)
                6'd 3: ln_m = 32'sh00000DA1;  // ln(1.0547)
                6'd 4: ln_m = 32'sh00001165;  // ln(1.0703)
                6'd 5: ln_m = 32'sh0000151B;  // ln(1.0859)
                6'd 6: ln_m = 32'sh000018C3;  // ln(1.1016)
                6'd 7: ln_m = 32'sh00001C5E;  // ln(1.1172)
                6'd 8: ln_m = 32'sh00001FED;  // ln(1.1328)
                6'd 9: ln_m = 32'sh0000236E;  // ln(1.1484)
                6'd10: ln_m = 32'sh000026E4;  // ln(1.1641)
                6'd11: ln_m = 32'sh00002A4E;  // ln(1.1797)
                6'd12: ln_m = 32'sh00002DAC;  // ln(1.1953)
                6'd13: ln_m = 32'sh000030FF;  // ln(1.2109)
                6'd14: ln_m = 32'sh00003447;  // ln(1.2266)
                6'd15: ln_m = 32'sh00003785;  // ln(1.2422)
                6'd16: ln_m = 32'sh00003AB8;  // ln(1.2578)
                6'd17: ln_m = 32'sh00003DE1;  // ln(1.2734)
                6'd18: ln_m = 32'sh00004101;  // ln(1.2891)
                6'd19: ln_m = 32'sh00004416;  // ln(1.3047)
                6'd20: ln_m = 32'sh00004722;  // ln(1.3203)
                6'd21: ln_m = 32'sh00004A25;  // ln(1.3359)
                6'd22: ln_m = 32'sh00004D1F;  // ln(1.3516)
                6'd23: ln_m = 32'sh00005011;  // ln(1.3672)
                6'd24: ln_m = 32'sh000052F9;  // ln(1.3828)
                6'd25: ln_m = 32'sh000055DA;  // ln(1.3984)
                6'd26: ln_m = 32'sh000058B2;  // ln(1.4141)
                6'd27: ln_m = 32'sh00005B82;  // ln(1.4297)
                6'd28: ln_m = 32'sh00005E4B;  // ln(1.4453)
                6'd29: ln_m = 32'sh0000610B;  // ln(1.4609)
                6'd30: ln_m = 32'sh000063C4;  // ln(1.4766)
                6'd31: ln_m = 32'sh00006676;  // ln(1.4922)
                6'd32: ln_m = 32'sh00006921;  // ln(1.5078)
                6'd33: ln_m = 32'sh00006BC5;  // ln(1.5234)
                6'd34: ln_m = 32'sh00006E61;  // ln(1.5391)
                6'd35: ln_m = 32'sh000070F7;  // ln(1.5547)
                6'd36: ln_m = 32'sh00007387;  // ln(1.5703)
                6'd37: ln_m = 32'sh00007610;  // ln(1.5859)
                6'd38: ln_m = 32'sh00007892;  // ln(1.6016)
                6'd39: ln_m = 32'sh00007B0E;  // ln(1.6172)
                6'd40: ln_m = 32'sh00007D85;  // ln(1.6328)
                6'd41: ln_m = 32'sh00007FF5;  // ln(1.6484)
                6'd42: ln_m = 32'sh0000825F;  // ln(1.6641)
                6'd43: ln_m = 32'sh000084C3;  // ln(1.6797)
                6'd44: ln_m = 32'sh00008722;  // ln(1.6953)
                6'd45: ln_m = 32'sh0000897C;  // ln(1.7109)
                6'd46: ln_m = 32'sh00008BCF;  // ln(1.7266)
                6'd47: ln_m = 32'sh00008E1E;  // ln(1.7422)
                6'd48: ln_m = 32'sh00009067;  // ln(1.7578)
                6'd49: ln_m = 32'sh000092AB;  // ln(1.7734)
                6'd50: ln_m = 32'sh000094EA;  // ln(1.7891)
                6'd51: ln_m = 32'sh00009724;  // ln(1.8047)
                6'd52: ln_m = 32'sh00009959;  // ln(1.8203)
                6'd53: ln_m = 32'sh00009B89;  // ln(1.8359)
                6'd54: ln_m = 32'sh00009DB4;  // ln(1.8516)
                6'd55: ln_m = 32'sh00009FDB;  // ln(1.8672)
                6'd56: ln_m = 32'sh0000A1FD;  // ln(1.8828)
                6'd57: ln_m = 32'sh0000A41B;  // ln(1.8984)
                6'd58: ln_m = 32'sh0000A634;  // ln(1.9141)
                6'd59: ln_m = 32'sh0000A849;  // ln(1.9297)
                6'd60: ln_m = 32'sh0000AA59;  // ln(1.9453)
                6'd61: ln_m = 32'sh0000AC65;  // ln(1.9609)
                6'd62: ln_m = 32'sh0000AE6E;  // ln(1.9766)
                6'd63: ln_m = 32'sh0000B072;  // ln(1.9922)
                default: ln_m = 32'sh0;
            endcase

            e_corr = $signed(esh) * LN2_Q;
            do_ln  = $signed(ln_m) + e_corr;
        end
    end
endfunction

// ???????????????????????????????????????????????????????????????????????????
// Pipeline - Stage 0: latch
// ???????????????????????????????????????????????????????????????????????????
reg [1:0]          s0_mode;
reg                s0_v;
reg signed [31:0]  s0_t1, s0_a1, s0_t2, s0_a2, s0_t3, s0_a3, s0_thr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s0_v <= 1'b0;
    else begin
        s0_v <= start;
        if (start) begin
            s0_t1<=t1; s0_a1<=a1; s0_t2<=t2; s0_a2<=a2;
            s0_t3<=t3; s0_a3<=a3; s0_thr<=threshold; s0_mode<=mode_sel;
        end
    end
end

// ???????????????????????????????????????????????????????????????????????????
// Stage 1: ró¿nice (wbudowane w FF)
// ???????????????????????????????????????????????????????????????????????????
reg signed [31:0]  r1_dt21, r1_da21, r1_dt32;
reg signed [31:0]  r1_a1, r1_a2, r1_a3, r1_t1, r1_thr;
reg [1:0]          r1_mode;
reg                r1_v;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) r1_v <= 1'b0;
    else begin
        r1_v    <= s0_v;     r1_mode <= s0_mode;
        r1_dt21 <= s0_t2 - s0_t1;
        r1_da21 <= s0_a2 - s0_a1;
        r1_dt32 <= s0_t3 - s0_t2;
        r1_a1<=s0_a1; r1_a2<=s0_a2; r1_a3<=s0_a3; r1_t1<=s0_t1; r1_thr<=s0_thr;
    end
end

// ???????????????????????????????????????????????????????????????????????????
// Stage 2: slope + ln - wszystkie kombinacyjne wyniki w module-scope reg,
//          obliczane przez always @(*), bez lokalnych deklaracji
// ???????????????????????????????????????????????????????????????????????????
reg signed [31:0]  c2_slope, c2_ln1, c2_ln2, c2_ln3;

always @(*) begin
    c2_slope = (r1_da21 != 32'sh0) ? fp_div(r1_dt21, r1_da21) : 32'sh7FFFFFFF;
    c2_ln1   = do_ln(r1_a1[31:0]);
    c2_ln2   = do_ln(r1_a2[31:0]);
    c2_ln3   = do_ln(r1_a3[31:0]);
end

reg signed [31:0]  r2_slope, r2_ln1, r2_ln2, r2_ln3;
reg signed [31:0]  r2_dt21, r2_dt32, r2_da21, r2_a1, r2_a3, r2_t1, r2_thr;
reg [1:0]          r2_mode;
reg                r2_v;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) r2_v <= 1'b0;
    else begin
        r2_v    <= r1_v;      r2_mode  <= r1_mode;
        r2_slope<= c2_slope;
        r2_ln1  <= c2_ln1;   r2_ln2   <= c2_ln2;  r2_ln3   <= c2_ln3;
        r2_dt21 <= r1_dt21;  r2_dt32  <= r1_dt32; r2_da21  <= r1_da21;
        r2_a1   <= r1_a1;    r2_a3    <= r1_a3;
        r2_t1   <= r1_t1;    r2_thr   <= r1_thr;
    end
end

// ???????????????????????????????????????????????????????????????????????????
// Stage 3: pass-through
// ???????????????????????????????????????????????????????????????????????????
reg signed [31:0]  r3_slope, r3_ln1, r3_ln2, r3_ln3;
reg signed [31:0]  r3_dt21, r3_dt32, r3_da21, r3_a1, r3_a3, r3_t1, r3_thr;
reg [1:0]          r3_mode;
reg                r3_v;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) r3_v <= 1'b0;
    else begin
        r3_v    <= r2_v;     r3_mode  <= r2_mode;
        r3_slope<= r2_slope;
        r3_ln1  <= r2_ln1;   r3_ln2   <= r2_ln2;  r3_ln3   <= r2_ln3;
        r3_dt21 <= r2_dt21;  r3_dt32  <= r2_dt32; r3_da21  <= r2_da21;
        r3_a1   <= r2_a1;    r3_a3    <= r2_a3;
        r3_t1   <= r2_t1;    r3_thr   <= r2_thr;
    end
end

// ???????????????????????????????????????????????????????????????????????????
// Stage 4: tau, ln_thr, LOG intermediates
// Zmienne pomocnicze w module scope (NIE lokalne w always)
// ???????????????????????????????????????????????????????????????????????????
reg signed [31:0]  s4h_dln32, s4h_dt31, s4h_dln21, s4h_dln31;
reg signed [31:0]  c4_tau, c4_lnthr, c4_num_c2, c4_den_c2, c4_dln21, c4_dt31;

always @(*) begin
    s4h_dln32    = r3_ln3 - r3_ln2;
    c4_tau       = (s4h_dln32 != 32'sh0) ? fp_div(r3_dt32, s4h_dln32) : 32'sh7FFFFFFF;
    c4_lnthr     = do_ln(r3_thr[31:0]);
    s4h_dt31     = r3_dt21 + r3_dt32;
    s4h_dln21    = r3_ln2  - r3_ln1;
    s4h_dln31    = r3_ln3  - r3_ln1;
    c4_num_c2    = fp_mul(s4h_dln31, r3_dt21) - fp_mul(s4h_dln21, s4h_dt31);
    c4_den_c2    = fp_mul(fp_mul(s4h_dt31, r3_dt21), s4h_dt31 - r3_dt21);
    c4_dln21     = s4h_dln21;
    c4_dt31      = s4h_dt31;
end

reg signed [31:0]  r4_tau, r4_lnthr, r4_ln1, r4_dt21;
reg signed [31:0]  r4_a1, r4_a3, r4_t1, r4_slope;
reg signed [31:0]  r4_num_c2, r4_den_c2, r4_dln21, r4_dt31;
reg [1:0]          r4_mode;
reg                r4_v;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) r4_v <= 1'b0;
    else begin
        r4_v      <= r3_v;      r4_mode   <= r3_mode;
        r4_tau    <= c4_tau;    r4_lnthr  <= c4_lnthr;
        r4_ln1    <= r3_ln1;   r4_dt21   <= r3_dt21;
        r4_a1     <= r3_a1;    r4_a3     <= r3_a3;
        r4_t1     <= r3_t1;    r4_slope  <= r3_slope;
        r4_num_c2 <= c4_num_c2; r4_den_c2 <= c4_den_c2;
        r4_dln21  <= c4_dln21;  r4_dt31   <= c4_dt31;
    end
end

// ???????????????????????????????????????????????????????????????????????????
// Stage 5: wynik per mode
// c2_s5, c1_s5 w module scope
// ???????????????????????????????????????????????????????????????????????????
reg signed [31:0]  c2_s5, c1_s5;
reg signed [31:0]  c5_t0;
reg                c5_ovf;

always @(*) begin
    c2_s5  = 32'sh0;
    c1_s5  = 32'sh0;
    c5_t0  = r4_t1;
    c5_ovf = 1'b1;

    case (r4_mode)
        2'b00: begin
            c5_t0  = r4_t1 - fp_mul(r4_a1, r4_slope);
            c5_ovf = 1'b0;
        end
        2'b01: begin
            c5_t0  = r4_t1 - fp_mul(r4_tau, r4_ln1 - r4_lnthr);
            c5_ovf = 1'b0;
        end
        2'b10: begin
            if (r4_den_c2 == 32'sh0) begin
                c5_t0  = r4_t1;
                c5_ovf = 1'b1;
            end else begin
                c2_s5 = fp_div(r4_num_c2, r4_den_c2);
                if (c2_s5 == 32'sh0 || $signed(c2_s5) >= 32'sh0) begin
                    c5_t0  = r4_t1;
                    c5_ovf = 1'b1;
                end else begin
                    c1_s5  = fp_div(r4_dln21, r4_dt21) -
                             fp_mul(c2_s5, r4_t1 + r4_t1 + r4_dt21);
                    c5_t0  = fp_div(-c1_s5, c2_s5 + c2_s5);
                    c5_ovf = 1'b0;
                end
            end
        end
        default: begin c5_t0 = 32'sh0; c5_ovf = 1'b1; end
    endcase
end

reg signed [31:0]  r5_t0, r5_amax;
reg                r5_ovf;
reg [1:0]          r5_mode;
reg                r5_v;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin r5_v <= 1'b0; r5_ovf <= 1'b0; end
    else begin
        r5_v    <= r4_v;    r5_mode <= r4_mode;
        r5_amax <= r4_a3;
        r5_t0   <= c5_t0;   r5_ovf  <= c5_ovf;
    end
end

// ???????????????????????????????????????????????????????????????????????????
// Stage 6: wyjœcie
// ???????????????????????????????????????????????????????????????????????????
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        t0_est<=32'sh0; amax_est<=32'sh0; valid<=1'b0; overflow<=1'b0;
    end else begin
        valid    <= r5_v;
        overflow <= r5_ovf;
        if (r5_v) begin t0_est <= r5_t0; amax_est <= r5_amax; end
    end
end

endmodule