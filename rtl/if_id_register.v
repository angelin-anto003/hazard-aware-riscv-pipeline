`timescale 1ns / 1ps

//==============================================================================
// Module      : if_id_register
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : Pipeline register between the IF and ID stages.
//               Positive-edge triggered, synchronous reset and flush.
//
// Priority (highest first):
//   1. reset  : clear everything (bubble, PCs = 0)
//   2. flush  : insert a bubble   (valid = 0, NOP, PCs = 0)
//   3. enable : capture inputs    (valid = 1)
//   4. hold   : keep previous values
//
// Notes:
//   - There is no initial block and no asynchronous reset, so the outputs are
//     unknown (x) in simulation until the first reset edge. Reset the
//     processor before use.
//   - Reset and flush produce the same register state; they are separate
//     inputs because they come from different sources (system reset vs.
//     branch-misprediction recovery).
//   - Hazard detection and branch prediction live outside this module; it
//     only obeys the enable and flush inputs.
//==============================================================================

module if_id_register (
    input  wire        clk,
    input  wire        reset,            // Active-high, synchronous
    input  wire        enable,           // 1 = capture, 0 = hold (stall)
    input  wire        flush,            // Active-high, synchronous bubble

    input  wire [31:0] pc_in,            // PC of the fetched instruction
    input  wire [31:0] pc_plus4_in,      // PC + 4
    input  wire [31:0] instruction_in,   // Fetched instruction word

    output reg  [31:0] pc_out,
    output reg  [31:0] pc_plus4_out,
    output reg  [31:0] instruction_out,
    output reg         valid_out         // 1 = real instruction, 0 = bubble
);

    // RISC-V NOP: addi x0, x0, 0
    localparam [31:0] NOP = 32'h00000013;

    always @(posedge clk) begin
        if (reset) begin
            // Priority 1: reset
            pc_out          <= 32'h00000000;
            pc_plus4_out    <= 32'h00000000;
            instruction_out <= NOP;
            valid_out       <= 1'b0;
        end
        else if (flush) begin
            // Priority 2: flush (wins over enable)
            pc_out          <= 32'h00000000;
            pc_plus4_out    <= 32'h00000000;
            instruction_out <= NOP;
            valid_out       <= 1'b0;
        end
        else if (enable) begin
            // Priority 3: capture
            pc_out          <= pc_in;
            pc_plus4_out    <= pc_plus4_in;
            instruction_out <= instruction_in;
            valid_out       <= 1'b1;
        end
        // Priority 4: hold. No else branch is needed in a clocked block;
        // registers keep their value, and no latch is created.
    end

endmodule