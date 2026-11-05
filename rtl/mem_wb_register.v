`timescale 1ns / 1ps

//==============================================================================
// Module      : mem_wb_register
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : Pipeline register between the MEM and WB stages.
//               Positive-edge triggered, synchronous reset and flush.
//
// Priority (highest first):
//   1. reset  : clear every output field to zero (valid_out = 0)
//   2. flush  : clear every output field to zero (valid_out = 0)
//   3. enable : capture every input field exactly, valid_out = valid_in
//   4. hold   : keep all previous values
//
// Notes:
//   - This register only STORES fields. It does not decode, gate or modify
//     any control signal based on valid_in. In particular, reg_write_out is
//     NOT gated by valid_in: the WB stage must qualify the register-file
//     write with valid_out (e.g. rf_write = reg_write_out & valid_out).
//   - There is no initial block and no asynchronous reset, so outputs are
//     unknown (x) in simulation until the first reset or flush edge.
//   - Zero in every field is a safe bubble: reg_write_out = 0, so nothing
//     is written back.
//==============================================================================

module mem_wb_register (
    input  wire        clk,
    input  wire        reset,              // Active-high, synchronous
    input  wire        enable,             // 1 = capture, 0 = hold
    input  wire        flush,              // Active-high, synchronous bubble

    // Data fields
    input  wire [31:0] alu_result_in,
    input  wire [31:0] mem_read_data_in,
    input  wire [31:0] pc_plus4_in,
    input  wire [31:0] immediate_in,

    // Destination register
    input  wire [4:0]  rd_addr_in,

    // Write-back controls
    input  wire        reg_write_in,
    input  wire [1:0]  wb_sel_in,

    // Validity
    input  wire        valid_in,

    // Data outputs
    output reg  [31:0] alu_result_out,
    output reg  [31:0] mem_read_data_out,
    output reg  [31:0] pc_plus4_out,
    output reg  [31:0] immediate_out,

    // Destination register output
    output reg  [4:0]  rd_addr_out,

    // Write-back control outputs
    output reg         reg_write_out,
    output reg  [1:0]  wb_sel_out,

    // Validity output
    output reg         valid_out
);

    always @(posedge clk) begin
        if (reset) begin
            // Priority 1: reset
            alu_result_out    <= 32'h00000000;
            mem_read_data_out <= 32'h00000000;
            pc_plus4_out      <= 32'h00000000;
            immediate_out     <= 32'h00000000;
            rd_addr_out       <= 5'd0;
            reg_write_out     <= 1'b0;
            wb_sel_out        <= 2'b00;
            valid_out         <= 1'b0;
        end
        else if (flush) begin
            // Priority 2: flush (wins over enable)
            alu_result_out    <= 32'h00000000;
            mem_read_data_out <= 32'h00000000;
            pc_plus4_out      <= 32'h00000000;
            immediate_out     <= 32'h00000000;
            rd_addr_out       <= 5'd0;
            reg_write_out     <= 1'b0;
            wb_sel_out        <= 2'b00;
            valid_out         <= 1'b0;
        end
        else if (enable) begin
            // Priority 3: capture every field unchanged.
            // reg_write_out is NOT gated by valid_in; valid_out copies it.
            alu_result_out    <= alu_result_in;
            mem_read_data_out <= mem_read_data_in;
            pc_plus4_out      <= pc_plus4_in;
            immediate_out     <= immediate_in;
            rd_addr_out       <= rd_addr_in;
            reg_write_out     <= reg_write_in;
            wb_sel_out        <= wb_sel_in;
            valid_out         <= valid_in;
        end
        // Priority 4: hold. No else branch is needed in a clocked block;
        // registers keep their values and no latch is created.
    end

endmodule