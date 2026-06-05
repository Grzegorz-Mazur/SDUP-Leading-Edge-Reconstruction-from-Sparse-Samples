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

localparam signed [31:0] LN2_Q = 32'sh0000B172;

// ?? Funkcje Q16.16 ????????????????????????????????????????????????????????
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

// ?? ln(x) bez tablicy - case na 6 MSB frakcji znormalizowanej ?????????????
function automatic signed [31:0] do_ln;
    input [31:0] x;
    reg [4:0]          msb5;
    reg [31:0]         mant32;
    reg [5:0]          seg;
    reg signed [31:0]  ln_m, e_corr;
    integer            esh;
    begin
        if (x == 32'h0) begin
            do_ln = -32'sh7FFFFFFF;
        end else begin
            if      (x[31]) msb5=31; else if (x[30]) msb5=30;
            else if (x[29]) msb5=29; else if (x[28]) msb5=28;
            else if (x[27]) msb5=27; else if (x[26]) msb5=26;
            else if (x[25]) msb5=25; else if (x[24]) msb5=24;
            else if (x[23]) msb5=23; else if (x[22]) msb5=22;
            else if (x[21]) msb5=21; else if (x[20]) msb5=20;
            else if (x[19]) msb5=19; else if (x[18]) msb5=18;
            else if (x[17]) msb5=17; else if (x[16]) msb5=16;
            else if (x[15]) msb5=15; else if (x[14]) msb5=14;
            else if (x[13]) msb5=13; else if (x[12]) msb5=12;
            else if (x[11]) msb5=11; else if (x[10]) msb5=10;
            else if (x[9])  msb5=9;  else if (x[8])  msb5=8;
            else if (x[7])  msb5=7;  else if (x[6])  msb5=6;
            else if (x[5])  msb5=5;  else if (x[4])  msb5=4;
            else if (x[3])  msb5=3;  else if (x[2])  msb5=2;
            else if (x[1])  msb5=1;  else              msb5=0;

            esh = $signed({27'h0, msb5}) - 16;
            if (esh >= 0) mant32 = x >> esh;
            else          mant32 = x << (-esh);

            seg = mant32[15:10];  // 6 MSB frakcji

            case (seg)
                6'd 0: ln_m=32'sh000001FE; 6'd 1: ln_m=32'sh000005EE;
                6'd 2: ln_m=32'sh000009CF; 6'd 3: ln_m=32'sh00000DA1;
                6'd 4: ln_m=32'sh00001165; 6'd 5: ln_m=32'sh0000151B;
                6'd 6: ln_m=32'sh000018C3; 6'd 7: ln_m=32'sh00001C5E;
                6'd 8: ln_m=32'sh00001FED; 6'd 9: ln_m=32'sh0000236E;
                6'd10: ln_m=32'sh000026E4; 6'd11: ln_m=32'sh00002A4E;
                6'd12: ln_m=32'sh00002DAC; 6'd13: ln_m=32'sh000030FF;
                6'd14: ln_m=32'sh00003447; 6'd15: ln_m=32'sh00003785;
                6'd16: ln_m=32'sh00003AB8; 6'd17: ln_m=32'sh00003DE1;
                6'd18: ln_m=32'sh00004101; 6'd19: ln_m=32'sh00004416;
                6'd20: ln_m=32'sh00004722; 6'd21: ln_m=32'sh00004A25;
                6'd22: ln_m=32'sh00004D1F; 6'd23: ln_m=32'sh00005011;
                6'd24: ln_m=32'sh000052F9; 6'd25: ln_m=32'sh000055DA;
                6'd26: ln_m=32'sh000058B2; 6'd27: ln_m=32'sh00005B82;
                6'd28: ln_m=32'sh00005E4B; 6'd29: ln_m=32'sh0000610B;
                6'd30: ln_m=32'sh000063C4; 6'd31: ln_m=32'sh00006676;
                6'd32: ln_m=32'sh00006921; 6'd33: ln_m=32'sh00006BC5;
                6'd34: ln_m=32'sh00006E61; 6'd35: ln_m=32'sh000070F7;
                6'd36: ln_m=32'sh00007387; 6'd37: ln_m=32'sh00007610;
                6'd38: ln_m=32'sh00007892; 6'd39: ln_m=32'sh00007B0E;
                6'd40: ln_m=32'sh00007D85; 6'd41: ln_m=32'sh00007FF5;
                6'd42: ln_m=32'sh0000825F; 6'd43: ln_m=32'sh000084C3;
                6'd44: ln_m=32'sh00008722; 6'd45: ln_m=32'sh0000897C;
                6'd46: ln_m=32'sh00008BCF; 6'd47: ln_m=32'sh00008E1E;
                6'd48: ln_m=32'sh00009067; 6'd49: ln_m=32'sh000092AB;
                6'd50: ln_m=32'sh000094EA; 6'd51: ln_m=32'sh00009724;
                6'd52: ln_m=32'sh00009959; 6'd53: ln_m=32'sh00009B89;
                6'd54: ln_m=32'sh00009DB4; 6'd55: ln_m=32'sh00009FDB;
                6'd56: ln_m=32'sh0000A1FD; 6'd57: ln_m=32'sh0000A41B;
                6'd58: ln_m=32'sh0000A634; 6'd59: ln_m=32'sh0000A849;
                6'd60: ln_m=32'sh0000AA59; 6'd61: ln_m=32'sh0000AC65;
                6'd62: ln_m=32'sh0000AE6E; 6'd63: ln_m=32'sh0000B072;
                default: ln_m=32'sh0;
            endcase

            e_corr = $signed(esh) * LN2_Q;
            do_ln  = $signed(ln_m) + e_corr;
        end
    end
endfunction

// =========================================================================
// Pipeline rejestrowy
// =========================================================================

// Stage 0: latch
reg [1:0] s0_mode; reg s0_v;
reg signed [31:0] s0_t1,s0_a1,s0_t2,s0_a2,s0_t3,s0_a3,s0_thr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s0_v <= 0;
    else begin
        s0_v <= start;
        if (start) begin
            s0_t1<=t1; s0_a1<=a1; s0_t2<=t2; s0_a2<=a2;
            s0_t3<=t3; s0_a3<=a3; s0_thr<=threshold; s0_mode<=mode_sel;
        end
    end
end

// Stage 1: ró¿nice
reg [1:0] s1_mode; reg s1_v;
reg signed [31:0] s1_dt21,s1_da21,s1_dt32,s1_a1,s1_a2,s1_a3,s1_t1,s1_thr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s1_v <= 0;
    else begin
        s1_v<=s0_v; s1_mode<=s0_mode;
        s1_dt21<=s0_t2-s0_t1; s1_da21<=s0_a2-s0_a1; s1_dt32<=s0_t3-s0_t2;
        s1_a1<=s0_a1; s1_a2<=s0_a2; s1_a3<=s0_a3; s1_t1<=s0_t1; s1_thr<=s0_thr;
    end
end

// Stage 2: slope + ln - WEWN¥TRZ posedge clk (blocking =)
reg [1:0] s2_mode; reg s2_v;
reg signed [31:0] s2_slope,s2_ln1,s2_ln2,s2_ln3;
reg signed [31:0] s2_dt21,s2_dt32,s2_da21,s2_a1,s2_a3,s2_t1,s2_thr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s2_v <= 0;
    else begin
        s2_v    = s1_v;    s2_mode = s1_mode;  // blocking
        s2_slope= (s1_da21!=0) ? fp_div(s1_dt21,s1_da21) : 32'sh7FFFFFFF;
        s2_ln1  = do_ln(s1_a1[31:0]);
        s2_ln2  = do_ln(s1_a2[31:0]);
        s2_ln3  = do_ln(s1_a3[31:0]);
        s2_dt21 = s1_dt21; s2_dt32 = s1_dt32; s2_da21 = s1_da21;
        s2_a1   = s1_a1;   s2_a3   = s1_a3;
        s2_t1   = s1_t1;   s2_thr  = s1_thr;
    end
end

// Stage 3: pass-through
reg [1:0] s3_mode; reg s3_v;
reg signed [31:0] s3_slope,s3_ln1,s3_ln2,s3_ln3;
reg signed [31:0] s3_dt21,s3_dt32,s3_a1,s3_a3,s3_t1,s3_thr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s3_v <= 0;
    else begin
        s3_v    <= s2_v;    s3_mode  <= s2_mode;
        s3_slope<= s2_slope; s3_ln1  <= s2_ln1; s3_ln2 <= s2_ln2; s3_ln3 <= s2_ln3;
        s3_dt21 <= s2_dt21; s3_dt32  <= s2_dt32;
        s3_a1   <= s2_a1;   s3_a3    <= s2_a3;
        s3_t1   <= s2_t1;   s3_thr   <= s2_thr;
    end
end

// Stage 4: tau, lnthr, LOG params - WEWN¥TRZ posedge clk (blocking =)
reg [1:0] s4_mode; reg s4_v;
reg signed [31:0] s4_tau,s4_lnthr,s4_ln1,s4_dt21;
reg signed [31:0] s4_a1,s4_a3,s4_t1,s4_slope;
reg signed [31:0] s4_num_c2,s4_den_c2,s4_dln21,s4_dt31;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s4_v <= 0;
    else begin : stage4_calc
        reg signed [31:0] dln32,dt31,dln21,dln31;

        s4_v    = s3_v;     s4_mode  = s3_mode;
        s4_a1   = s3_a1;    s4_a3    = s3_a3;
        s4_t1   = s3_t1;    s4_slope = s3_slope;
        s4_ln1  = s3_ln1;   s4_dt21  = s3_dt21;

        dln32      = s3_ln3 - s3_ln2;
        s4_tau     = (dln32 != 0) ? fp_div(s3_dt32, dln32) : 32'sh7FFFFFFF;
        s4_lnthr   = do_ln(s3_thr[31:0]);

        dt31       = s3_dt21 + s3_dt32;
        dln21      = s3_ln2  - s3_ln1;
        dln31      = s3_ln3  - s3_ln1;
        s4_num_c2  = fp_mul(dln31, s3_dt21) - fp_mul(dln21, dt31);
        s4_den_c2  = fp_mul(fp_mul(dt31, s3_dt21), dt31 - s3_dt21);
        s4_dln21   = dln21;
        s4_dt31    = dt31;
    end
end

// Stage 5: wynik per mode - WEWN¥TRZ posedge clk (blocking =)
reg [1:0] s5_mode; reg s5_v;
reg signed [31:0] s5_t0, s5_amax;
reg               s5_ovf;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin s5_v<=0; s5_ovf<=0; end
    else begin : stage5_calc
        reg signed [31:0] c2, c1;

        s5_v    = s4_v;
        s5_mode = s4_mode;
        s5_amax = s4_a3;
        s5_ovf  = 0;
        s5_t0   = s4_t1;

        case (s4_mode)
            2'b00: begin
                s5_t0 = s4_t1 - fp_mul(s4_a1, s4_slope);
                s5_ovf = 0;
            end
            2'b01: begin
                s5_t0 = s4_t1 - fp_mul(s4_tau, s4_ln1 - s4_lnthr);
                s5_ovf = 0;
            end
            2'b10: begin
                if (s4_den_c2 == 32'sh0) begin
                    s5_t0  = s4_t1;
                    s5_ovf = 1;
                end else begin
                    c2 = fp_div(s4_num_c2, s4_den_c2);
                    if (c2 == 32'sh0 || $signed(c2) >= 32'sh0) begin
                        s5_t0  = s4_t1;
                        s5_ovf = 1;
                    end else begin
                        c1     = fp_div(s4_dln21, s4_dt21) -
                                 fp_mul(c2, s4_t1 + s4_t1 + s4_dt21);
                        s5_t0  = fp_div(-c1, c2 + c2);
                        s5_ovf = 0;
                    end
                end
            end
            default: begin s5_t0 = 0; s5_ovf = 1; end
        endcase
    end
end

// Stage 6: output
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin t0_est<=0; amax_est<=0; valid<=0; overflow<=0; end
    else begin
        valid    <= s5_v;
        overflow <= s5_ovf;
        if (s5_v) begin t0_est <= s5_t0; amax_est <= s5_amax; end
    end
end

endmodule