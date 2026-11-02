
`timescale 1ns / 1ps

//==============================================================================
// Module      : register_file
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : 32 x 32-bit RISC-V RV32I Register File
//
// Features:
//   - 32 general-purpose registers (x0 - x31)
//   - Two independent combinational read ports
//   - One synchronous write port (positive-edge triggered)
//   - Active-high synchronous reset
//   - Reset has priority over register writes
//   - Register x0 is hardwired to zero
//
// Notes:
//   - Reads are asynchronous (combinational).
//   - Writes occur only on the rising edge of the clock.
//   - Writes to x0 are ignored.
//   - Data forwarding and hazard handling are implemented
//     outside this module.
//==============================================================================

module register_file (
    input  wire        clk,
    input  wire        reset,

    // Read port 1
    input  wire [4:0]  read_addr1,
    output wire [31:0] read_data1,

    // Read port 2
    input  wire [4:0]  read_addr2,
    output wire [31:0] read_data2,

    // Write port
    input  wire        write_enable,
    input  wire [4:0]  write_addr,
    input  wire [31:0] write_data
);

    //--------------------------------------------------------------------------
    // Register storage
    // 32 registers, each 32 bits wide.
    //--------------------------------------------------------------------------
    reg [31:0] registers [0:31];

    integer i;

    //--------------------------------------------------------------------------
    // Sequential logic: synchronous reset and register write
    //--------------------------------------------------------------------------
    always @(posedge clk) begin

        if (reset) begin

            // Clear all registers during reset
            for (i = 0; i < 32; i = i + 1) begin
                registers[i] <= 32'd0;
            end

        end
        else if (write_enable && (write_addr != 5'd0)) begin

            // Write data to the selected register
            registers[write_addr] <= write_data;

        end

    end

    //--------------------------------------------------------------------------
    // Combinational logic: independent register read ports
    //--------------------------------------------------------------------------

    // Read port 1
    assign read_data1 = (read_addr1 == 5'd0)
                      ? 32'd0
                      : registers[read_addr1];

    // Read port 2
    assign read_data2 = (read_addr2 == 5'd0)
                      ? 32'd0
                      : registers[read_addr2];

endmodule
