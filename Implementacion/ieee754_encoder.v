// Codificador IEEE-754 para single precision (32 bits) y half precision (16 bits)
module ieee754_encoder(
    input mode_fp,              // 0=half precision, 1=single precision
    input sign,                 // Signo del resultado
    input [7:0] exp,           // Exponente (formato interno extendido)
    input [22:0] mant,         // Mantisa (formato interno extendido)
    output reg [31:0] fp_result // Resultado en formato IEEE-754
);

    // Parámetros para conversión de exponentes
    localparam SP_EXP_BIAS = 127;
    localparam HP_EXP_BIAS = 15;
    
    // Variables locales
    reg [4:0] hp_exp;
    reg [9:0] hp_mant;
    reg [8:0] temp_exp;

    always @(*) begin
        if (mode_fp) begin
            // Single precision (32 bits)
            fp_result = {sign, exp, mant};
        end else begin
            // Half precision (16 bits) - conversión desde formato extendido
            
            // Convertir exponente
            if (exp == 8'b0) begin
                hp_exp = 5'b0; // Cero o denormal
            end else if (exp == 8'hFF) begin
                hp_exp = 5'h1F; // Infinito o NaN
            end else begin
                // Convertir bias: de single precision (127) a half precision (15)
                temp_exp = exp - SP_EXP_BIAS + HP_EXP_BIAS;
                
                if (temp_exp <= 0) begin
                    hp_exp = 5'b0; // Underflow -> cero
                end else if (temp_exp >= 5'h1F) begin
                    hp_exp = 5'h1F; // Overflow -> infinito
                end else begin
                    hp_exp = temp_exp[4:0];
                end
            end
            
            // Convertir mantisa (tomar los 10 bits más significativos)
            hp_mant = mant[22:13];
            
            // Ensamblar resultado en half precision en los 16 bits superiores
            fp_result = {{sign, hp_exp, hp_mant}, 16'b0};
        end
    end

endmodule