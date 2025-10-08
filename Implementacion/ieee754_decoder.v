module ieee754_decoder(
    input mode_fp,              // 0=half precision, 1=single precision
    input [31:0] fp_a,          // Op A
    input [31:0] fp_b,          // Op B

    output wire sign_a,         // Signo de A
    output wire sign_b,         // Signo de B
    output reg [7:0] exp_a,     // Exponente de A (8 bits)
    output reg [7:0] exp_b,     // Exponente de B (8 bits)
    output reg [22:0] mant_a,   // Mantisa de A (23 bits)
    output reg [22:0] mant_b,   // Mantisa de B (23 bits)
    output wire is_nan_a,       // A es NaN
    output wire is_nan_b,       // B es NaN
    output wire is_inf_a,       // A es infinito
    output wire is_inf_b,       // B es infinito
    output wire is_zero_a,      // A es cero
    output wire is_zero_b,      // B es cero
    output wire is_denorm_a,    // A es denormalizado
    output wire is_denorm_b     // B es denormalizado
);

    // Parámetros para IEEE-754
    localparam SP_EXP_MAX = 8'hFF;
    localparam HP_EXP_MAX = 5'h1F;
    localparam SP_EXP_BIAS = 127;
    localparam HP_EXP_BIAS = 15;

    // Extracción de campos para single precision
    wire [7:0] sp_exp_a, sp_exp_b;
    wire [22:0] sp_mant_a, sp_mant_b;
    
    assign sign_a = mode_fp ? fp_a[31] : fp_a[15];  // Bit 15 para half precision
    assign sign_b = mode_fp ? fp_b[31] : fp_b[15];
    
    assign sp_exp_a = fp_a[30:23];
    assign sp_exp_b = fp_b[30:23];
    assign sp_mant_a = fp_a[22:0];
    assign sp_mant_b = fp_b[22:0];
    
    // Extracción de campos para half precision (en los 16 bits menos significativos)
    wire [4:0] hp_exp_a, hp_exp_b;
    wire [9:0] hp_mant_a, hp_mant_b;
    
    assign hp_exp_a = fp_a[14:10];  // Exponente en bits 14:10 de los 16 bits menos significativos
    assign hp_exp_b = fp_b[14:10];
    assign hp_mant_a = fp_a[9:0];   // Mantisa en bits 9:0 de los 16 bits menos significativos
    assign hp_mant_b = fp_b[9:0];
    
    // Conversión de exponentes y mantisas según el modo
    always @(*) begin
        if (mode_fp) begin
            // Single precision
            exp_a = sp_exp_a;
            exp_b = sp_exp_b;
            mant_a = sp_mant_a;
            mant_b = sp_mant_b;
        end else begin
            // Half precision - convertir a formato extendido
            // Convertir exponente de 5 bits a 8 bits ajustando el bias
            if (hp_exp_a == 5'b0) begin
                exp_a = 8'b0; // Mantener cero o denormal
            end else if (hp_exp_a == 5'h1F) begin
                exp_a = 8'hFF; // Infinito o NaN
            end else begin
                // Ajustar bias: half precision bias=15, single precision bias=127
                exp_a = hp_exp_a - HP_EXP_BIAS + SP_EXP_BIAS;
            end
            
            if (hp_exp_b == 5'b0) begin
                exp_b = 8'b0;
            end else if (hp_exp_b == 5'h1F) begin
                exp_b = 8'hFF;
            end else begin
                exp_b = hp_exp_b - HP_EXP_BIAS + SP_EXP_BIAS;
            end
            
            // Extender mantisa de 10 bits a 23 bits (agregar ceros a la derecha)
            mant_a = {hp_mant_a, 13'b0};
            mant_b = {hp_mant_b, 13'b0};
        end
    end
    
    // Detección de casos especiales para operando A
    wire sp_zero_a, sp_denorm_a, sp_inf_a, sp_nan_a;
    wire hp_zero_a, hp_denorm_a, hp_inf_a, hp_nan_a;
    
    // Single precision A
    assign sp_zero_a = (sp_exp_a == 8'b0) && (sp_mant_a == 23'b0);
    assign sp_denorm_a = (sp_exp_a == 8'b0) && (sp_mant_a != 23'b0);
    assign sp_inf_a = (sp_exp_a == 8'hFF) && (sp_mant_a == 23'b0);
    assign sp_nan_a = (sp_exp_a == 8'hFF) && (sp_mant_a != 23'b0);
    
    // Half precision A
    assign hp_zero_a = (hp_exp_a == 5'b0) && (hp_mant_a == 10'b0);
    assign hp_denorm_a = (hp_exp_a == 5'b0) && (hp_mant_a != 10'b0);
    assign hp_inf_a = (hp_exp_a == 5'h1F) && (hp_mant_a == 10'b0);
    assign hp_nan_a = (hp_exp_a == 5'h1F) && (hp_mant_a != 10'b0);
    
    // Detección de casos especiales para operando B
    wire sp_zero_b, sp_denorm_b, sp_inf_b, sp_nan_b;
    wire hp_zero_b, hp_denorm_b, hp_inf_b, hp_nan_b;
    
    // Single precision B
    assign sp_zero_b = (sp_exp_b == 8'b0) && (sp_mant_b == 23'b0);
    assign sp_denorm_b = (sp_exp_b == 8'b0) && (sp_mant_b != 23'b0);
    assign sp_inf_b = (sp_exp_b == 8'hFF) && (sp_mant_b == 23'b0);
    assign sp_nan_b = (sp_exp_b == 8'hFF) && (sp_mant_b != 23'b0);
    
    // Half precision B
    assign hp_zero_b = (hp_exp_b == 5'b0) && (hp_mant_b == 10'b0);
    assign hp_denorm_b = (hp_exp_b == 5'b0) && (hp_mant_b != 10'b0);
    assign hp_inf_b = (hp_exp_b == 5'h1F) && (hp_mant_b == 10'b0);
    assign hp_nan_b = (hp_exp_b == 5'h1F) && (hp_mant_b != 10'b0);
    
    // Salidas multiplexadas según el modo
    assign is_zero_a = mode_fp ? sp_zero_a : hp_zero_a;
    assign is_zero_b = mode_fp ? sp_zero_b : hp_zero_b;
    assign is_denorm_a = mode_fp ? sp_denorm_a : hp_denorm_a;
    assign is_denorm_b = mode_fp ? sp_denorm_b : hp_denorm_b;
    assign is_inf_a = mode_fp ? sp_inf_a : hp_inf_a;
    assign is_inf_b = mode_fp ? sp_inf_b : hp_inf_b;
    assign is_nan_a = mode_fp ? sp_nan_a : hp_nan_a;
    assign is_nan_b = mode_fp ? sp_nan_b : hp_nan_b;

endmodule