`timescale 1ns / 1ps
module fp_adder_subber(
    input clk,
    input rst,
    input mode_fp,              // 0=half precision, 1=single precision
    input operation,            // 0=add, 1=sub
    input sign_a,
    input sign_b,
    input [7:0] exp_a,
    input [7:0] exp_b,
    input [22:0] mant_a,
    input [22:0] mant_b,
    input round_mode,     // nearest
    output reg result_sign,
    output reg [7:0] result_exp,
    output reg [22:0] result_mant,
    output reg overflow,
    output reg underflow,
    output reg inexact
);

    // Señales internas - usando combinacional para evitar problemas de timing
    wire effective_sub;          // Operación efectiva es resta
    wire [7:0] larger_exp, smaller_exp;
    wire [23:0] larger_mant, smaller_mant;  // 24 bits con bit implícito
    wire larger_sign, smaller_sign;
    wire exp_diff_overflow;
    wire [7:0] exp_diff;
    wire [25:0] aligned_smaller_mant;    // 26 bits para alineación y redondeo
    wire [26:0] sum_result; // 27 bits para manejar overflow
    wire [4:0] leading_zeros;
    wire [7:0] normalized_exp;
    wire [22:0] normalized_mant;
    
    // Parámetros
    localparam SP_EXP_BIAS = 127;
    localparam HP_EXP_BIAS = 15;
    localparam SP_EXP_MAX = 8'hFF;
    localparam HP_EXP_MAX = 5'h1F;

    // Determinar si la operación efectiva es resta
    assign effective_sub = sign_a ^ sign_b ^ operation;
    
    // Determinar cuál operando es mayor en magnitud
    wire a_larger = (exp_a > exp_b) || ((exp_a == exp_b) && (mant_a >= mant_b));
    
    assign larger_exp = a_larger ? exp_a : exp_b;
    assign smaller_exp = a_larger ? exp_b : exp_a;
    assign larger_mant = a_larger ? {1'b1, mant_a} : {1'b1, mant_b};
    assign smaller_mant = a_larger ? {1'b1, mant_b} : {1'b1, mant_a};
    assign larger_sign = a_larger ? sign_a : (sign_b ^ operation);
    assign smaller_sign = a_larger ? (sign_b ^ operation) : sign_a;
    
    // Calcular diferencia de exponentes
    assign {exp_diff_overflow, exp_diff} = larger_exp - smaller_exp;
    
    // Alinear mantisas
    assign aligned_smaller_mant = (exp_diff >= 26) ? 26'b0 : ({smaller_mant, 2'b0} >> exp_diff);
    
    // Realizar suma o resta
    wire [25:0] larger_extended = {larger_mant, 2'b0};
    assign sum_result = effective_sub ? 
                    (larger_extended - aligned_smaller_mant) :
                    (larger_extended + aligned_smaller_mant);

    // Función sintetizable para contar ceros a la izquierda (sin "break")
    function [4:0] count_leading_zeros;
        input [26:0] value;
        integer j;
        begin
            count_leading_zeros = 27;
            for (j = 26; j >= 0; j = j - 1) begin
                if (value[j] && count_leading_zeros == 27) begin
                    count_leading_zeros = 26 - j;
                end
            end
            if (count_leading_zeros == 27)
                count_leading_zeros = 27; // todo cero
        end
    endfunction
    
    assign leading_zeros = count_leading_zeros(sum_result);
    
    // Lógica de normalización combinacional
    // Variables temporales (deben declararse antes de cualquier sentencia en Verilog-2001)
    reg [22:0] mant_pre;
    reg guard_bit, round_bit, sticky_bit;
    reg [23:0] mant_rounded; // 1 bit extra para detectar carry
    integer deficit;
    reg [49:0] ext; // espacio para sticky
    reg [49:0] shifted;
    reg [26:0] sr;
    integer k;
    reg [26:0] shifted_local;

    always @(*) begin
        // Valores por defecto
        result_sign = larger_sign;
        overflow = 1'b0;
        underflow = 1'b0;
        inexact = 1'b0;
        result_exp = 8'b0;
        result_mant = 23'b0;
        
        if (sum_result == 27'b0) begin
            // Resultado es cero
            result_exp = 8'b0;
            result_mant = 23'b0;
            // Preservar cero con signo según operandos (no forzar +0)
            // Si las magnitudes son iguales y se restan, mantener el signo del operando "mayor" (en empate, A)
            result_sign = larger_sign;
        end else if (sum_result[26]) begin
            // Bit 26 activo - overflow, necesita shift a la derecha  
            result_exp = larger_exp + 1;
            mant_pre = sum_result[25:3];
            guard_bit = sum_result[2];
            round_bit = sum_result[1];
            sticky_bit = |sum_result[0];
            // Tie-to-even
            mant_rounded = {1'b0, mant_pre};
            if (guard_bit && (round_bit | sticky_bit | mant_pre[0])) begin
                mant_rounded = mant_rounded + 24'd1;
            end
            // Si hay carry en redondeo, incrementar exponente y ajustar mantisa
            if (mant_rounded[23]) begin
                result_exp = result_exp + 1'b1;
                result_mant = 23'b0;
            end else begin
                result_mant = mant_rounded[22:0];
            end
            inexact = guard_bit | round_bit | sticky_bit;
        end else if (sum_result[25]) begin
            // Bit 25 activo - normalizado
            result_exp = larger_exp;
            mant_pre = sum_result[24:2];
            guard_bit = sum_result[1];
            round_bit = sum_result[0];
            sticky_bit = 1'b0;
            mant_rounded = {1'b0, mant_pre};
            if (guard_bit && (round_bit | sticky_bit | mant_pre[0])) begin
                mant_rounded = mant_rounded + 24'd1;
            end
            if (mant_rounded[23]) begin
                result_exp = result_exp + 1'b1;
                result_mant = 23'b0;
            end else begin
                result_mant = mant_rounded[22:0];
            end
            inexact = guard_bit | round_bit | sticky_bit;
        end else if (sum_result[24]) begin
            // Bit 24 activo - necesita shift left de 1
            result_exp = larger_exp - 1;
            mant_pre = sum_result[23:1];
            guard_bit = sum_result[0];
            round_bit = 1'b0;
            sticky_bit = 1'b0;
            mant_rounded = {1'b0, mant_pre};
            if (guard_bit && (round_bit | sticky_bit | mant_pre[0])) begin
                mant_rounded = mant_rounded + 24'd1;
            end
            if (mant_rounded[23]) begin
                result_exp = result_exp + 1'b1;
                result_mant = 23'b0;
            end else begin
                result_mant = mant_rounded[22:0];
            end
            inexact = guard_bit | round_bit | sticky_bit;
        end else begin
            // Necesita normalización a la izquierda
            if (leading_zeros > larger_exp) begin
                // Underflow
                // Generar subnormal en single/half: aquí sólo marcamos underflow y dejamos encoder/otros módulos manejar half.
                // Convertimos a subnormal para single: desplazar la mantisa según déficit de exponente y aplicar GRS
                // Nota: Para simplificar, si el desplazamiento requerido excede el rango, resultado es cero
                underflow = 1'b1;
                result_exp = 8'b0;
                deficit = leading_zeros - larger_exp; // cuántos pasos de izquierda no se pueden reflejar en exp
                // Construimos el valor (sum_result) como significando a desplazar a la derecha para crear subnormal
                ext = {sum_result, 23'b0};
                if (deficit >= 50) begin
                    result_mant = 23'b0;
                    inexact = 1'b1;
                end else begin
                    // Para obtener 23 bits finales, desplazamos a la derecha deficit+? y definimos GRS
                    shifted = ext >> (deficit + 4); // +4 para dejar GRS suficientes
                    mant_pre = shifted[49:27];
                    guard_bit = shifted[26];
                    round_bit = shifted[25];
                    sticky_bit = |shifted[24:0];
                    mant_rounded = {1'b0, mant_pre};
                    if (guard_bit && (round_bit | sticky_bit | mant_pre[0])) begin
                        mant_rounded = mant_rounded + 24'd1;
                    end
                    result_mant = mant_rounded[22:0];
                    inexact = guard_bit | round_bit | sticky_bit;
                end
            end else begin
                result_exp = larger_exp - leading_zeros;
                // Seleccionar ventana para 23 bits y GRS basados en leading_zeros
                // Tomamos la ventana [24 - leading_zeros : 2 - leading_zeros] como mant_pre
                // y definimos GRS con los bits inferiores
                // Calcular índices de forma segura
                sr = sum_result;
                // Construcción explícita de mant_pre y GRS
                case (leading_zeros)
                    5'd0: begin
                        mant_pre = sr[24:2];
                        guard_bit = sr[1];
                        round_bit = sr[0];
                        sticky_bit = 1'b0;
                    end
                    5'd1: begin
                        mant_pre = sr[23:1];
                        guard_bit = sr[0];
                        round_bit = 1'b0;
                        sticky_bit = 1'b0;
                    end
                    default: begin
                        // Para shifts mayores, completamos con ceros y acumulamos sticky con lo que queda
                        shifted_local = sr << leading_zeros;
                        mant_pre = shifted_local[24:2];
                        guard_bit = shifted_local[1];
                        round_bit = shifted_local[0];
                        sticky_bit = 1'b0; // ya están alineados sin pérdida adicional
                    end
                endcase
                mant_rounded = {1'b0, mant_pre};
                if (guard_bit && (round_bit | sticky_bit | mant_pre[0])) begin
                    mant_rounded = mant_rounded + 24'd1;
                end
                if (mant_rounded[23]) begin
                    result_exp = result_exp + 1'b1;
                    result_mant = 23'b0;
                end else begin
                    result_mant = mant_rounded[22:0];
                end
                inexact = guard_bit | round_bit | sticky_bit;
            end
        end
        
        // Verificar overflow después de normalización
        if (mode_fp && result_exp >= SP_EXP_MAX) begin
            result_exp = SP_EXP_MAX;
            result_mant = 23'b0;
            overflow = 1'b1;
        end else if (!mode_fp && result_exp >= (HP_EXP_MAX - HP_EXP_BIAS + SP_EXP_BIAS)) begin
            result_exp = HP_EXP_MAX - HP_EXP_BIAS + SP_EXP_BIAS;
            result_mant = 23'b0;
            overflow = 1'b1;
        end
    end

endmodule