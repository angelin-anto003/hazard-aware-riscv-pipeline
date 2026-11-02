`timescale 1ns / 1ps
module program_counter (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire [31:0] next_pc,
    output reg  [31:0] pc
);

    // Reset address
    localparam [31:0] RESET_PC = 32'h00000000;

    // Sequential Program Counter
    always @(posedge clk) begin
        if (reset) begin
            pc <= RESET_PC;
        end
        else if (enable) begin
            pc <= next_pc;
        end
    end

endmodule
