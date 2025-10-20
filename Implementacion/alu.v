`timescale 1ns / 1ps
module alu(
    input clk,
    input rst,
    input [31:0] op_a,        // Operando A (IEEE-754, single o half)
    input [31:0] op_b,        // Operando B (IEEE-754, single o half)
    input [2:0] op_code,      // Código de operación: 000=ADD, 001=SUB, 010=MUL, 011=DIV
    input mode_fp,            // 0=half precision (16 bits), 1=single precision (32 bits)
    input round_mode,         // Modo de redondeo: nearest
    input start,              // Inicia la operación
    output reg [31:0] result, // Resultado en formato IEEE-754
    output reg valid_out,     // Indica que el resultado está listo
    output reg [4:0] flags    // [4:0] = {invalid, divide_by_zero, overflow, underflow, inexact}
);

    // Parámetros para operaciones
    localparam OP_ADD = 3'b000;  // suma
    localparam OP_SUB = 3'b001;  // resta
    localparam OP_MUL = 3'b010;  // multiplicación
    localparam OP_DIV = 3'b011;  // división

    // Parámetros para IEEE-754
    // Single precision (32 bits): 1 bit signo + 8 bits exponente + 23 bits mantisa
    localparam SP_SIGN_POS = 31;
    localparam SP_EXP_MSB = 30;
    localparam SP_EXP_LSB = 23;
    localparam SP_MANT_MSB = 22;
    localparam SP_MANT_LSB = 0;
    localparam SP_EXP_BIAS = 127;
    localparam SP_EXP_WIDTH = 8;
    localparam SP_MANT_WIDTH = 23;
    
    // Half precision (16 bits): 1 bit signo + 5 bits exponente + 10 bits mantisa
    localparam HP_SIGN_POS = 15;
    localparam HP_EXP_MSB = 14;
    localparam HP_EXP_LSB = 10;
    localparam HP_MANT_MSB = 9;
    localparam HP_MANT_LSB = 0;
    localparam HP_EXP_BIAS = 15;
    localparam HP_EXP_WIDTH = 5;
    localparam HP_MANT_WIDTH = 10;

    // Señales internas para decodificación IEEE-754
    wire sign_a, sign_b, result_sign;
    wire [7:0] exp_a, exp_b;
    wire [22:0] mant_a, mant_b;
    wire [7:0] result_exp;
    wire [22:0] result_mant;
    
    // Señal intermedia para el codificador
    wire [31:0] encoded_result;
    
    // Flags de casos especiales
    wire is_nan_a, is_nan_b, is_inf_a, is_inf_b, is_zero_a, is_zero_b;
    wire is_denorm_a, is_denorm_b;
    
    // Estados de la máquina de estados
    reg [2:0] state;
    localparam IDLE = 3'b000;
    localparam DECODE = 3'b001;
    localparam COMPUTE = 3'b010;
    localparam NORMALIZE = 3'b011;
    localparam ENCODE = 3'b100;
    localparam DONE = 3'b101;
    
    // Registros internos para cálculos
    reg [31:0] temp_a, temp_b;
    reg [2:0] current_op;
    reg current_mode;
    reg current_round_mode;
    
    // Contador para sincronización del multiplicador (2 ciclos de latencia)
    reg [1:0] mul_counter;
    
    // Decodificador IEEE-754
    ieee754_decoder decoder_inst (
        .mode_fp(current_mode),
        .fp_a(temp_a),
        .fp_b(temp_b),
        .sign_a(sign_a),
        .sign_b(sign_b),
        .exp_a(exp_a),
        .exp_b(exp_b),
        .mant_a(mant_a),
        .mant_b(mant_b),
        .is_nan_a(is_nan_a),
        .is_nan_b(is_nan_b),
        .is_inf_a(is_inf_a),
        .is_inf_b(is_inf_b),
        .is_zero_a(is_zero_a),
        .is_zero_b(is_zero_b),
        .is_denorm_a(is_denorm_a),
        .is_denorm_b(is_denorm_b)
    );
    
    // SUM SUB
    wire add_overflow, add_underflow, add_inexact;
    wire add_result_sign;
    wire [7:0] add_result_exp;
    wire [22:0] add_result_mant;
    
    fp_adder_subber adder_sub_inst (
        .clk(clk),
        .rst(rst),
        .mode_fp(current_mode),
        .operation(current_op[0]), // 0=add, 1=sub
        .sign_a(sign_a),
        .sign_b(sign_b),
        .exp_a(exp_a),
        .exp_b(exp_b),
        .mant_a(mant_a),
        .mant_b(mant_b),
        .round_mode(current_round_mode),
        .result_sign(add_result_sign),
        .result_exp(add_result_exp),
        .result_mant(add_result_mant),
        .overflow(add_overflow),
        .underflow(add_underflow),
        .inexact(add_inexact)
    );
    
    // MUL
    wire mul_overflow, mul_underflow, mul_inexact;
    wire mul_result_sign;
    wire [7:0] mul_result_exp;
    wire [22:0] mul_result_mant;
    
    fp_multiplier multiplier_inst (
        .clk(clk),
        .rst(rst),
        .mode_fp(current_mode),
        .sign_a(sign_a),
        .sign_b(sign_b),
        .exp_a(exp_a),
        .exp_b(exp_b),
        .mant_a(mant_a),
        .mant_b(mant_b),
        .round_mode(current_round_mode),
        .result_sign(mul_result_sign),
        .result_exp(mul_result_exp),
        .result_mant(mul_result_mant),
        .overflow(mul_overflow),
        .underflow(mul_underflow),
        .inexact(mul_inexact)
    );
    
    // DIV
    wire div_overflow, div_underflow, div_inexact, div_ready;
    wire div_result_sign;
    wire [7:0] div_result_exp;
    wire [22:0] div_result_mant;
    
    fp_divider divider_inst (
        .clk(clk),
        .rst(rst),
        .start((state == COMPUTE) && (current_op == OP_DIV)),
        .mode_fp(current_mode),
        .sign_a(sign_a),
        .sign_b(sign_b),
        .exp_a(exp_a),
        .exp_b(exp_b),
        .mant_a(mant_a),
        .mant_b(mant_b),
        .round_mode(current_round_mode),
        .result_sign(div_result_sign),
        .result_exp(div_result_exp),
        .result_mant(div_result_mant),
        .overflow(div_overflow),
        .underflow(div_underflow),
        .inexact(div_inexact),
        .ready(div_ready)
    );
    
    // Mux: Seleccionar el resultado según la operación
    reg final_result_sign;
    reg [7:0] final_result_exp;
    reg [22:0] final_result_mant;
    reg final_overflow, final_underflow, final_inexact;
    
    always @(*) begin
        case (current_op)
            OP_ADD, OP_SUB: begin
                final_result_sign = add_result_sign;
                final_result_exp = add_result_exp;
                final_result_mant = add_result_mant;
                final_overflow = add_overflow;
                final_underflow = add_underflow;
                final_inexact = add_inexact;
            end
            OP_MUL: begin
                final_result_sign = mul_result_sign;
                final_result_exp = mul_result_exp;
                final_result_mant = mul_result_mant;
                final_overflow = mul_overflow;
                final_underflow = mul_underflow;
                final_inexact = mul_inexact;
            end
            OP_DIV: begin
                final_result_sign = div_result_sign;
                final_result_exp = div_result_exp;
                final_result_mant = div_result_mant;
                final_overflow = div_overflow;
                final_underflow = div_underflow;
                final_inexact = div_inexact;
            end
            default: begin
                final_result_sign = 1'b0;
                final_result_exp = 8'b0;
                final_result_mant = 23'b0;
                final_overflow = 1'b0;
                final_underflow = 1'b0;
                final_inexact = 1'b0;
            end
        endcase
    end
    
    // Codificador IEEE-754
    ieee754_encoder encoder_inst (
        .mode_fp(current_mode),
        .sign(final_result_sign),
        .exp(final_result_exp),
        .mant(final_result_mant),
        .fp_result(encoded_result)
    );

    // Máquina de estados principal
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            result <= 32'b0;
            valid_out <= 1'b0;
            flags <= 5'b0;
            mul_counter <= 2'b0;
        end else begin
            case (state)
                IDLE: begin
                    valid_out <= 1'b0;
                    if (start) begin
                        temp_a <= op_a;
                        temp_b <= op_b;
                        current_op <= op_code;
                        current_mode <= mode_fp;
                        current_round_mode <= round_mode;
                        state <= DECODE;
                    end
                end
                
                DECODE: begin
                    state <= COMPUTE;
                end
                
                COMPUTE: begin
                    // Manejo de casos especiales
                    if (is_nan_a || is_nan_b) begin
                        // Cualquier operación con NaN resulta en NaN
                        if (current_mode) // Single precision
                            result <= 32'h7FC00000; // Quiet NaN
                        else // Half precision
                            result <= {16'h0, 16'h7E00}; // Quiet NaN en los 16 bits menos significativos
                        flags[4] <= 1'b1; // invalid operation
                        state <= DONE;
                    end else if (is_inf_a || is_inf_b) begin
                        // Manejo de infinitos
                        case (current_op)
                            OP_ADD, OP_SUB: begin
                                if (is_inf_a && is_inf_b && (sign_a ^ sign_b ^ current_op[0])) begin
                                    // Inf - Inf o -Inf + Inf = NaN
                                    if (current_mode)
                                        result <= 32'h7FC00000;
                                    else
                                        result <= {16'h0, 16'h7E00};
                                    flags[4] <= 1'b1; // invalid operation
                                end else begin
                                    // Resultado es infinito
                                    if (current_mode)
                                        result <= is_inf_a ? temp_a : temp_b;
                                    else
                                        result <= is_inf_a ? temp_a : temp_b;
                                end
                            end
                            OP_MUL: begin
                                if (is_zero_a || is_zero_b) begin
                                    // 0 * Inf = NaN
                                    if (current_mode)
                                        result <= 32'h7FC00000;
                                    else
                                        result <= {16'h0, 16'h7E00};
                                    flags[4] <= 1'b1; // invalid operation
                                end else begin
                                    // Inf * número = Inf con signo apropiado
                                    if (current_mode)
                                        result <= {sign_a ^ sign_b, 8'hFF, 23'b0};
                                    else
                                        result <= {16'b0, sign_a ^ sign_b, 5'h1F, 10'b0};
                                end
                            end
                            OP_DIV: begin
                                if (is_inf_a && is_inf_b) begin
                                    // Inf / Inf = NaN
                                    if (current_mode)
                                        result <= 32'h7FC00000;
                                    else
                                        result <= {16'h0, 16'h7E00};
                                    flags[4] <= 1'b1; // invalid operation
                                end else if (is_inf_a) begin
                                    // Inf / número = Inf
                                    if (current_mode)
                                        result <= {sign_a ^ sign_b, 8'hFF, 23'b0};
                                    else
                                        result <= {16'b0, sign_a ^ sign_b, 5'h1F, 10'b0};
                                end else begin
                                    // número / Inf = 0
                                    if (current_mode)
                                        result <= {sign_a ^ sign_b, 31'b0};
                                    else
                                        result <= {16'b0, sign_a ^ sign_b, 15'b0};
                                end
                            end
                        endcase
                        state <= DONE;
                    end else if (is_zero_b && current_op == OP_DIV) begin
                        // División por cero
                        if (is_zero_a) begin
                            // 0/0 = NaN
                            if (current_mode)
                                result <= 32'h7FC00000;
                            else
                                result <= {16'h0, 16'h7E00};
                            flags[4] <= 1'b1; // invalid operation
                        end else begin
                            // número/0 = Inf
                            if (current_mode)
                                result <= {sign_a ^ sign_b, 8'hFF, 23'b0};
                            else
                                result <= {16'b0, sign_a ^ sign_b, 5'h1F, 10'b0};
                            flags[3] <= 1'b1; // divide by zero
                        end
                        state <= DONE;
                        
                    end else if ((is_zero_a || is_zero_b) && current_op == OP_MUL) begin
                        // Multiplicación por cero (número * 0 = 0)
                        if (current_mode)
                            result <= {sign_a ^ sign_b, 31'b0}; // +/- 0 en SP
                        else
                            result <= {16'b0, sign_a ^ sign_b, 15'b0}; // +/- 0 en HP
                        flags <= 5'b0; // Ningún flag
                        state <= DONE;

                    end else begin
                        // Operaciones normales
                        if (current_op == OP_MUL) begin
                            // Para multiplicación, inicializar contador (2 ciclos de latencia)
                            mul_counter <= 2'd2;
                        end
                        state <= NORMALIZE;
                    end
                end

                NORMALIZE: begin
                    // Verificar si hay overflow y generar infinito
                    if (final_overflow) begin
                        // Overflow: generar infinito con signo correcto
                        if (current_mode) // Single precision
                            result <= {final_result_sign, 8'hFF, 23'b0}; // +/-Inf
                        else // Half precision
                            result <= {16'b0, final_result_sign, 5'h1F, 10'b0}; // +/-Inf en HP
                        flags[4] <= 1'b0; // invalid operation
                        flags[3] <= 1'b0; // divide by zero
                        flags[2] <= 1'b1; // overflow
                        flags[1] <= 1'b0; // underflow
                        flags[0] <= final_inexact; // inexact
                        state <= DONE;
                    end else if (final_underflow) begin
                        // Underflow: generar cero con signo correcto
                        if (current_mode)
                            result <= {final_result_sign, 31'b0}; // +/-0 en SP
                        else
                            result <= {16'b0, final_result_sign, 15'b0}; // +/-0 en HP
                        flags[4] <= 1'b0; // invalid operation
                        flags[3] <= 1'b0; // divide by zero
                        flags[2] <= 1'b0; // overflow
                        flags[1] <= 1'b1; // underflow
                        flags[0] <= final_inexact; // inexact
                        state <= DONE;
                    end else begin
                        // Caso normal: usar el codificador
                        // Asignar flags según la operación
                        flags[4] <= 1'b0; // invalid operation (manejado en casos especiales)
                        flags[3] <= 1'b0; // divide by zero (manejado en casos especiales)
                        flags[2] <= final_overflow;   // overflow
                        flags[1] <= final_underflow;  // underflow
                        flags[0] <= final_inexact;    // inexact
                        
                        // Esperar según el tipo de operación
                        if (current_op == OP_DIV) begin
                            // Para división, esperar a que termine
                            if (div_ready) begin
                                state <= ENCODE;
                            end
                        end else if (current_op == OP_MUL) begin
                            // Para multiplicación, esperar 2 ciclos
                            if (mul_counter == 0) begin
                                state <= ENCODE;
                            end else begin
                                mul_counter <= mul_counter - 1;
                            end
                        end else begin
                            // ADD/SUB son combinacionales
                            state <= ENCODE;
                        end
                    end
                end
                
                ENCODE: begin
                    result <= encoded_result;
                    state <= DONE;
                end
                
                DONE: begin
                    valid_out <= 1'b1;
                    if (!start) begin
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule