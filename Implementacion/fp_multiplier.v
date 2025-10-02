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

    always @(posedge clk) begin
        if (rst) begin
            result_sign <= 1'b0;
            result_exp <= 8'b0;
            result_mant <= 23'b0;
            overflow <= 1'b0;
            underflow <= 1'b0;
            inexact <= 1'b0;
        end else begin
            // Calcular signo del resultado (XOR de los signos)
            result_sign <= sign_a ^ sign_b;
            
            // Agregar bit implícito a las mantisas
            mant_a_ext <= {1'b1, mant_a};
            mant_b_ext <= {1'b1, mant_b};
            
            // Multiplicar mantisas
            product <= mant_a_ext * mant_b_ext;
            
            // Sumar exponentes y restar bias
            exp_sum <= exp_a + exp_b - SP_EXP_BIAS;
            
            // Verificar si el producto requiere normalización
            if (product[47]) begin
                // El producto es >= 2.0, necesita shift a la derecha
                result_mant <= product[46:24];
                biased_exp <= exp_sum + 1;
                inexact <= (product[23:0] != 24'b0);
            end else begin
                // El producto es < 2.0, normalizado
                result_mant <= product[45:23];
                biased_exp <= exp_sum;
                inexact <= (product[22:0] != 23'b0);
            end
            
            // Verificar overflow y underflow
            if (mode_fp) begin
                // Single precision
                if (biased_exp >= SP_EXP_MAX) begin
                    // Overflow
                    result_exp <= SP_EXP_MAX;
                    result_mant <= 23'b0; // Infinito
                    overflow <= 1'b1;
                end else if (biased_exp <= 0) begin
                    // Underflow
                    result_exp <= 8'b0;
                    result_mant <= 23'b0; // Cero
                    underflow <= 1'b1;
                end else begin
                    result_exp <= biased_exp[7:0];
                    overflow <= 1'b0;
                    underflow <= 1'b0;
                end
            end else begin
                // Half precision - convertir rango de exponente
                hp_biased_exp <= biased_exp - SP_EXP_BIAS + HP_EXP_BIAS;
                
                if (hp_biased_exp >= HP_EXP_MAX) begin
                    // Overflow en half precision
                    result_exp <= HP_EXP_MAX - HP_EXP_BIAS + SP_EXP_BIAS;
                    result_mant <= {13'b0, 10'b0}; // Infinito en formato extendido
                    overflow <= 1'b1;
                end else if (hp_biased_exp <= 0) begin
                    // Underflow en half precision
                    result_exp <= 8'b0;
                    result_mant <= 23'b0; // Cero
                    underflow <= 1'b1;
                end else begin
                    result_exp <= hp_biased_exp[7:0];
                    overflow <= 1'b0;
                    underflow <= 1'b0;
                end
            end
        end
    end

endmodule