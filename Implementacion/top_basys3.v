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
    
    reg [2:0] state;
    
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
    
    // Parámetro para configurar el tiempo de debounce
    // Para síntesis: 999999 (10ms @ 100MHz)
    // Para simulación: 9 (muy corto para pruebas rápidas)
    parameter BTN_DEBOUNCE_CYCLES = 9;  // Cambiar a 999999 para hardware real
    
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
            
            // Debounce con contador (aprox. 10ms a 100MHz en hardware)
            if (btn_sync_1 == btn_debounced) begin
                btn_counter <= 20'd0;
            end else begin
                btn_counter <= btn_counter + 1;
                if (btn_counter == BTN_DEBOUNCE_CYCLES) begin
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
    // Máquina de estados (todo en un solo bloque síncrono)
    // ====================
    
    always @(posedge clk) begin
        if (rst) begin
            state <= S0_CONFIG;
            op_code_reg <= 3'b000;
            mode_fp_reg <= 1'b0;
            round_mode_reg <= 1'b0;
            op_a_reg <= 32'b0;
            op_b_reg <= 32'b0;
            alu_start <= 1'b0;
        end else begin            
            // Lógica de estados y captura de datos
            case (state)
                S0_CONFIG: begin
                    if (btn_edge) begin
                        // Capturar configuración
                        op_code_reg <= switches[2:0];
                        mode_fp_reg <= switches[3];
                        round_mode_reg <= switches[4];
                        // Cambiar a siguiente estado
                        state <= S1_NUM1_LOW;
                    end
                end
                
                S1_NUM1_LOW: begin
                    if (btn_edge) begin
                        // Capturar datos
                        if (mode_fp_reg) begin
                            // Single precision: guardar bits bajos
                            op_a_reg[15:0] <= switches;
                            state <= S2_NUM1_HIGH;
                        end else begin
                            // Half precision: número completo en 16 bits
                            op_a_reg <= {16'b0, switches};
                            state <= S3_NUM2_LOW;
                        end
                    end
                end
                
                S2_NUM1_HIGH: begin
                    if (btn_edge) begin
                        // Solo en single precision
                        op_a_reg[31:16] <= switches;
                        state <= S3_NUM2_LOW;
                    end
                end
                
                S3_NUM2_LOW: begin
                    if (btn_edge) begin
                        // Capturar datos
                        if (mode_fp_reg) begin
                            // Single precision: guardar bits bajos
                            op_b_reg[15:0] <= switches;
                            state <= S4_NUM2_HIGH;
                        end else begin
                            // Half precision: número completo en 16 bits
                            op_b_reg <= {16'b0, switches};
                            // Iniciar ALU para Half Precision
                            alu_start <= 1'b1;
                            state <= S5_RESULT_LOW;
                        end
                    end
                end
                
                S4_NUM2_HIGH: begin
                    if (btn_edge) begin
                        // Solo en single precision
                        op_b_reg[31:16] <= switches;
                        // Iniciar ALU para Single Precision
                        alu_start <= 1'b1;
                        state <= S5_RESULT_LOW;
                    end
                end
                
                S5_RESULT_LOW: begin
                    // NO desactivar start aquí, el ALU lo necesita para mantener valid_out
                    
                    if (btn_edge && alu_valid_out) begin
                        // Desactivar start SOLO cuando avanzamos de estado
                        alu_start <= 1'b0;
                        
                        // Solo avanzar si el resultado está listo
                        if (mode_fp_reg)
                            state <= S6_RESULT_HIGH;
                        else
                            state <= S7_FLAGS;
                    end
                end
                
                S6_RESULT_HIGH: begin
                    if (btn_edge) begin
                        state <= S7_FLAGS;
                    end
                end
                
                S7_FLAGS: begin
                    if (btn_edge) begin
                        state <= S0_CONFIG; // Volver al inicio
                    end
                end
                
                default: state <= S0_CONFIG;
            endcase
        end
    end
    
    // Lógica de salida a LEDs
    always @(*) begin
        case (state)
            S0_CONFIG: begin
                // Mostrar estado y configuración
                // LEDs[15:13] = estado (000)
                // LEDs[4:0] = configuración
                leds = {3'b000, 8'b0, round_mode_reg, mode_fp_reg, op_code_reg};
            end
            
            S1_NUM1_LOW: begin
                leds = switches;
            end
            
            S2_NUM1_HIGH: begin
                leds = switches;
            end
            
            S3_NUM2_LOW: begin
                leds = switches;
            end
            
            S4_NUM2_HIGH: begin
                leds = switches;
            end
            
            S5_RESULT_LOW: begin
                if (alu_valid_out)
                    leds = alu_result[15:0];
                else
                    leds = {3'b101, 13'b0}; 
            end
            
            S6_RESULT_HIGH: begin
                leds = alu_result[31:16];
            end
            
            S7_FLAGS: begin
                leds = {11'b0, alu_flags};
            end
            
            default: leds = 16'h0000;
        endcase
    end

endmodule