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
    input round_mode,
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

    // Función para contar ceros a la izquierda  
    function [4:0] count_leading_zeros;
        input [26:0] value;
        integer j;
        reg found;
        begin
            count_leading_zeros = 27;
            found = 0;
            for (j = 26; j >= 0; j = j - 1) begin
                if (value[j] && !found) begin
                    count_leading_zeros = 26 - j;
                    found = 1;
                end
            end
        end
    endfunction
    
    assign leading_zeros = count_leading_zeros(sum_result);
    
    // Lógica de normalización combinacional
    always @(*) begin
        // Valores por defecto
        result_sign = larger_sign;
        overflow = 1'b0;
        underflow = 1'b0;
        inexact = 1'b0;
        
        if (sum_result == 27'b0) begin
            // Resultado es cero
            result_exp = 8'b0;
            result_mant = 23'b0;
            result_sign = 1'b0; // +0
        end else if (sum_result[26]) begin
            // Bit 26 activo - overflow, necesita shift a la derecha  
            result_exp = larger_exp + 1;
            result_mant = sum_result[25:3]; // Tomar bits 25:3 para mantisa
            inexact = (sum_result[2:0] != 3'b0);
        end else if (sum_result[25]) begin
            // Bit 25 activo - normalizado
            result_exp = larger_exp;
            result_mant = sum_result[24:2];
            inexact = (sum_result[1:0] != 2'b0);
        end else if (sum_result[24]) begin
            // Bit 24 activo - necesita shift left de 1
            result_exp = larger_exp - 1;
            result_mant = sum_result[23:1];
            inexact = sum_result[0];
        end else begin
            // Necesita normalización a la izquierda
            if (leading_zeros > larger_exp) begin
                // Underflow
                result_exp = 8'b0;
                result_mant = 23'b0;
                underflow = 1'b1;
            end else begin
                result_exp = larger_exp - leading_zeros;
                // Normalización manual
                case (leading_zeros)
                    5'd1: result_mant = sum_result[23:1];
                    5'd2: result_mant = sum_result[22:0];
                    5'd3: result_mant = {sum_result[21:0], 1'b0};
                    5'd4: result_mant = {sum_result[20:0], 2'b0};
                    5'd5: result_mant = {sum_result[19:0], 3'b0};
                    5'd6: result_mant = {sum_result[18:0], 4'b0};
                    5'd7: result_mant = {sum_result[17:0], 5'b0};
                    5'd8: result_mant = {sum_result[16:0], 6'b0};
                    5'd9: result_mant = {sum_result[15:0], 7'b0};
                    5'd10: result_mant = {sum_result[14:0], 8'b0};
                    5'd11: result_mant = {sum_result[13:0], 9'b0};
                    default: result_mant = 23'b0;
                endcase
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