`timescale 1ns/1ps

module alu_testbench;

    // Parámetros del testbench
    localparam CLK_PERIOD = 10; // 100 MHz
    
    // Señales del testbench
    reg clk;
    reg rst;
    reg [31:0] op_a, op_b;
    reg [2:0] op_code;
    reg mode_fp;
    reg [1:0] round_mode;
    reg start;
    wire [31:0] result;
    wire valid_out;
    wire [4:0] flags;
    
    // Instancia del DUT (Device Under Test)
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
    localparam SP_POS_ONE    = 32'h3F800000; // +1.0
    localparam SP_POS_ONE_FIVE    = 32'h3FC00000; // +1.5
    localparam SP_NEG_ONE    = 32'hBF800000; // -1.0
    localparam SP_POS_TWO    = 32'h40000000; // +2.0
    localparam SP_POS_HALF   = 32'h3F000000; // +0.5
    localparam SP_POS_ZERO   = 32'h00000000; // +0.0
    localparam SP_NEG_ZERO   = 32'h80000000; // -0.0
    localparam SP_POS_INF    = 32'h7F800000; // +Inf
    localparam SP_NEG_INF    = 32'hFF800000; // -Inf
    localparam SP_QNAN       = 32'h7FC00000; // Quiet NaN
    
    // Half precision (en los 16 bits superiores)
    localparam HP_POS_ONE    = 32'h3C000000; // +1.0 en half precision
    localparam HP_POS_TWO    = 32'h40000000; // +2.0 en half precision
    localparam HP_POS_HALF   = 32'h38000000; // +0.5 en half precision
    localparam HP_POS_INF    = 32'h7C000000; // +Inf en half precision
    localparam HP_QNAN       = 32'h7E000000; // Quiet NaN en half precision
    
    // Tareas auxiliares
    task reset_system;
        begin
            rst = 1;
            start = 0;
            op_a = 32'b0;
            op_b = 32'b0;
            op_code = 3'b0;
            mode_fp = 1'b0;
            round_mode = 2'b00;
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
        input [63:0] test_name;
        begin
            $display("\n=== Test: %s ===", test_name);
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
        
        // Pruebas de suma
        test_operation(SP_POS_ONE_FIVE, SP_POS_ONE_FIVE, 3'b000, 1'b1, "ADD: 1.5 + 1.5 = 3.0");


        // $display("\n=== PRUEBAS EN HALF PRECISION (16 bits) ===");

        // // Pruebas de suma
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
    
    // Timeout de seguridad
    initial begin
        #50000; // 50 µs timeout
        $display("ERROR: Timeout reached!");
        $finish;
    end

endmodule