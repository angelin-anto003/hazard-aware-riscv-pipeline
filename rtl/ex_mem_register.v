`timescale 1ns / 1ps

//==============================================================================
// Module      : ex_mem_register
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : Pipeline register between the EX and MEM stages.
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
//     any control signal based on valid_in. Later stages (MEM, WB) must
//     qualify side effects (memory access, register write) with valid_out.
//   - There is no initial block and no asynchronous reset, so outputs are
//     unknown (x) in simulation until the first reset or flush edge.
//   - Zero in every control field is a safe bubble: mem_read, mem_write and
//     reg_write are all 0.
//==============================================================================

module ex_mem_register (
    input  wire        clk,
    input  wire        reset,           // Active-high, synchronous
    input  wire        enable,          // 1 = capture, 0 = hold
    input  wire        flush,           // Active-high, synchronous bubble

    // Data fields
    input  wire [31:0] pc_plus4_in,
    input  wire [31:0] alu_result_in,
    input  wire [31:0] store_data_in,
    input  wire [31:0] immediate_in,

    // Destination register
    input  wire [4:0]  rd_addr_in,

    // Memory controls
    input  wire        mem_read_in,
    input  wire        mem_write_in,

    // Write-back controls
    input  wire        reg_write_in,
    input  wire [1:0]  wb_sel_in,

    // Validity
    input  wire        valid_in,

    // Data outputs
    output reg  [31:0] pc_plus4_out,
    output reg  [31:0] alu_result_out,
    output reg  [31:0] store_data_out,
    output reg  [31:0] immediate_out,

    // Destination register output
    output reg  [4:0]  rd_addr_out,

    // Memory control outputs
    output reg         mem_read_out,
    output reg         mem_write_out,

    // Write-back control outputs
    output reg         reg_write_out,
    output reg  [1:0]  wb_sel_out,

    // Validity output
    output reg         valid_out
);

    always @(posedge clk) begin
        if (reset) begin
            // Priority 1: reset
            pc_plus4_out   <= 32'h00000000;
            alu_result_out <= 32'h00000000;
            store_data_out <= 32'h00000000;
            immediate_out  <= 32'h00000000;
            rd_addr_out    <= 5'd0;
            mem_read_out   <= 1'b0;
            mem_write_out  <= 1'b0;
            reg_write_out  <= 1'b0;
            wb_sel_out     <= 2'b00;
            valid_out      <= 1'b0;
        end
        else if (flush) begin
            // Priority 2: flush (wins over enable)
            pc_plus4_out   <= 32'h00000000;
            alu_result_out <= 32'h00000000;
            store_data_out <= 32'h00000000;
            immediate_out  <= 32'h00000000;
            rd_addr_out    <= 5'd0;
            mem_read_out   <= 1'b0;
            mem_write_out  <= 1'b0;
            reg_write_out  <= 1'b0;
            wb_sel_out     <= 2'b00;
            valid_out      <= 1'b0;
        end
        else if (enable) begin
            // Priority 3: capture every field unchanged.
            // Controls are NOT gated by valid_in; valid_out copies it.
            pc_plus4_out   <= pc_plus4_in;
            alu_result_out <= alu_result_in;
            store_data_out <= store_data_in;
            immediate_out  <= immediate_in;
            rd_addr_out    <= rd_addr_in;
            mem_read_out   <= mem_read_in;
            mem_write_out  <= mem_write_in;
            reg_write_out  <= reg_write_in;
            wb_sel_out     <= wb_sel_in;
            valid_out      <= valid_in;
        end
        // Priority 4: hold. No else branch is needed in a clocked block;
        // registers keep their values and no latch is created.
    end

endmodule