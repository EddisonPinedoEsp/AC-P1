`timescale 1ns / 1ps

module top_basys3(
    input clk,
    input btnC,
    input btnR,
    input btnU,
    input btnD,
    input btnL,
    input [15:0] sw,
    output reg [15:0] led,
    output [6:0] seg,
    output dp,
    output [3:0] an
);

    // Switch mapping
    wire mode_fp = sw[0];          // 0=HP16, 1=SP32
    wire [2:0] op_code = sw[3:1];  // 000 add, 001 sub, 010 mul, 011 div
    wire page_sel = sw[4];         // 0=LOW16, 1=HIGH16 (solo SP)
    wire [1:0] target_sel = sw[6:5]; // 01=A, 10=B
    wire [15:0] data_in = sw[15:0];  // datos a latchear a A/B según página

    // Simple button synchronizers and one-shot pulses
    reg [2:0] syncC, syncD, syncR, syncU, syncL;
    always @(posedge clk) begin
        syncC <= {syncC[1:0], btnC};
        syncD <= {syncD[1:0], btnD};
        syncR <= {syncR[1:0], btnR};
        syncU <= {syncU[1:0], btnU};
        syncL <= {syncL[1:0], btnL};
    end
    wire pulseC = (syncC[2:1] == 2'b01);
    wire pulseD = (syncD[2:1] == 2'b01);
    wire pulseR = (syncR[2:1] == 2'b01);
    wire pulseU = (syncU[2:1] == 2'b01);
    wire pulseL = (syncL[2:1] == 2'b01);

    // Operandos latcheados manualmente
    reg [31:0] op_a_reg = 32'b0;
    reg [31:0] op_b_reg = 32'b0;

    // Latch de operandos con btnC
    always @(posedge clk) begin
        if (pulseU) begin
            op_a_reg <= 32'b0;
            op_b_reg <= 32'b0;
        end else if (pulseC) begin
            case (target_sel)
                2'b01: begin // A
                    if (mode_fp) begin
                        if (page_sel) op_a_reg[31:16] <= data_in; else op_a_reg[15:0] <= data_in;
                    end else begin
                        op_a_reg[15:0] <= data_in; // half usa 16 LSB
                    end
                end
                2'b10: begin // B
                    if (mode_fp) begin
                        if (page_sel) op_b_reg[31:16] <= data_in; else op_b_reg[15:0] <= data_in;
                    end else begin
                        op_b_reg[15:0] <= data_in;
                    end
                end
                default: begin end
            endcase
        end
    end

    // ALU wiring
    reg start = 1'b0;
    wire [31:0] result;
    wire valid_out;
    wire [4:0] flags;

    // Busy tracking
    reg busy = 1'b0;
    always @(posedge clk) begin
        if (pulseU) begin
            busy <= 1'b0;
            start <= 1'b0;
        end else begin
            // generate one-cycle start when btnD pressed and not busy
            start <= 1'b0;
            if (!busy && pulseD) begin
                start <= 1'b1;
                busy <= 1'b1;
            end else if (busy && valid_out) begin
                busy <= 1'b0;
            end
        end
    end

    // ALU instance
    alu u_alu (
        .clk(clk),
        .rst(1'b0),
        .op_a(op_a_reg),
        .op_b(op_b_reg),
        .op_code(op_code),
        .mode_fp(mode_fp),
        .round_mode(1'b0), // nearest-even only
        .start(start),
        .result(result),
        .valid_out(valid_out),
        .flags(flags)
    );

    // LED mapping
    always @(posedge clk) begin
        led[0]  <= flags[0]; // inexact
        led[1]  <= flags[1]; // underflow
        led[2]  <= flags[2]; // overflow
        led[3]  <= flags[3]; // div by zero
        led[4]  <= flags[4]; // invalid
        led[14] <= mode_fp;
        led[15] <= valid_out;
        led[13] <= busy;
        // Other LEDs off
        led[12:5] <= 8'b0;
    end

    // 7-seg outputs (disabled for now: all off). Active-low on Basys3.
    assign seg = 7'b1111111;
    assign dp  = 1'b1;
    assign an  = 4'b1111;

endmodule


