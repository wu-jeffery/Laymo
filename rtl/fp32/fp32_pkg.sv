`timescale 1ns/1ps

// Combinational binary32 operations for a small inference-oriented MAC.
// Round to nearest, ties to even. Subnormal inputs/results flush to zero.
package fp32_pkg;
    localparam logic [31:0] QNAN = 32'h7fc00000;

    function automatic logic [26:0] shift_right_jam27(
        input logic [26:0] value,
        input int unsigned amount
    );
        logic [26:0] mask;
        if (amount == 0)
            return value;
        if (amount >= 27)
            return {26'b0, (|value)};
        mask = (27'b1 << amount) - 27'b1;
        return (value >> amount) | {26'b0, (|(value & mask))};
    endfunction

    function automatic logic [31:0] fp32_mul(
        input logic [31:0] x,
        input logic [31:0] y
    );
        logic sign;
        logic x_zero, y_zero, x_inf, y_inf, x_nan, y_nan;
        logic [47:0] product;
        logic [23:0] mantissa;
        logic guard_bit, round_bit, sticky_bit;
        logic [24:0] rounded;
        int signed exponent;

        sign = x[31] ^ y[31];
        x_zero = (x[30:23] == 0);
        y_zero = (y[30:23] == 0);
        x_inf = (x[30:23] == 8'hff) && (x[22:0] == 0);
        y_inf = (y[30:23] == 8'hff) && (y[22:0] == 0);
        x_nan = (x[30:23] == 8'hff) && (x[22:0] != 0);
        y_nan = (y[30:23] == 8'hff) && (y[22:0] != 0);

        if (x_nan || y_nan || ((x_inf || y_inf) && (x_zero || y_zero)))
            return QNAN;
        if (x_inf || y_inf)
            return {sign, 8'hff, 23'b0};
        if (x_zero || y_zero)
            return {sign, 31'b0};

        product = {1'b1, x[22:0]} * {1'b1, y[22:0]};
        exponent = int'(x[30:23]) + int'(y[30:23]) - 127;
        if (product[47]) begin
            exponent++;
            mantissa = product[47:24];
            guard_bit = product[23];
            round_bit = product[22];
            sticky_bit = |product[21:0];
        end else begin
            mantissa = product[46:23];
            guard_bit = product[22];
            round_bit = product[21];
            sticky_bit = |product[20:0];
        end

        rounded = {1'b0, mantissa} +
                  {24'b0, (guard_bit && (round_bit || sticky_bit || mantissa[0]))};
        if (rounded[24]) begin
            exponent++;
            mantissa = rounded[24:1];
        end else begin
            mantissa = rounded[23:0];
        end

        if (exponent >= 255)
            return {sign, 8'hff, 23'b0};
        if (exponent <= 0)
            return {sign, 31'b0};
        return {sign, 8'(exponent), mantissa[22:0]};
    endfunction

    function automatic logic [31:0] fp32_add(
        input logic [31:0] x,
        input logic [31:0] y
    );
        logic x_zero, y_zero, x_inf, y_inf, x_nan, y_nan;
        logic sign, big_sign;
        logic [7:0] big_exp, small_exp;
        logic [22:0] big_frac, small_frac;
        logic [26:0] big_sig, small_sig, aligned_sig, sig;
        logic [27:0] sum;
        logic [24:0] rounded;
        int signed exponent;

        x_zero = (x[30:23] == 0);
        y_zero = (y[30:23] == 0);
        x_inf = (x[30:23] == 8'hff) && (x[22:0] == 0);
        y_inf = (y[30:23] == 8'hff) && (y[22:0] == 0);
        x_nan = (x[30:23] == 8'hff) && (x[22:0] != 0);
        y_nan = (y[30:23] == 8'hff) && (y[22:0] != 0);

        if (x_nan || y_nan || (x_inf && y_inf && (x[31] != y[31])))
            return QNAN;
        if (x_inf)
            return x;
        if (y_inf)
            return y;
        if (x_zero && y_zero)
            return 32'b0;
        if (x_zero)
            return y;
        if (y_zero)
            return x;

        if ((x[30:23] > y[30:23]) ||
            ((x[30:23] == y[30:23]) && (x[22:0] >= y[22:0]))) begin
            big_exp = x[30:23];
            small_exp = y[30:23];
            big_frac = x[22:0];
            small_frac = y[22:0];
            big_sign = x[31];
        end else begin
            big_exp = y[30:23];
            small_exp = x[30:23];
            big_frac = y[22:0];
            small_frac = x[22:0];
            big_sign = y[31];
        end

        big_sig = {1'b1, big_frac, 3'b000};
        small_sig = {1'b1, small_frac, 3'b000};
        aligned_sig = shift_right_jam27(small_sig, int'(big_exp) - int'(small_exp));
        exponent = int'(big_exp);
        sign = big_sign;

        if (x[31] == y[31]) begin
            sum = {1'b0, big_sig} + {1'b0, aligned_sig};
            if (sum[27]) begin
                sig = sum[27:1] | {26'b0, sum[0]};
                exponent++;
            end else begin
                sig = sum[26:0];
            end
        end else begin
            sig = big_sig - aligned_sig;
            if (sig == 0)
                return 32'b0;
            for (int i = 0; i < 26; i++) begin
                if (!sig[26]) begin
                    sig = sig << 1;
                    exponent--;
                end
            end
        end

        if (exponent <= 0)
            return {sign, 31'b0};

        rounded = {1'b0, sig[26:3]} +
                  {24'b0, (sig[2] && (sig[1] || sig[0] || sig[3]))};
        if (rounded[24]) begin
            exponent++;
            rounded = rounded >> 1;
        end

        if (exponent >= 255)
            return {sign, 8'hff, 23'b0};
        return {sign, 8'(exponent), rounded[22:0]};
    endfunction
endpackage
