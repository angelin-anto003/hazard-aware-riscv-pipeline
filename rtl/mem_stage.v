`timescale 1ns / 1ps

//==============================================================================
// Module      : mem_stage
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : Memory stage wiring. Instantiates data_memory and the MEM/WB
//               pipeline register.
//
// Memory side effects are qualified with the EX/MEM valid bit:
//   data_memory.mem_read  = mem_mem_read  & mem_valid
//   data_memory.mem_write = mem_mem_write & mem_valid
// An invalid (bubble) pipeline entry therefore never reads or writes memory.
//
// Address = ALU result, store data = forwarded rs2 (from the EX stage).
// LW and SW only; data_memory ignores misaligned / out-of-range accesses.
//
// MEM/WB register: enable = 1, flush = 0, valid_in = mem_valid.
// reg_write is passed through UNGATED; the WB stage must qualify it with
// wb_valid (e.g. register write enable = wb_reg_write & wb_valid).
//==============================================================================

module mem_stage (
    input  wire        clk,
    input  wire        reset,

    // EX/MEM register outputs (names match the ex_stage outputs)
    input  wire [31:0] mem_pc_plus4,
    input  wire [31:0] mem_alu_result,
    input  wire [31:0] mem_store_data,
    input  wire [31:0] mem_immediate,
    input  wire [4:0]  mem_rd_addr,
    input  wire        mem_mem_read,
    input  wire        mem_mem_write,
    input  wire        mem_reg_write,
    input  wire [1:0]  mem_wb_sel,
    input  wire        mem_valid,

    // MEM/WB register outputs (to the WB stage)
    output wire [31:0] wb_alu_result,
    output wire [31:0] wb_mem_read_data,
    output wire [31:0] wb_pc_plus4,
    output wire [31:0] wb_immediate,
    output wire [4:0]  wb_rd_addr,
    output wire        wb_reg_write,
    output wire [1:0]  wb_sel,
    output wire        wb_valid
);

    //--------------------------------------------------------------------------
    // Valid-qualified memory controls
    //--------------------------------------------------------------------------
   wire dm_read  = mem_mem_read  & mem_valid & ~reset;
   wire dm_write = mem_mem_write & mem_valid & ~reset;
    wire [31:0] dm_read_data;

    //--------------------------------------------------------------------------
    // Data memory
    //--------------------------------------------------------------------------
    data_memory u_dmem (
        .clk        (clk),
        .mem_read   (dm_read),
        .mem_write  (dm_write),
        .address    (mem_alu_result),
        .write_data (mem_store_data),
        .read_data  (dm_read_data)
    );

    //--------------------------------------------------------------------------
    // MEM/WB pipeline register
    //--------------------------------------------------------------------------
    mem_wb_register u_mem_wb (
        .clk               (clk),
        .reset             (reset),
        .enable            (1'b1),
        .flush             (1'b0),

        .alu_result_in     (mem_alu_result),
        .mem_read_data_in  (dm_read_data),
        .pc_plus4_in       (mem_pc_plus4),
        .immediate_in      (mem_immediate),

        .rd_addr_in        (mem_rd_addr),

        .reg_write_in      (mem_reg_write),
        .wb_sel_in         (mem_wb_sel),

        .valid_in          (mem_valid),

        .alu_result_out    (wb_alu_result),
        .mem_read_data_out (wb_mem_read_data),
        .pc_plus4_out      (wb_pc_plus4),
        .immediate_out     (wb_immediate),

        .rd_addr_out       (wb_rd_addr),

        .reg_write_out     (wb_reg_write),
        .wb_sel_out        (wb_sel),

        .valid_out         (wb_valid)
    );

endmodule