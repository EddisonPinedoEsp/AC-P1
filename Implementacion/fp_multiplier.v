`timescale 1ns / 1ps
module fp_multiplier(
    input clk,
    input rst,
    input mode_fp,              // 0=half precision, 1=single precision
    input sign_a,
    input sign_b,
    input [7:0] exp_a,
    input [7:0] exp_b,
    input [22:0] mant_a,
    input [22:0] mant_b,
    input round_mode,           // nearest
    output reg result_sign,
    output reg [7:0] result_exp,
    output reg [22:0] result_mant,
    output reg overflow,
    output reg underflow,
    output reg inexact
);

    // Señales internas
    reg [23:0] mant_a_ext, mant_b_ext;  // Mantisas con bit implícito
    reg [47:0] product;                 // Producto de mantisas
    reg [8:0] exp_sum;                 // Suma de exponentes (9 bits para detectar overflow)
    reg signed [9:0] biased_exp;              // Exponente ajustado (signed, 10 bits para overflow detection)
    reg signed [9:0] hp_biased_exp;           // Exponente ajustado para half precision (signed, 10 bits)
    // Temporales para normalización/redondeo (declarados a nivel de módulo para Verilog-2001)
    reg [22:0] mant_pre;
    reg guard_bit, round_bit, sticky_bit;
    reg [23:0] mant_rounded;
    integer shift_amount;
    reg [47:0] frac_ext, shifted;
    reg [22:0] mpre;
    reg gb, rb, sb;
    reg [23:0] mround;
    integer shift_amount_hp;
    reg [47:0] frac_ext_hp, shifted_hp;
    reg [9:0] half_pre;
    reg gbh, rbh, sbh;
    reg [10:0] half_round;
    
    // Parámetros
    localparam SP_EXP_BIAS = 127;
    localparam HP_EXP_BIAS = 15;
    localparam SP_EXP_MAX = 8'hFF;
    localparam HP_EXP_MAX = 5'h1F;

    // Pipeline de 2 ciclos: Etapa 1 (producto y exponente) -> Etapa 2 (normalización y flags)

    // Registros de la Etapa 1
    reg [47:0] s1_product;
    reg signed [9:0]  s1_exp_sum;
    reg        s1_sign;

    always @(posedge clk) begin
        if (rst) begin
            // Reset salida
            result_sign <= 1'b0;
            result_exp <= 8'b0;
            result_mant <= 23'b0;
            overflow <= 1'b0;
            underflow <= 1'b0;
            inexact <= 1'b0;

            // Reset S1
            mant_a_ext <= 24'b0;
            mant_b_ext <= 24'b0;
            s1_product <= 48'b0;
            s1_exp_sum <= 10'b0;
            s1_sign <= 1'b0;
        end else begin
            // ===== Etapa 1 =====
            mant_a_ext <= {1'b1, mant_a};
            mant_b_ext <= {1'b1, mant_b};
            s1_product <= {1'b1, mant_a} * {1'b1, mant_b};
            s1_exp_sum <= exp_a + exp_b - SP_EXP_BIAS;
            s1_sign <= sign_a ^ sign_b;

            // ===== Etapa 2 =====
            result_sign <= s1_sign;
            overflow <= 1'b0;
            underflow <= 1'b0;

            // Normalización del producto registrado con GRS y tie-to-even
            if (s1_product[47]) begin
                mant_pre = s1_product[46:24];
                guard_bit = s1_product[23];
                round_bit = s1_product[22];
                sticky_bit = (s1_product[21:0] != 22'b0);
                biased_exp <= s1_exp_sum + 1;
            end else begin
                mant_pre = s1_product[45:23];
                guard_bit = s1_product[22];
                round_bit = s1_product[21];
                sticky_bit = (s1_product[20:0] != 21'b0);
                biased_exp <= s1_exp_sum;
            end
            mant_rounded = {1'b0, mant_pre};
            if (guard_bit && (round_bit | sticky_bit | mant_pre[0])) begin
                mant_rounded = mant_rounded + 24'd1;
            end
            inexact <= guard_bit | round_bit | sticky_bit;
            if (mant_rounded[23]) begin
                result_mant <= 23'b0;
                biased_exp <= biased_exp + 1;
            end else begin
                result_mant <= mant_rounded[22:0];
            end

            // Chequeo de rangos por modo (subnormales y saturación)
            if (mode_fp) begin
                if (biased_exp <= 0) begin
                    // Generar subnormal en single: desplazar a la derecha (1 - biased_exp)
                    shift_amount = (1 - biased_exp);
                    frac_ext = {result_mant, 24'b0};
                    if (shift_amount >= 48) begin
                        result_exp <= 8'b0;
                        result_mant <= 23'b0;
                        inexact <= 1'b1;
                    end else begin
                        shifted = frac_ext >> (shift_amount); // ya incluye 24 bits para GRS
                        mpre = shifted[47:25];
                        gb = shifted[24];
                        rb = shifted[23];
                        sb = (shifted[22:0] != 23'b0) | inexact;
                        mround = {1'b0, mpre};
                        if (gb && (rb | sb | mpre[0])) begin
                            mround = mround + 24'd1;
                        end
                        result_exp <= 8'b0;
                        result_mant <= mround[22:0];
                        inexact <= gb | rb | sb;
                    end
                    underflow <= 1'b1;
                end else if (biased_exp >= SP_EXP_MAX) begin
                    // Overflow: generar infinito (exponente = 255, mantisa = 0)
                    result_exp <= SP_EXP_MAX;
                    result_mant <= 23'b0;
                    overflow <= 1'b1;
                end else begin
                    result_exp <= biased_exp[7:0];
                end
            end else begin
                hp_biased_exp <= biased_exp - SP_EXP_BIAS + HP_EXP_BIAS;
                if (hp_biased_exp <= 0) begin
                    // Underflow en half (generará subnormal en encoder). Mantener exp interna >=1.
                    result_exp <= (biased_exp <= 0) ? 8'd1 : biased_exp[7:0];
                    underflow <= 1'b1;
                end else if (hp_biased_exp >= HP_EXP_MAX) begin
                    // Overflow en half precision: generar infinito
                    result_exp <= 8'hFF; // Usar valor de infinito en formato interno
                    result_mant <= 23'b0;
                    overflow <= 1'b1;
                end else begin
                    // Exponente interno normal
                    result_exp <= biased_exp[7:0];
                end
            end
        end
    end

endmodule