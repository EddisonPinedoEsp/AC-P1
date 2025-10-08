`timescale 1ns/1ps

module alu_testbench;

    localparam CLK_PERIOD = 10; // 100 MHz
    
    // Señales del testbench
    reg clk;
    reg rst;
    reg [31:0] op_a, op_b;
    reg [2:0] op_code;
    reg mode_fp;
    reg round_mode;
    reg start;
    wire [31:0] result;
    wire valid_out;
    wire [4:0] flags;
    
    alu dut (
        .clk(clk),
        .rst(rst),
        .op_a(op_a),
        .op_b(op_b),
        .op_code(op_code),
        .mode_fp(mode_fp),
        .round_mode(round_mode),
        .start(start),
        .result(result),
        .valid_out(valid_out),
        .flags(flags)
    );
    
    // Generación de reloj
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Valores de prueba IEEE-754
    // Single precision
    // Pos
    localparam SP_POS_0       = 32'h00000000; // +0.0
    localparam SP_POS_0_5   = 32'h3F000000; // +0.5
    localparam SP_POS_1       = 32'h3F800000; // +1.0
    localparam SP_POS_1_2       = 32'h3F99999A; // +1.2
    localparam SP_POS_1_3       = 32'h3FA66666; // +1.3
    localparam SP_POS_1_5  = 32'h3FC00000; // +1.5
    localparam SP_POS_2    = 32'h40000000; // +2.0
    localparam SP_POS_3   = 32'h40400000; // +3.0
    localparam SP_POS_5    = 32'h40A00000; // +5.0
    localparam SP_POS_30   = 32'h41F00000; // +30
    localparam SP_POS_35   = 32'h420C0000; // +35
    localparam SP_POS_99_99 = 32'h42C7FAE1; // +99.99
    localparam SP_POS_INF    = 32'h7F800000; // +Inf
    localparam SP_POS_MIN_DENORM = 32'h00000001; // +Denorm
    localparam SP_POS_MIN = 32'h007FFFFD; // +Min
    localparam SP_POS_MAX_DENORM = 32'h007FFFFF; // +Denorm
    localparam SP_POS_MAX = 32'h7F7FFFFF; // Máximo valor representable en single precision

    // Neg
    localparam SP_NEG_0       = 32'h80000000; // -0.0
    localparam SP_NEG_1    = 32'hBF800000; // -1.0
    localparam SP_NEG_1_3  = 32'hBFA66666; // -1.3
    localparam SP_NEG_2    = 32'hC0000000; // -2.0
    localparam SP_NEG_3  = 32'hC0400000; // -3.0
    localparam SP_NEG_INF    = 32'hFF800000; // -Inf
    localparam SP_NEG_MIN_DENORM = 32'h80000001; // -Denorm
    localparam SP_NEG_MAX_DENORM = 32'h807FFFFF; // -Denorm


//  Half precision

localparam HP_POS_1       = 16'h3C00; // +1.0
localparam HP_POS_2       = 16'h4000; // +2.0
localparam HP_POS_2_5     = 16'h4100; // +2.5
localparam HP_POS_3       = 16'h4200; // +3.0
localparam HP_POS_4       = 16'h4400; // +4.0
localparam HP_POS_5       = 16'h4500; // +5.0
localparam HP_POS_INF    = 16'h7C00; // +Inf

// Neg
localparam HP_NEG_1       = 16'hBC00; // -1.0
localparam HP_NEG_2       = 16'hC000; // -2.0
localparam HP_NEG_3       = 16'hC200; // -3.0
localparam HP_NEG_4       = 16'hC400; // -4.0
localparam HP_NEG_5       = 16'hC500; // -5.0
localparam HP_NEG_INF     = 16'hFC00; // -Inf

// 
    // Tareas auxiliares
    task reset_system;
        begin
            rst = 1;
            start = 0;
            op_a = 32'b0;
            op_b = 32'b0;
            op_code = 3'b0;
            mode_fp = 1'b0;
            round_mode = 1'b0;
            #(CLK_PERIOD * 2);
            rst = 0;
            #(CLK_PERIOD);
        end
    endtask
    
    task wait_for_result;
        begin
            wait(valid_out);
            #(CLK_PERIOD);
            start = 0;
            wait(!valid_out);
            #(CLK_PERIOD);
        end
    endtask
    
    task test_operation;
        input [31:0] a, b;
        input [2:0] op;
        input mode;
        begin
            $display("A: %h, B: %h, OP: %d, Mode: %s", a, b, op, mode ? "SP" : "HP");
            
            op_a = a;
            op_b = b;
            op_code = op;
            mode_fp = mode;
            start = 1;
            #(CLK_PERIOD);
            
            wait_for_result();
            
            $display("Result: %h", result);
            $display("Flags: invalid=%b, div_by_zero=%b, overflow=%b, underflow=%b, inexact=%b", 
                    flags[4], flags[3], flags[2], flags[1], flags[0]);
        end
    endtask
    
    // Proceso principal de test
    initial begin
        $display("=== Iniciando testbench de ALU IEEE-754 ===");
        
        // Inicializar sistema
        reset_system();
        
        $display("\n=== PRUEBAS EN SINGLE PRECISION (32 bits) ===");

        // Single Precision = 1'b1
        // Half Precision = 1'b0
        
        // Suma
        // $display("=== Pruebas de suma en half precision ===");
        test_operation(HP_POS_2, HP_POS_1, 3'b000, 1'b0); // 2.0 + 1.0 = 3.0
        test_operation(HP_POS_1, HP_POS_1, 3'b001, 1'b0); // 1.0 + 1.0 = 2.0
        
        // Resta  
        // $display("=== Pruebas de resta en half precision ===");
        // test_operation(HP_POS_5, HP_POS_2, 3'b001, 1'b0); // 5.0 - 2.0 = 3.0

        // Multiplicación
        // $display("=== Pruebas de multiplicación en half precision ===");
        // test_operation(HP_POS_2, HP_POS_1, 3'b010, 1'b0); // 2.0 * 3.0 = 6.0
        // test_operation(HP_POS_2, HP_POS_3, 3'b010, 1'b0); // 2.0 * 3.0 = 6.0
        // test_operation(HP_POS_2, HP_POS_4, 3'b010, 1'b0); // 2.0 * 3.0 = 6.0

        // División en Half Precision (usar valores HP que están en los 16 bits menos significativos)
        // $display("=== Pruebas de división en Half Precision ===");
        // test_operation(HP_POS_2, HP_POS_1, 3'b011, 1'b0); // 2.0 / 1.0 = 2.0
        // test_operation(HP_POS_2, HP_POS_2, 3'b011, 1'b0); // 2.0 / 2.0 = 1.0
        // test_operation(HP_NEG_5, HP_POS_2, 3'b011, 1'b0); // 5.0 / 2.0 = 2.5

        // $display("\n=== PRUEBAS EN HALF PRECISION (16 bits) ===");

        // Suma
        // test_operation(HP_POS_ONE, HP_POS_ONE, 3'b000, 1'b0, "ADD: 1.0 + 1.0 = 2.0");

        $display("\n=== Testbench completado ===");
        #(CLK_PERIOD * 10);
        $finish;
    end
    
    // Monitor de señales
    initial begin
        $monitor("Time: %t, Start: %b, Valid: %b, Result: %h, Flags: %b", 
                $time, start, valid_out, result, flags);
    end
    

    initial begin
        #50000;
        $display("ERROR: Timeout reached!");
        $finish;
    end

endmodule