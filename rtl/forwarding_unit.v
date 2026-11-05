`timescale 1ns / 1ps

//==============================================================================
// Module      : forwarding_unit
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : Combinational forwarding unit for the EX stage. For each ALU
//               source (rs1 -> forward_a, rs2 -> forward_b) it selects where
//               the operand should come from.
//
// Encoding (forward_a / forward_b):
//   2'b00 : register file (value latched in ID/EX)
//   2'b10 : EX/MEM stage  (instruction one ahead)
//   2'b01 : MEM/WB stage  (instruction two ahead)
//   2'b11 : never generated
//
// Rules, evaluated independently for A and B:
//   1. EX/MEM is eligible when valid, reg_write = 1, NOT a load, rd != x0.
//      If its rd matches the ID/EX source -> 2'b10 (highest priority).
//   2. Otherwise MEM/WB is eligible when valid, reg_write = 1, rd != x0.
//      If its rd matches the ID/EX source -> 2'b01.
//   3. Otherwise -> 2'b00.
//
// Notes:
//   - A load in EX/MEM is excluded because its data is not available yet.
//     The load-use hazard unit must stall such a dependent instruction, so
//     the pipeline never relies on the result of this fall-through case.
//   - No clock, no reset, no state, no latches.
//==============================================================================

module forwarding_unit (
    // Source registers of the instruction currently in EX (from ID/EX)
    input  wire [4:0] id_ex_rs1_addr,
    input  wire [4:0] id_ex_rs2_addr,

    // Instruction in MEM (from EX/MEM)
    input  wire [4:0] ex_mem_rd_addr,
    input  wire       ex_mem_reg_write,
    input  wire       ex_mem_mem_read,
    input  wire       ex_mem_valid,

    // Instruction in WB (from MEM/WB)
    input  wire [4:0] mem_wb_rd_addr,
    input  wire       mem_wb_reg_write,
    input  wire       mem_wb_valid,

    // Forwarding selects
    output reg  [1:0] forward_a,
    output reg  [1:0] forward_b
);

    //--------------------------------------------------------------------------
    // Eligibility of each forwarding source (independent of the consumer)
    //--------------------------------------------------------------------------
    wire ex_mem_can_forward = ex_mem_valid
                            & ex_mem_reg_write
                            & ~ex_mem_mem_read
                            & (ex_mem_rd_addr != 5'd0);

    wire mem_wb_can_forward = mem_wb_valid
                            & mem_wb_reg_write
                            & (mem_wb_rd_addr != 5'd0);

    //--------------------------------------------------------------------------
    // Operand A (rs1)
    //--------------------------------------------------------------------------
    always @(*) begin
        forward_a = 2'b00;                                    // default
        if (ex_mem_can_forward && (ex_mem_rd_addr == id_ex_rs1_addr))
            forward_a = 2'b10;                                // EX/MEM wins
        else if (mem_wb_can_forward && (mem_wb_rd_addr == id_ex_rs1_addr))
            forward_a = 2'b01;                                // MEM/WB
    end

    //--------------------------------------------------------------------------
    // Operand B (rs2)
    //--------------------------------------------------------------------------
    always @(*) begin
        forward_b = 2'b00;                                    // default
        if (ex_mem_can_forward && (ex_mem_rd_addr == id_ex_rs2_addr))
            forward_b = 2'b10;                                // EX/MEM wins
        else if (mem_wb_can_forward && (mem_wb_rd_addr == id_ex_rs2_addr))
            forward_b = 2'b01;                                // MEM/WB
    end

endmodule