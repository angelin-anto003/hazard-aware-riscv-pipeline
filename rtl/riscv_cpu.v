`timescale 1ns / 1ps

//==============================================================================
// Module      : riscv_cpu
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : Top-level five-stage RV32I pipeline. Instantiates only the
//               stage wrappers and the hazard detection unit.
//
//   IF  : if_stage   (PC, instruction memory, IF/ID register)
//   ID  : id_stage   (control, imm_gen, the ONLY register file, ID/EX register)
//   EX  : ex_stage   (forwarding, ALU, comparator, redirect, EX/MEM register)
//   MEM : mem_stage  (data memory, MEM/WB register)
//   WB  : wb_stage   (write-back mux and write enable)
//
// Control summary:
//   redirect (from EX) -> if_stage (PC load + IF/ID flush) and
//                         id_stage (ID/EX flush). EX/MEM and MEM/WB continue.
//   hazard unit        -> pc_write / if_id_write (stall), id_ex_flush (bubble)
//   WB -> ID           : wb_data / wb_write_enable / wb_write_addr / wb_valid
//   WB -> EX forwarding: wb_rd_addr / wb_reg_write / wb_valid / wb_data
//
// Static not-taken prediction, branches resolved in EX.
//==============================================================================

module riscv_cpu #(
    parameter INIT_FILE = ""
) (
    input wire clk,
    input wire reset
);

    //--------------------------------------------------------------------------
    // IF/ID register outputs (from if_stage, to id_stage and hazard unit)
    //--------------------------------------------------------------------------
    wire [31:0] id_pc;
    wire [31:0] id_pc_plus4;
    wire [31:0] id_instruction;
    wire        id_valid;

    //--------------------------------------------------------------------------
    // ID/EX register outputs (from id_stage, to ex_stage and hazard unit)
    //--------------------------------------------------------------------------
    wire [31:0] ex_pc;
    wire [31:0] ex_pc_plus4;
    wire [31:0] ex_rs1_data;
    wire [31:0] ex_rs2_data;
    wire [31:0] ex_immediate;
    wire [4:0]  ex_rs1_addr;
    wire [4:0]  ex_rs2_addr;
    wire [4:0]  ex_rd_addr;
    wire [1:0]  ex_alu_src_a;
    wire        ex_alu_src_b;
    wire [3:0]  ex_alu_control;
    wire        ex_branch;
    wire [2:0]  ex_branch_type;
    wire        ex_jump;
    wire        ex_jump_reg;
    wire        ex_mem_read;
    wire        ex_mem_write;
    wire        ex_reg_write;
    wire [1:0]  ex_wb_sel;
    wire        ex_valid;

    //--------------------------------------------------------------------------
    // EX/MEM register outputs and redirect (from ex_stage)
    //--------------------------------------------------------------------------
    wire        redirect;
    wire [31:0] redirect_target;
    wire [31:0] mem_pc_plus4;
    wire [31:0] mem_alu_result;
    wire [31:0] mem_store_data;
    wire [31:0] mem_immediate;
    wire [4:0]  mem_rd_addr;
    wire        mem_mem_read;
    wire        mem_mem_write;
    wire        mem_reg_write;
    wire [1:0]  mem_wb_sel;
    wire        mem_valid;

    //--------------------------------------------------------------------------
    // MEM/WB register outputs (from mem_stage)
    //--------------------------------------------------------------------------
    wire [31:0] wb_alu_result;
    wire [31:0] wb_mem_read_data;
    wire [31:0] wb_pc_plus4;
    wire [31:0] wb_immediate;
    wire [4:0]  wb_rd_addr;
    wire        wb_reg_write;      // raw MEM/WB reg_write (not gated)
    wire [1:0]  wb_sel;
    wire        wb_valid;

    //--------------------------------------------------------------------------
    // WB stage outputs
    //--------------------------------------------------------------------------
    wire [31:0] wb_data;           // final WB mux value (never gated)
    wire        wb_write_enable;   // reg_write & valid & (rd != x0)
    wire [4:0]  wb_write_addr;

    //--------------------------------------------------------------------------
    // Hazard detection outputs
    //--------------------------------------------------------------------------
    wire        pc_write;
    wire        if_id_write;
    wire        id_ex_flush;

    //--------------------------------------------------------------------------
    // IF stage
    //--------------------------------------------------------------------------
    if_stage #(
        .INIT_FILE (INIT_FILE)
    ) u_if (
        .clk             (clk),
        .reset           (reset),
        .pc_write        (pc_write),
        .if_id_write     (if_id_write),
        .redirect        (redirect),
        .redirect_target (redirect_target),
        .pc              (),                    // live fetch PC, unused
        .id_pc           (id_pc),
        .id_pc_plus4     (id_pc_plus4),
        .id_instruction  (id_instruction),
        .id_valid        (id_valid)
    );

    //--------------------------------------------------------------------------
    // Hazard detection (reads the instruction in ID and the load in EX)
    //--------------------------------------------------------------------------
    hazard_detection_unit u_hazard (
        .id_ex_mem_read (ex_mem_read),
        .id_ex_rd_addr  (ex_rd_addr),
        .if_id_rs1_addr (id_instruction[19:15]),
        .if_id_rs2_addr (id_instruction[24:20]),
        .pc_write       (pc_write),
        .if_id_write    (if_id_write),
        .id_ex_flush    (id_ex_flush)
    );

    //--------------------------------------------------------------------------
    // ID stage (contains the only register file)
    //--------------------------------------------------------------------------
    id_stage u_id (
        .clk            (clk),
        .reset          (reset),
        .id_pc          (id_pc),
        .id_pc_plus4    (id_pc_plus4),
        .id_instruction (id_instruction),
        .id_valid       (id_valid),
        .redirect       (redirect),
        .id_ex_flush    (id_ex_flush),
        .wb_reg_write   (wb_write_enable),
        .wb_valid       (wb_valid),
        .wb_rd_addr     (wb_write_addr),
        .wb_data        (wb_data),
        .ex_pc          (ex_pc),
        .ex_pc_plus4    (ex_pc_plus4),
        .ex_rs1_data    (ex_rs1_data),
        .ex_rs2_data    (ex_rs2_data),
        .ex_immediate   (ex_immediate),
        .ex_rs1_addr    (ex_rs1_addr),
        .ex_rs2_addr    (ex_rs2_addr),
        .ex_rd_addr     (ex_rd_addr),
        .ex_alu_src_a   (ex_alu_src_a),
        .ex_alu_src_b   (ex_alu_src_b),
        .ex_alu_control (ex_alu_control),
        .ex_imm_sel     (),                     // unused downstream
        .ex_branch      (ex_branch),
        .ex_branch_type (ex_branch_type),
        .ex_jump        (ex_jump),
        .ex_jump_reg    (ex_jump_reg),
        .ex_mem_read    (ex_mem_read),
        .ex_mem_write   (ex_mem_write),
        .ex_reg_write   (ex_reg_write),
        .ex_wb_sel      (ex_wb_sel),
        .ex_valid       (ex_valid)
    );

    //--------------------------------------------------------------------------
    // EX stage
    //--------------------------------------------------------------------------
    ex_stage u_ex (
        .clk               (clk),
        .reset             (reset),
        .id_ex_pc          (ex_pc),
        .id_ex_pc_plus4    (ex_pc_plus4),
        .id_ex_rs1_data    (ex_rs1_data),
        .id_ex_rs2_data    (ex_rs2_data),
        .id_ex_immediate   (ex_immediate),
        .id_ex_rs1_addr    (ex_rs1_addr),
        .id_ex_rs2_addr    (ex_rs2_addr),
        .id_ex_rd_addr     (ex_rd_addr),
        .id_ex_alu_src_a   (ex_alu_src_a),
        .id_ex_alu_src_b   (ex_alu_src_b),
        .id_ex_alu_control (ex_alu_control),
        .id_ex_branch      (ex_branch),
        .id_ex_branch_type (ex_branch_type),
        .id_ex_jump        (ex_jump),
        .id_ex_jump_reg    (ex_jump_reg),
        .id_ex_mem_read    (ex_mem_read),
        .id_ex_mem_write   (ex_mem_write),
        .id_ex_reg_write   (ex_reg_write),
        .id_ex_wb_sel      (ex_wb_sel),
        .id_ex_valid       (ex_valid),
        .wb_rd_addr        (wb_rd_addr),
        .wb_reg_write      (wb_reg_write),
        .wb_valid          (wb_valid),
        .wb_data           (wb_data),
        .redirect          (redirect),
        .redirect_target   (redirect_target),
        .mem_pc_plus4      (mem_pc_plus4),
        .mem_alu_result    (mem_alu_result),
        .mem_store_data    (mem_store_data),
        .mem_immediate     (mem_immediate),
        .mem_rd_addr       (mem_rd_addr),
        .mem_mem_read      (mem_mem_read),
        .mem_mem_write     (mem_mem_write),
        .mem_reg_write     (mem_reg_write),
        .mem_wb_sel        (mem_wb_sel),
        .mem_valid         (mem_valid)
    );

    //--------------------------------------------------------------------------
    // MEM stage
    //--------------------------------------------------------------------------
    mem_stage u_mem (
        .clk              (clk),
        .reset            (reset),
        .mem_pc_plus4     (mem_pc_plus4),
        .mem_alu_result   (mem_alu_result),
        .mem_store_data   (mem_store_data),
        .mem_immediate    (mem_immediate),
        .mem_rd_addr      (mem_rd_addr),
        .mem_mem_read     (mem_mem_read),
        .mem_mem_write    (mem_mem_write),
        .mem_reg_write    (mem_reg_write),
        .mem_wb_sel       (mem_wb_sel),
        .mem_valid        (mem_valid),
        .wb_alu_result    (wb_alu_result),
        .wb_mem_read_data (wb_mem_read_data),
        .wb_pc_plus4      (wb_pc_plus4),
        .wb_immediate     (wb_immediate),
        .wb_rd_addr       (wb_rd_addr),
        .wb_reg_write     (wb_reg_write),
        .wb_sel           (wb_sel),
        .wb_valid         (wb_valid)
    );

    //--------------------------------------------------------------------------
    // WB stage (combinational: write-back mux and write enable)
    //--------------------------------------------------------------------------
    wb_stage u_wb (
        .wb_alu_result    (wb_alu_result),
        .wb_mem_read_data (wb_mem_read_data),
        .wb_pc_plus4      (wb_pc_plus4),
        .wb_immediate     (wb_immediate),
        .wb_rd_addr       (wb_rd_addr),
        .wb_reg_write     (wb_reg_write),
        .wb_sel           (wb_sel),
        .wb_valid         (wb_valid),
        .wb_data          (wb_data),
        .wb_write_enable  (wb_write_enable),
        .wb_write_addr    (wb_write_addr)
    );

endmodule