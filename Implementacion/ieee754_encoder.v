`timescale 1ns / 1ps
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
    reg [4:0] hp_exp;          // Exponente para half (incluye 0 y 31 reservados)
    reg [9:0] hp_mant;         // Fracción para half
    reg signed [9:0] e_unbiased;  // Exponente sin sesgo (formato interno) relativo a single
    reg signed [9:0] e_half;      // Exponente con sesgo de half antes de saturación
    reg [23:0] sig;               // 1.mant (24 bits)
    reg guard_bit, round_bit, sticky_bit;
    reg [10:0] rounded_frac;      // Fracción con bit extra para detectar carry
    integer shift_amount;         // Para subnormales
    // moved outside of always: temporary vectors used in subnormal path
    reg [37:0] sig_ext;
    reg [37:0] shifted;

    always @(*) begin
        if (mode_fp) begin
            // Single precision (32 bits)
            fp_result = {sign, exp, mant};
        end else begin
            // Half precision (16 bits) - conversión desde formato extendido
            // Construir significando extendido y exponente sin sesgo
            sig = {1'b1, mant}; // 1.mant de 24 bits
            if (exp == 8'h00) begin
                // Cero/subnormal en formato interno (ya normalizado previamente)
                // Empaquetar como cero en half
                hp_exp = 5'b0;
                hp_mant = 10'b0;
                fp_result = {16'b0, sign, hp_exp, hp_mant};
            end else if (exp == 8'hFF) begin
                // Infinito o NaN
                hp_exp = 5'h1F;
                // Si mant != 0 -> NaN: mapear a qNaN simple en half (payload no preservado)
                hp_mant = (mant != 23'b0) ? 10'h200 : 10'b0; // 01x... para qNaN
                fp_result = {16'b0, sign, hp_exp, hp_mant};
            end else begin
                // Convertir a rango de half
                e_unbiased = $signed({1'b0, exp}) - $signed(SP_EXP_BIAS); // exp - 127
                e_half = e_unbiased + $signed(HP_EXP_BIAS);               // +15

                if (e_half >= 5'd31) begin
                    // Overflow en half -> infinito
                    hp_exp = 5'h1F;
                    hp_mant = 10'b0;
                    fp_result = {16'b0, sign, hp_exp, hp_mant};
                end else if (e_half >= 5'd1) begin
                    // Número normalizado en half
                    // Reducir 24->(1+10) bits con GRS: necesitamos 10 de fracción
                    // Desplazar 24-1-10 = 13 bits para obtener fracción; GRS son los 13 bits descartados
                    guard_bit = sig[13];
                    round_bit = sig[12];
                    sticky_bit = (sig[11:0] != 12'b0);
                    hp_mant = sig[23:14]; // 10 MSBs después del 1 implícito

                    // Tie-to-even
                    rounded_frac = {1'b0, hp_mant};
                    if (guard_bit && (round_bit | sticky_bit | hp_mant[0])) begin
                        rounded_frac = {1'b0, hp_mant} + 11'd1;
                    end

                    // Manejar carry de redondeo en fracción
                    if (rounded_frac[10]) begin
                        // overflow en fracción -> incrementar exponente
                        if (e_half + 1 >= 5'd31) begin
                            // Se satura a infinito
                            hp_exp = 5'h1F;
                            hp_mant = 10'b0;
                        end else begin
                            // Evitar indexado de expresión, usar temporal
                            begin : inc_half_exp_block
                                reg [9:0] tmp_inc;
                                tmp_inc = e_half + 1;
                                hp_exp = tmp_inc[4:0];
                            end
                            hp_mant = 10'b0; // 1.111.. redondeado -> 10.000.. con exponente +1 -> fracción 0
                        end
                    end else begin
                        hp_exp = e_half[4:0];
                        hp_mant = rounded_frac[9:0];
                    end

                    fp_result = {16'b0, sign, hp_exp, hp_mant};
                end else begin
                    // Subnormal en half (e_half <= 0)
                    // Shift necesario para colocar el 1 implícito dentro de la fracción
                    // Para half, el valor efectivo es 1.xxx * 2^(e_unbiased). Cuando e_half <= 0,
                    // debemos desplazar a la derecha (1 - e_half) posiciones antes de recortar a 10 bits.
                    shift_amount = (1 - e_half);
                    if (shift_amount > 24+13) begin
                        // Demasiado pequeño -> cero
                        hp_exp = 5'b0;
                        hp_mant = 10'b0;
                        fp_result = {16'b0, sign, hp_exp, hp_mant};
                    end else begin
                        // Total de bits a desplazar para obtener 10 fracciones: 13 (para 24->(1+10)) + (shift_amount)
                        // Construimos un vector extendido para recopilar sticky correctamente
                        // desplazamiento seguro con límite
                        sig_ext = {sig, 14'b0};
                        if (shift_amount < 0) shift_amount = 0;
                        shifted = sig_ext >> (13 + shift_amount);

                        hp_mant = shifted[23:14]; // 10 bits de fracción resultante
                        guard_bit = shifted[13];
                        round_bit = shifted[12];
                        sticky_bit = (shifted[11:0] != 12'b0);

                        // Redondeo tie-to-even para subnormal
                        rounded_frac = {1'b0, hp_mant};
                        if (guard_bit && (round_bit | sticky_bit | hp_mant[0])) begin
                            rounded_frac = {1'b0, hp_mant} + 11'd1;
                        end

                        // En subnormal el exponente es 0; si overflowea la fracción, se convierte en min normal
                        if (rounded_frac[10]) begin
                            // Conlleva a 1.000... -> min normal (exp=1, frac=0)
                            hp_exp = 5'd1;
                            hp_mant = 10'b0;
                        end else begin
                            hp_exp = 5'b0;
                            hp_mant = rounded_frac[9:0];
                        end

                        fp_result = {16'b0, sign, hp_exp, hp_mant};
                    end
                end
            end
        end
    end

endmodule