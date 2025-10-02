// Módulo para división de números en punto flotante IEEE-754
module fp_divider(
    input clk,
    input rst,
    input start,
    input mode_fp,              // 0=half precision, 1=single precision
    input sign_a,               // Signo del dividendo
    input sign_b,               // Signo del divisor
    input [7:0] exp_a,          // Exponente del dividendo
    input [7:0] exp_b,          // Exponente del divisor
    input [22:0] mant_a,        // Mantisa del dividendo
    input [22:0] mant_b,        // Mantisa del divisor
    input [1:0] round_mode,     // 00=nearest even, 01=toward zero, 10=up, 11=down
    output reg result_sign,
    output reg [7:0] result_exp,
    output reg [22:0] result_mant,
    output reg overflow,
    output reg underflow,
    output reg inexact,
    output reg ready
);

    // Señales internas
    reg [23:0] dividend, divisor;       // Mantisas con bit implícito
    reg [47:0] quotient;               // Cociente extendido
    reg [8:0] exp_diff;                // Diferencia de exponentes
    reg [8:0] biased_exp;              // Exponente ajustado
    
    // Estados de la máquina de división
    reg [2:0] div_state;
    localparam DIV_IDLE = 3'b000;
    localparam DIV_SETUP = 3'b001;
    localparam DIV_COMPUTE = 3'b010;
    localparam DIV_NORMALIZE = 3'b011;
    localparam DIV_DONE = 3'b100;
    
    // Contador para división iterativa
    reg [4:0] div_counter;
    reg [47:0] remainder;
    
    // Variables para normalización
    integer i;
    reg [5:0] shift_amount;
    
    // Parámetros
    localparam SP_EXP_BIAS = 127;
    localparam HP_EXP_BIAS = 15;
    localparam SP_EXP_MAX = 8'hFF;
    localparam HP_EXP_MAX = 5'h1F;
    
    // Función para contar leading zeros en quotient[45:0]
    function [5:0] count_quotient_leading_zeros;
        input [47:0] value;
        integer j;
        begin
            count_quotient_leading_zeros = 46;
            for (j = 45; j >= 0; j = j - 1) begin
                if (value[j]) begin
                    count_quotient_leading_zeros = 45 - j;
                    j = -1; // Salir del bucle
                end
            end
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            div_state <= DIV_IDLE;
            result_sign <= 1'b0;
            result_exp <= 8'b0;
            result_mant <= 23'b0;
            overflow <= 1'b0;
            underflow <= 1'b0;
            inexact <= 1'b0;
            ready <= 1'b1;
            div_counter <= 5'b0;
            quotient <= 48'b0;
            remainder <= 48'b0;
        end else begin
            case (div_state)
                DIV_IDLE: begin
                    ready <= 1'b1;
                    if (start) begin
                        ready <= 1'b0;
                        div_state <= DIV_SETUP;
                        
                        // Calcular signo del resultado
                        result_sign <= sign_a ^ sign_b;
                        
                        // Preparar mantisas con bit implícito
                        dividend <= {1'b1, mant_a};
                        divisor <= {1'b1, mant_b};
                        
                        // Calcular diferencia de exponentes
                        exp_diff <= exp_a - exp_b + SP_EXP_BIAS;
                        
                        // Inicializar división
                        quotient <= 48'b0;
                        remainder <= {1'b1, mant_a, 23'b0}; // Dividend extendido
                        div_counter <= 5'd24; // 24 bits de precisión
                    end
                end
                
                DIV_SETUP: begin
                    div_state <= DIV_COMPUTE;
                end
                
                DIV_COMPUTE: begin
                    // División SRT (Sweeney, Robertson, Tocher) simplificada
                    if (div_counter > 0) begin
                        remainder <= remainder << 1;
                        quotient <= quotient << 1;
                        
                        if (remainder[47:24] >= divisor) begin
                            remainder[47:24] <= remainder[47:24] - divisor;
                            quotient[0] <= 1'b1;
                        end
                        
                        div_counter <= div_counter - 1;
                    end else begin
                        div_state <= DIV_NORMALIZE;
                    end
                end
                
                DIV_NORMALIZE: begin
                    // Normalizar el resultado
                    if (quotient[47]) begin
                        // El cociente es >= 2.0, necesita shift a la derecha
                        result_mant <= quotient[46:24];
                        biased_exp <= exp_diff + 1;
                        inexact <= (quotient[23:0] != 24'b0) || (remainder != 48'b0);
                    end else if (quotient[46]) begin
                        // El cociente está normalizado
                        result_mant <= quotient[45:23];
                        biased_exp <= exp_diff;
                        inexact <= (quotient[22:0] != 23'b0) || (remainder != 48'b0);
                    end else begin
                        // El cociente necesita normalización a la izquierda
                        shift_amount <= count_quotient_leading_zeros(quotient);
                        
                        if (shift_amount <= biased_exp) begin
                            // Normalización manual para evitar shift dinámico
                            case (shift_amount)
                                6'd0: begin
                                    result_mant <= quotient[45:23];
                                    inexact <= (quotient[22:0] != 23'b0) || (remainder != 48'b0);
                                end
                                6'd1: begin
                                    result_mant <= quotient[44:22];
                                    inexact <= (quotient[21:0] != 22'b0) || (remainder != 48'b0);
                                end
                                6'd2: begin
                                    result_mant <= quotient[43:21];
                                    inexact <= (quotient[20:0] != 21'b0) || (remainder != 48'b0);
                                end
                                6'd3: begin
                                    result_mant <= quotient[42:20];
                                    inexact <= (quotient[19:0] != 20'b0) || (remainder != 48'b0);
                                end
                                6'd4: begin
                                    result_mant <= quotient[41:19];
                                    inexact <= (quotient[18:0] != 19'b0) || (remainder != 48'b0);
                                end
                                6'd5: begin
                                    result_mant <= quotient[40:18];
                                    inexact <= (quotient[17:0] != 18'b0) || (remainder != 48'b0);
                                end
                                default: begin
                                    result_mant <= 23'b0;
                                    inexact <= 1'b1;
                                end
                            endcase
                            biased_exp <= biased_exp - shift_amount;
                        end else begin
                            // Underflow
                            result_mant <= 23'b0;
                            biased_exp <= 9'b0;
                            underflow <= 1'b1;
                        end
                    end
                    
                    // Verificar overflow y underflow
                    if (mode_fp) begin
                        // Single precision
                        if (biased_exp >= SP_EXP_MAX) begin
                            result_exp <= SP_EXP_MAX;
                            result_mant <= 23'b0; // Infinito
                            overflow <= 1'b1;
                        end else if (biased_exp <= 0) begin
                            result_exp <= 8'b0;
                            result_mant <= 23'b0; // Cero
                            underflow <= 1'b1;
                        end else begin
                            result_exp <= biased_exp[7:0];
                        end
                    end else begin
                        // Half precision
                        if (biased_exp - SP_EXP_BIAS + HP_EXP_BIAS >= HP_EXP_MAX) begin
                            result_exp <= HP_EXP_MAX - HP_EXP_BIAS + SP_EXP_BIAS;
                            result_mant <= {13'b0, 10'b0};
                            overflow <= 1'b1;
                        end else if (biased_exp - SP_EXP_BIAS + HP_EXP_BIAS <= 0) begin
                            result_exp <= 8'b0;
                            result_mant <= 23'b0;
                            underflow <= 1'b1;
                        end else begin
                            result_exp <= biased_exp - SP_EXP_BIAS + HP_EXP_BIAS;
                        end
                    end
                    
                    div_state <= DIV_DONE;
                end
                
                DIV_DONE: begin
                    ready <= 1'b1;
                    if (!start) begin
                        div_state <= DIV_IDLE;
                        overflow <= 1'b0;
                        underflow <= 1'b0;
                        inexact <= 1'b0;
                    end
                end
                
                default: div_state <= DIV_IDLE;
            endcase
        end
    end

endmodule