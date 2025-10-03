// Módulo para multiplicación de números en punto flotante IEEE-754
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
    input [1:0] round_mode,     // 00=nearest even, 01=toward zero, 10=up, 11=down
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
    reg [8:0] biased_exp;              // Exponente ajustado
    reg [8:0] hp_biased_exp;           // Exponente ajustado para half precision
    
    // Parámetros
    localparam SP_EXP_BIAS = 127;
    localparam HP_EXP_BIAS = 15;
    localparam SP_EXP_MAX = 8'hFF;
    localparam HP_EXP_MAX = 5'h1F;

    // Pipeline de 2 ciclos: Etapa 1 (producto y exponente) -> Etapa 2 (normalización y flags)

    // Registros de la Etapa 1
    reg [47:0] s1_product;
    reg [8:0]  s1_exp_sum;
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
            s1_exp_sum <= 9'b0;
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

            // Normalización del producto registrado
            if (s1_product[47]) begin
                result_mant <= s1_product[46:24];
                biased_exp <= s1_exp_sum + 1;
                inexact <= (s1_product[23:0] != 24'b0);
            end else begin
                result_mant <= s1_product[45:23];
                biased_exp <= s1_exp_sum;
                inexact <= (s1_product[22:0] != 23'b0);
            end

            // Chequeo de rangos por modo
            if (mode_fp) begin
                if ($signed(biased_exp) <= 0) begin
                    result_exp <= 8'b0;
                    result_mant <= 23'b0;
                    underflow <= 1'b1;
                end else if (biased_exp >= SP_EXP_MAX) begin
                    result_exp <= SP_EXP_MAX;
                    result_mant <= 23'b0;
                    overflow <= 1'b1;
                end else begin
                    result_exp <= biased_exp[7:0];
                end
            end else begin
                hp_biased_exp <= biased_exp - SP_EXP_BIAS + HP_EXP_BIAS;
                if ($signed(hp_biased_exp) <= 0) begin
                    result_exp <= 8'b0;
                    result_mant <= 23'b0;
                    underflow <= 1'b1;
                end else if (hp_biased_exp >= HP_EXP_MAX) begin
                    result_exp <= HP_EXP_MAX - HP_EXP_BIAS + SP_EXP_BIAS;
                    result_mant <= 23'b0;
                    overflow <= 1'b1;
                end else begin
                    result_exp <= hp_biased_exp[7:0];
                end
            end
        end
    end

endmodule