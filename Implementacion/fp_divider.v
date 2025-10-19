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
    input round_mode,
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
    localparam DIV_ROUND = 3'b100;
    localparam DIV_DONE = 3'b101;
    
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
                        
                        // Calcular diferencia de exponentes correctamente
                        exp_diff <= exp_a - exp_b + SP_EXP_BIAS;
                        
                        // Inicializar división - poner dividendo en la posición correcta
                        quotient <= 48'b0;
                        remainder <= {{1'b1, mant_a}, 24'b0}; // Dividendo en bits superiores para división
                        div_counter <= 5'd24; // 24 bits de precisión
                    end
                end
                
                DIV_SETUP: begin
                    div_state <= DIV_COMPUTE;
                end
                
                DIV_COMPUTE: begin
                    // División restoring simple
                    if (div_counter > 0) begin
                        // Comparar y substraer si es posible
                        if (remainder[47:24] >= divisor) begin
                            remainder <= (remainder - {divisor, 24'b0}) << 1;
                            quotient <= (quotient << 1) | 1'b1;
                        end else begin
                            remainder <= remainder << 1;
                            quotient <= quotient << 1;
                        end
                        
                        div_counter <= div_counter - 1;
                    end else begin
                        div_state <= DIV_NORMALIZE;
                    end
                end
                
                DIV_NORMALIZE: begin
                    // Normalizar el resultado - el resultado está en quotient[23:0]
                    if (quotient[23]) begin
                        // El cociente está normalizado (1.xxx)
                        result_mant <= quotient[22:0];
                        biased_exp <= exp_diff;
                        inexact <= (remainder != 48'b0);
                    end else if (quotient[22]) begin
                        // El cociente necesita shift left de 1
                        result_mant <= {quotient[21:0], 1'b0};
                        biased_exp <= exp_diff - 1;
                        inexact <= (remainder != 48'b0);
                    end else if (quotient[21]) begin
                        // El cociente necesita shift left de 2
                        result_mant <= {quotient[20:0], 2'b0};
                        biased_exp <= exp_diff - 2;
                        inexact <= (remainder != 48'b0);
                    end else begin
                        // Resultado muy pequeño - underflow
                        result_mant <= 23'b0;
                        biased_exp <= 9'b0;
                        underflow <= 1'b1;
                    end
                    
                    div_state <= DIV_ROUND;
                end
                
                DIV_ROUND: begin
                    if (mode_fp) begin
                        // Single precision
                        if (biased_exp <= 0) begin
                            // Underflow
                            result_exp <= 8'b0;
                            underflow <= 1'b1;
                        end else if (biased_exp >= SP_EXP_MAX) begin
                            // Overflow
                            result_exp <= SP_EXP_MAX;
                            overflow <= 1'b1;
                        end else begin
                            // Caso normal
                            result_exp <= biased_exp[7:0];
                        end
                    end else begin
                        // Half precision - convertir bias y rango
                        if ((biased_exp - SP_EXP_BIAS + HP_EXP_BIAS) <= 0) begin
                            // Underflow en half precision
                            result_exp <= 8'b0;
                            underflow <= 1'b1;
                        end else if ((biased_exp - SP_EXP_BIAS + HP_EXP_BIAS) >= HP_EXP_MAX) begin
                            // Overflow en half precision
                            result_exp <= 8'hFF; // Marcar como infinito en formato interno
                            overflow <= 1'b1;
                        end else begin
                            // Convertir de vuelta a formato interno (single precision bias)
                            result_exp <= (biased_exp - SP_EXP_BIAS + HP_EXP_BIAS) - HP_EXP_BIAS + SP_EXP_BIAS;
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