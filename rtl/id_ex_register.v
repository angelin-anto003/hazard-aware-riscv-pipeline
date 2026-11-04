`timescale 1ns / 1ps

//==============================================================================
// Module      : id_ex_register
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : Pipeline register between the ID and EX stages.
//               Positive-edge triggered, synchronous reset and flush.
//
// Priority (highest first):
//   1. reset  : clear every field, valid_out = 0
//   2. flush  : clear every field, valid_out = 0 (bubble)
//   3. enable : capture every input field, valid_out = valid_in
//   4. hold   : keep all previous values
//
// Notes:
//   - This register only STORES fields. It does not decode, gate or modify
//     controls based on valid_in. Later stages must qualify side effects
//     (register write, memory write, branch, jump) with valid_out.
//   - There is no initial block and no asynchronous reset: outputs are
//     unknown (x) in simulation until the first reset or flush edge.
//   - Zero in every control field is a safe bubble: reg_write, mem_read,
//     mem_write, branch, jump and jump_reg are all 0.
//==============================================================================

module id_ex_register (
    input  wire        clk,
    input  wire        reset,            // Active-high, synchronous
    input  wire        enable,           // 1 = capture, 0 = hold (stall)
    input  wire        flush,            // Active-high, synchronous bubble

    // Data fields
    input  wire [31:0] pc_in,
    input  wire [31:0] pc_plus4_in,
    input  wire [31:0] rs1_data_in,
    input  wire [31:0] rs2_data_in,
    input  wire [31:0] immediate_in,

    // Register addresses
    input  wire [4:0]  rs1_addr_in,
    input  wire [4:0]  rs2_addr_in,
    input  wire [4:0]  rd_addr_in,

    // ALU controls
    input  wire [1:0]  alu_src_a_in,
    input  wire        alu_src_b_in,
    input  wire [3:0]  alu_control_in,

    // Immediate selection
    input  wire [2:0]  imm_sel_in,

    // Branch and jump controls
    input  wire        branch_in,
    input  wire [2:0]  branch_type_in,
    input  wire        jump_in,
    input  wire        jump_reg_in,

    // Memory controls
    input  wire        mem_read_in,
    input  wire        mem_write_in,

    // Write-back controls
    input  wire        reg_write_in,
    input  wire [1:0]  wb_sel_in,

    // Validity
    input  wire        valid_in,

    // Data outputs
    output reg  [31:0] pc_out,
    output reg  [31:0] pc_plus4_out,
    output reg  [31:0] rs1_data_out,
    output reg  [31:0] rs2_data_out,
    output reg  [31:0] immediate_out,

    // Register address outputs
    output reg  [4:0]  rs1_addr_out,
    output reg  [4:0]  rs2_addr_out,
    output reg  [4:0]  rd_addr_out,

    // ALU control outputs
    output reg  [1:0]  alu_src_a_out,
    output reg         alu_src_b_out,
    output reg  [3:0]  alu_control_out,

    // Immediate selection output
    output reg  [2:0]  imm_sel_out,

    // Branch and jump outputs
    output reg         branch_out,
    output reg  [2:0]  branch_type_out,
    output reg         jump_out,
    output reg         jump_reg_out,

    // Memory outputs
    output reg         mem_read_out,
    output reg         mem_write_out,

    // Write-back outputs
    output reg         reg_write_out,
    output reg  [1:0]  wb_sel_out,

    // Validity
    output reg         valid_out
);

    always @(posedge clk) begin
        if (reset) begin
            // Priority 1: reset
            pc_out          <= 32'h00000000;
            pc_plus4_out    <= 32'h00000000;
            rs1_data_out    <= 32'h00000000;
            rs2_data_out    <= 32'h00000000;
            immediate_out   <= 32'h00000000;
            rs1_addr_out    <= 5'd0;
            rs2_addr_out    <= 5'd0;
            rd_addr_out     <= 5'd0;
            alu_src_a_out   <= 2'b00;
            alu_src_b_out   <= 1'b0;
            alu_control_out <= 4'b0000;
            imm_sel_out     <= 3'b000;
            branch_out      <= 1'b0;
            branch_type_out <= 3'b000;
            jump_out        <= 1'b0;
            jump_reg_out    <= 1'b0;
            mem_read_out    <= 1'b0;
            mem_write_out   <= 1'b0;
            reg_write_out   <= 1'b0;
            wb_sel_out      <= 2'b00;
            valid_out       <= 1'b0;
        end
        else if (flush) begin
            // Priority 2: flush (wins over enable)
            pc_out          <= 32'h00000000;
            pc_plus4_out    <= 32'h00000000;
            rs1_data_out    <= 32'h00000000;
            rs2_data_out    <= 32'h00000000;
            immediate_out   <= 32'h00000000;
            rs1_addr_out    <= 5'd0;
            rs2_addr_out    <= 5'd0;
            rd_addr_out     <= 5'd0;
            alu_src_a_out   <= 2'b00;
            alu_src_b_out   <= 1'b0;
            alu_control_out <= 4'b0000;
            imm_sel_out     <= 3'b000;
            branch_out      <= 1'b0;
            branch_type_out <= 3'b000;
            jump_out        <= 1'b0;
            jump_reg_out    <= 1'b0;
            mem_read_out    <= 1'b0;
            mem_write_out   <= 1'b0;
            reg_write_out   <= 1'b0;
            wb_sel_out      <= 2'b00;
            valid_out       <= 1'b0;
        end
        else if (enable) begin
            // Priority 3: capture every field unchanged.
            // valid_out copies valid_in; controls are NOT gated by it.
            pc_out          <= pc_in;
            pc_plus4_out    <= pc_plus4_in;
            rs1_data_out    <= rs1_data_in;
            rs2_data_out    <= rs2_data_in;
            immediate_out   <= immediate_in;
            rs1_addr_out    <= rs1_addr_in;
            rs2_addr_out    <= rs2_addr_in;
            rd_addr_out     <= rd_addr_in;
            alu_src_a_out   <= alu_src_a_in;
            alu_src_b_out   <= alu_src_b_in;
            alu_control_out <= alu_control_in;
            imm_sel_out     <= imm_sel_in;
            branch_out      <= branch_in;
            branch_type_out <= branch_type_in;
            jump_out        <= jump_in;
            jump_reg_out    <= jump_reg_in;
            mem_read_out    <= mem_read_in;
            mem_write_out   <= mem_write_in;
            reg_write_out   <= reg_write_in;
            wb_sel_out      <= wb_sel_in;
            valid_out       <= valid_in;
        end
        // Priority 4: hold. No else branch is needed in a clocked block;
        // registers keep their values and no latch is created.
    end

endmodule