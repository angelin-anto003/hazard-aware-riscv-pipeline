
`timescale 1ns / 1ps

// Module: alu
// Project: Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description: 32-bit combinational RV32I ALU

module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  alu_control,

    output reg  [31:0] result,
    output wire        zero
);

// ALU control encodings
// 0000 = ADD
// 0001 = SUB
// 0010 = AND
// 0011 = OR
// 0100 = XOR
// 0101 = SLT
// 0110 = SLTU
// 0111 = SLL
// 1000 = SRL
// 1001 = SRA

always @(*) begin

    result = 32'd0;

    case (alu_control)

        // Arithmetic operations
        4'b0000: result = a + b;
        4'b0001: result = a - b;

        // Logical operations
        4'b0010: result = a & b;
        4'b0011: result = a | b;
        4'b0100: result = a ^ b;

        // Comparison operations
        4'b0101: result =
            ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;

        4'b0110: result =
            (a < b) ? 32'd1 : 32'd0;

        // Shift operations
        4'b0111: result = a << b[4:0];
        4'b1000: result = a >> b[4:0];
        4'b1001: result = $signed(a) >>> b[4:0];

        // Invalid operation
        default: result = 32'd0;

    endcase

end

// Zero flag
assign zero = (result == 32'd0);

endmodule
