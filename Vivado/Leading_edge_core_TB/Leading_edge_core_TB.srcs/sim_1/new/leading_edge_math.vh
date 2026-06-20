// -----------------------------------------------------------------------------
// Shared fixed-point math for leading_edge_core
// -----------------------------------------------------------------------------
// Numeric format:
//   signed Q16.16, where 1.0 == 32'h0001_0000.
//
// Keep this file included inside a module.  The functions are intentionally
// small and named after the operation they perform.
// -----------------------------------------------------------------------------

localparam signed [31:0] Q16_MAX = 32'sh7FFFFFFF;
localparam signed [31:0] LN2_Q   = 32'sh0000B172;

function automatic signed [31:0] q16_mul;
    input signed [31:0] lhs;
    input signed [31:0] rhs;
    reg signed [63:0] product;
    begin
        product = $signed(lhs) * $signed(rhs);
        q16_mul = product[47:16];
    end
endfunction

function automatic signed [31:0] q16_div;
    input signed [31:0] numerator;
    input signed [31:0] denominator;
    reg signed [63:0] expanded;
    begin
        if (denominator == 32'sh0) begin
            q16_div = Q16_MAX;
        end else begin
            expanded = ($signed(numerator) <<< 16) / $signed(denominator);
            q16_div  = expanded[31:0];
        end
    end
endfunction

function automatic [4:0] q16_find_msb;
    input [31:0] value;
    integer bit_index;
    begin
        q16_find_msb = 5'd0;
        for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
            if (value[bit_index])
                q16_find_msb = bit_index[4:0];
        end
    end
endfunction

function automatic [31:0] q16_normalize_mantissa;
    input [31:0] value;
    input integer exponent_shift;
    begin
        if (exponent_shift >= 0)
            q16_normalize_mantissa = value >> exponent_shift;
        else
            q16_normalize_mantissa = value << (-exponent_shift);
    end
endfunction

function automatic signed [31:0] q16_ln_lut_64;
    input [5:0] segment;
    begin
        case (segment)
            6'd 0: q16_ln_lut_64=32'sh000001FE; 6'd 1: q16_ln_lut_64=32'sh000005EE;
            6'd 2: q16_ln_lut_64=32'sh000009CF; 6'd 3: q16_ln_lut_64=32'sh00000DA1;
            6'd 4: q16_ln_lut_64=32'sh00001165; 6'd 5: q16_ln_lut_64=32'sh0000151B;
            6'd 6: q16_ln_lut_64=32'sh000018C3; 6'd 7: q16_ln_lut_64=32'sh00001C5E;
            6'd 8: q16_ln_lut_64=32'sh00001FED; 6'd 9: q16_ln_lut_64=32'sh0000236E;
            6'd10: q16_ln_lut_64=32'sh000026E4; 6'd11: q16_ln_lut_64=32'sh00002A4E;
            6'd12: q16_ln_lut_64=32'sh00002DAC; 6'd13: q16_ln_lut_64=32'sh000030FF;
            6'd14: q16_ln_lut_64=32'sh00003447; 6'd15: q16_ln_lut_64=32'sh00003785;
            6'd16: q16_ln_lut_64=32'sh00003AB8; 6'd17: q16_ln_lut_64=32'sh00003DE1;
            6'd18: q16_ln_lut_64=32'sh00004101; 6'd19: q16_ln_lut_64=32'sh00004416;
            6'd20: q16_ln_lut_64=32'sh00004722; 6'd21: q16_ln_lut_64=32'sh00004A25;
            6'd22: q16_ln_lut_64=32'sh00004D1F; 6'd23: q16_ln_lut_64=32'sh00005011;
            6'd24: q16_ln_lut_64=32'sh000052F9; 6'd25: q16_ln_lut_64=32'sh000055DA;
            6'd26: q16_ln_lut_64=32'sh000058B2; 6'd27: q16_ln_lut_64=32'sh00005B82;
            6'd28: q16_ln_lut_64=32'sh00005E4B; 6'd29: q16_ln_lut_64=32'sh0000610B;
            6'd30: q16_ln_lut_64=32'sh000063C4; 6'd31: q16_ln_lut_64=32'sh00006676;
            6'd32: q16_ln_lut_64=32'sh00006921; 6'd33: q16_ln_lut_64=32'sh00006BC5;
            6'd34: q16_ln_lut_64=32'sh00006E61; 6'd35: q16_ln_lut_64=32'sh000070F7;
            6'd36: q16_ln_lut_64=32'sh00007387; 6'd37: q16_ln_lut_64=32'sh00007610;
            6'd38: q16_ln_lut_64=32'sh00007892; 6'd39: q16_ln_lut_64=32'sh00007B0E;
            6'd40: q16_ln_lut_64=32'sh00007D85; 6'd41: q16_ln_lut_64=32'sh00007FF5;
            6'd42: q16_ln_lut_64=32'sh0000825F; 6'd43: q16_ln_lut_64=32'sh000084C3;
            6'd44: q16_ln_lut_64=32'sh00008722; 6'd45: q16_ln_lut_64=32'sh0000897C;
            6'd46: q16_ln_lut_64=32'sh00008BCF; 6'd47: q16_ln_lut_64=32'sh00008E1E;
            6'd48: q16_ln_lut_64=32'sh00009067; 6'd49: q16_ln_lut_64=32'sh000092AB;
            6'd50: q16_ln_lut_64=32'sh000094EA; 6'd51: q16_ln_lut_64=32'sh00009724;
            6'd52: q16_ln_lut_64=32'sh00009959; 6'd53: q16_ln_lut_64=32'sh00009B89;
            6'd54: q16_ln_lut_64=32'sh00009DB4; 6'd55: q16_ln_lut_64=32'sh00009FDB;
            6'd56: q16_ln_lut_64=32'sh0000A1FD; 6'd57: q16_ln_lut_64=32'sh0000A41B;
            6'd58: q16_ln_lut_64=32'sh0000A634; 6'd59: q16_ln_lut_64=32'sh0000A849;
            6'd60: q16_ln_lut_64=32'sh0000AA59; 6'd61: q16_ln_lut_64=32'sh0000AC65;
            6'd62: q16_ln_lut_64=32'sh0000AE6E; 6'd63: q16_ln_lut_64=32'sh0000B072;
            default: q16_ln_lut_64=32'sh0;
        endcase
    end
endfunction

function automatic signed [31:0] q16_ln;
    input [31:0] value;
    reg [4:0] msb_index;
    reg [31:0] mantissa_q16;
    reg [5:0] lut_segment;
    integer exponent_shift;
    reg signed [31:0] mantissa_ln;
    reg signed [31:0] exponent_ln;
    begin
        if (value == 32'h0) begin
            q16_ln = -Q16_MAX;
        end else begin
            msb_index      = q16_find_msb(value);
            exponent_shift = $signed({27'h0, msb_index}) - 16;
            mantissa_q16   = q16_normalize_mantissa(value, exponent_shift);
            lut_segment    = mantissa_q16[15:10];
            mantissa_ln    = q16_ln_lut_64(lut_segment);
            exponent_ln    = $signed(exponent_shift) * LN2_Q;
            q16_ln         = $signed(mantissa_ln) + exponent_ln;
        end
    end
endfunction
