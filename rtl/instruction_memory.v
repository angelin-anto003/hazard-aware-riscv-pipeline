
`timescale 1ns / 1ps

//==============================================================================
// Module      : instruction_memory
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : 1 KB Instruction Memory (256 words x 32 bits)
//               Used in the Instruction Fetch (IF) stage.
//
// Features:
//   - 32-bit byte-addressed memory
//   - 256 words, each 32 bits wide
//   - Asynchronous (combinational) read
//   - Word-aligned address validation
//   - Out-of-range address protection
//   - Zero initialization
//   - Optional initialization using $readmemh
//==============================================================================

module instruction_memory #(
    parameter INIT_FILE = ""
)(
    input  wire [31:0] address,
    output reg  [31:0] instruction
);

    // Memory storage: 256 words x 32 bits
    reg [31:0] mem [0:255];

    integer i;

    // Initialize memory to zero
    // Optionally load instructions from a hexadecimal file
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            mem[i] = 32'h00000000;
        end

        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    // Address validation
    // Valid range: 0x00000000 to 0x000003FC
    // Address must be word-aligned

    wire address_valid;
    wire [7:0] word_index;

    assign address_valid =
        (address[1:0] == 2'b00) &&
        (address[31:10] == 22'b0);

    // Convert byte address into word index
    assign word_index = address[9:2];

    // Read selected memory word
    // Separate continuous assignment avoids the Icarus
    // @* array-sensitivity warning.
    wire [31:0] mem_word;

    assign mem_word = mem[word_index];

    // Asynchronous instruction output
    always @(*) begin
        instruction = 32'h00000000;

        if (address_valid) begin
            instruction = mem_word;
        end
    end

endmodule

