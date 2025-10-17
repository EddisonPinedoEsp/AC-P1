`timescale 1ns / 1ps

module top_basys3(
    input clk,
    input rst,
    input [15:0] switches,     // 16 switches de la Basys3
    input btn_next,            // Botón para avanzar de estado
    output reg [15:0] leds     // 16 LEDs para mostrar resultados
);

    // Estados de la FSM
    localparam S0_CONFIG = 3'b000;    // Configurar modo, operación y redondeo
    localparam S1_NUM1_LOW = 3'b001;  // Ingresar bits [15:0] del número 1 (o completo si HP)
    localparam S2_NUM1_HIGH = 3'b010; // Ingresar bits [31:16] del número 1 (solo si SP)
    localparam S3_NUM2_LOW = 3'b011;  // Ingresar bits [15:0] del número 2 (o completo si HP)
    localparam S4_NUM2_HIGH = 3'b100; // Ingresar bits [31:16] del número 2 (solo si SP)
    localparam S5_RESULT_LOW = 3'b101;  // Mostrar bits [15:0] del resultado
    localparam S6_RESULT_HIGH = 3'b110; // Mostrar bits [31:16] del resultado
    localparam S7_FLAGS = 3'b111;       // Mostrar flags
    
    reg [2:0] state, next_state;
    
    // Registros para almacenar datos capturados
    reg [2:0] op_code_reg;
    reg mode_fp_reg;
    reg round_mode_reg;
    reg [31:0] op_a_reg;
    reg [31:0] op_b_reg;
    
    // Señales del ALU
    wire [31:0] alu_result;
    wire alu_valid_out;
    wire [4:0] alu_flags;
    reg alu_start;
    
    // Debounce del botón
    reg [19:0] btn_counter;
    reg btn_sync_0, btn_sync_1;
    reg btn_debounced;
    reg btn_edge;
    reg btn_prev;
    
    // Instancia del ALU
    alu alu_inst (
        .clk(clk),
        .rst(rst),
        .op_a(op_a_reg),
        .op_b(op_b_reg),
        .op_code(op_code_reg),
        .mode_fp(mode_fp_reg),
        .round_mode(round_mode_reg),
        .start(alu_start),
        .result(alu_result),
        .valid_out(alu_valid_out),
        .flags(alu_flags)
    );
    
    // ====================
    // Debounce del botón
    // ====================
    always @(posedge clk) begin
        if (rst) begin
            btn_sync_0 <= 1'b0;
            btn_sync_1 <= 1'b0;
            btn_debounced <= 1'b0;
            btn_counter <= 20'd0;
        end else begin
            // Sincronización de 2 etapas
            btn_sync_0 <= btn_next;
            btn_sync_1 <= btn_sync_0;
            
            // Debounce con contador (aprox. 10ms a 100MHz)
            if (btn_sync_1 == btn_debounced) begin
                btn_counter <= 20'd0;
            end else begin
                btn_counter <= btn_counter + 1;
                if (btn_counter == 20'd999999) begin
                    btn_debounced <= btn_sync_1;
                end
            end
        end
    end
    
    // Detector de flanco de subida del botón
    always @(posedge clk) begin
        if (rst) begin
            btn_prev <= 1'b0;
            btn_edge <= 1'b0;
        end else begin
            btn_prev <= btn_debounced;
            btn_edge <= btn_debounced && !btn_prev;
        end
    end
    
    // ====================
    // Máquina de estados
    // ====================
    
    // Registro de estado
    always @(posedge clk) begin
        if (rst) begin
            state <= S0_CONFIG;
        end else begin
            state <= next_state;
        end
    end
    
    // Lógica de transición de estados
    always @(*) begin
        next_state = state;
        
        case (state)
            S0_CONFIG: begin
                if (btn_edge) begin
                    next_state = S1_NUM1_LOW;
                end
            end
            
            S1_NUM1_LOW: begin
                if (btn_edge) begin
                    // Si es half precision (mode_fp=0), pasar a num2
                    // Si es single precision (mode_fp=1), necesitar más bits
                    if (mode_fp_reg)
                        next_state = S2_NUM1_HIGH;
                    else
                        next_state = S3_NUM2_LOW;
                end
            end
            
            S2_NUM1_HIGH: begin
                if (btn_edge) begin
                    next_state = S3_NUM2_LOW;
                end
            end
            
            S3_NUM2_LOW: begin
                if (btn_edge) begin
                    // Si es half precision, pasar directo a cálculo
                    // Si es single precision, necesitar más bits
                    if (mode_fp_reg)
                        next_state = S4_NUM2_HIGH;
                    else
                        next_state = S5_RESULT_LOW; // Iniciar cálculo
                end
            end
            
            S4_NUM2_HIGH: begin
                if (btn_edge) begin
                    next_state = S5_RESULT_LOW; // Iniciar cálculo
                end
            end
            
            S5_RESULT_LOW: begin
                if (btn_edge) begin
                    // Si es half precision, ir directo a flags
                    // Si es single precision, mostrar parte alta
                    if (mode_fp_reg)
                        next_state = S6_RESULT_HIGH;
                    else
                        next_state = S7_FLAGS;
                end
            end
            
            S6_RESULT_HIGH: begin
                if (btn_edge) begin
                    next_state = S7_FLAGS;
                end
            end
            
            S7_FLAGS: begin
                if (btn_edge) begin
                    next_state = S0_CONFIG; // Volver al inicio
                end
            end
            
            default: next_state = S0_CONFIG;
        endcase
    end
    
    // Lógica de captura de datos y control del ALU
    always @(posedge clk) begin
        if (rst) begin
            op_code_reg <= 3'b000;
            mode_fp_reg <= 1'b0;
            round_mode_reg <= 1'b0;
            op_a_reg <= 32'b0;
            op_b_reg <= 32'b0;
            alu_start <= 1'b0;
        end else begin
            // Control del start del ALU - SE MANTIENE HASTA QUE VALID_OUT ESTÉ ACTIVO
            if ((state == S4_NUM2_HIGH || state == S3_NUM2_LOW) && btn_edge) begin
                // Iniciar ALU cuando se confirma el último número
                alu_start <= 1'b1;
            end else if (alu_valid_out || state == S0_CONFIG) begin
                alu_start <= 1'b0;
            end
            
            // Captura de datos según el estado
            // IMPORTANTE: Capturar ANTES de cambiar de estado
            if (btn_edge) begin
                case (state)
                    S0_CONFIG: begin
                        // switches[2:0] = op_code
                        // switches[3] = mode_fp
                        // switches[4] = round_mode
                        op_code_reg <= switches[2:0];
                        mode_fp_reg <= switches[3];
                        round_mode_reg <= switches[4];
                    end
                    
                    S1_NUM1_LOW: begin
                        if (mode_fp_reg) begin
                            // Single precision: guardar bits bajos
                            op_a_reg[15:0] <= switches;
                        end else begin
                            // Half precision: número completo en 16 bits
                            op_a_reg <= {16'b0, switches};
                        end
                    end
                    
                    S2_NUM1_HIGH: begin
                        // Solo en single precision
                        op_a_reg[31:16] <= switches;
                    end
                    
                    S3_NUM2_LOW: begin
                        if (mode_fp_reg) begin
                            // Single precision: guardar bits bajos
                            op_b_reg[15:0] <= switches;
                        end else begin
                            // Half precision: número completo en 16 bits
                            op_b_reg <= {16'b0, switches};
                        end
                    end
                    
                    S4_NUM2_HIGH: begin
                        // Solo en single precision
                        op_b_reg[31:16] <= switches;
                    end
                endcase
            end
        end
    end
    
    // Lógica de salida a LEDs
    always @(*) begin
        case (state)
            S0_CONFIG: begin
                // Mostrar configuración actual en los LEDs
                leds = {11'b0, round_mode_reg, mode_fp_reg, op_code_reg};
            end
            
            S1_NUM1_LOW: begin
                // Mostrar lo que se está ingresando
                leds = switches;
            end
            
            S2_NUM1_HIGH: begin
                // Mostrar lo que se está ingresando
                leds = switches;
            end
            
            S3_NUM2_LOW: begin
                // Mostrar lo que se está ingresando
                leds = switches;
            end
            
            S4_NUM2_HIGH: begin
                // Mostrar lo que se está ingresando
                leds = switches;
            end
            
            S5_RESULT_LOW: begin
                // Mostrar bits bajos del resultado
                if (alu_valid_out)
                    leds = alu_result[15:0];
                else
                    leds = 16'b0000000000000001; // Indicador de "calculando" (LED 0 encendido)
            end
            
            S6_RESULT_HIGH: begin
                // Mostrar bits altos del resultado
                leds = alu_result[31:16];
            end
            
            S7_FLAGS: begin
                // Mostrar flags en los LEDs inferiores
                leds = {11'b0, alu_flags};
            end
            
            default: leds = 16'h0000;
        endcase
    end

endmodule


