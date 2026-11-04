
`timescale 1ns / 1ps

//==============================================================================
// Module      : data_memory
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : 1 KB Data Memory for the MEM stage of a 5-stage RV32I CPU.
//
// Architecture:
//   - Memory capacity : 256 words x 32 bits (1 KB)
//   - Address width   : 32 bits (byte-addressed)
//   - Data width      : 32 bits
//   - Read operation  : Asynchronous (combinational)
//   - Write operation : Synchronous (positive clock edge)
//   - Initialization  : All memory locations initialized to zero
//
// Supported operations:
//   - LW (Load Word)
//   - SW (Store Word)
//
// Address mapping:
//   0x00000000 -> Word 0
//   0x00000004 -> Word 1
//   0x00000008 -> Word 2
//   ...
//   0x000003FC -> Word 255
//
// Address validation:
//   - Address must be word-aligned (address[1:0] == 2'b00).
//   - Valid address range: 0x00000000 to 0x000003FC.
//   - Invalid reads return zero.
//   - Invalid writes are ignored.
//
// Read/write behaviour:
//   - Read data reflects the current memory contents.
//   - Writes take effect on the rising edge of clk.
//   - If read and write are simultaneously enabled at the same address,
//     the read returns the old value before the edge and the new value
//     after the non-blocking write update.
//==============================================================================

module data_memory (
    input  wire        clk,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [31:0] address,
    input  wire [31:0] write_data,
    output reg  [31:0] read_data
);

    //--------------------------------------------------------------------------
    // Memory storage: 256 words x 32 bits
    //--------------------------------------------------------------------------

    reg [31:0] mem [0:255];

    integer i;

    //--------------------------------------------------------------------------
    // Memory initialization
    // All locations are initialized to zero at simulation time zero.
    //--------------------------------------------------------------------------

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            mem[i] = 32'h00000000;
        end
    end

    //--------------------------------------------------------------------------
    // Address validation and decoding
    //--------------------------------------------------------------------------

    wire address_valid;
    wire [7:0] word_index;

    // Check word alignment and memory address range.
    assign address_valid =
        (address[1:0] == 2'b00) &&
        (address[31:10] == 22'b0);

    // Convert byte address into word index.
    assign word_index = address[9:2];

    //--------------------------------------------------------------------------
    // Asynchronous memory read
    //--------------------------------------------------------------------------

    wire [31:0] mem_word;

    // Select the memory word corresponding to the address.
    assign mem_word = mem[word_index];

    always @(*) begin

        // Default output when reading is disabled or address is invalid.
        read_data = 32'h00000000;

        if (mem_read && address_valid) begin
            read_data = mem_word;
        end

    end

    //--------------------------------------------------------------------------
    // Synchronous memory write
    // Writes occur only on the rising edge of clk.
    //--------------------------------------------------------------------------

    always @(posedge clk) begin

        if (mem_write && address_valid) begin
            mem[word_index] <= write_data;
        end

    end

endmodule
