`timescale 1ns / 1ps

//==============================================================================
// Module      : id_stage
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : Instruction Decode stage wiring. Instantiates control_unit,
//               imm_gen, register_file and id_ex_register, and implements the
//               WB-to-ID bypass outside the register file.
//
// WB bypass (per read port, x0 excluded):
//   wb_write = wb_reg_write & wb_valid
//   bypass1  = wb_write & (wb_rd_addr != 0) & (wb_rd_addr == rs1)
//   bypass2  = wb_write & (wb_rd_addr != 0) & (wb_rd_addr == rs2)
//   rs1_data = bypass1 ? wb_data : register_file.read_data1
//   rs2_data = bypass2 ? wb_data : register_file.read_data2
//
// ID/EX register:
//   enable = 1 (only the PC and IF/ID stall)
//   flush  = redirect | id_ex_flush
//   valid_in = IF/ID valid
//
// illegal_instr is intentionally left unconnected (no trap).
//==============================================================================

module id_stage (
    input  wire        clk,
    input  wire        reset,

    // From the IF/ID register
    input  wire [31:0] id_pc,
    input  wire [31:0] id_pc_plus4,
    input  wire [31:0] id_instruction,
    input  wire        id_valid,

    // Pipeline control
    input  wire        redirect,          // taken branch / jump from EX
    input  wire        id_ex_flush,       // load-use bubble from hazard unit

    // Write-back port (from MEM/WB and the WB mux)
    input  wire        wb_reg_write,
    input  wire        wb_valid,
    input  wire [4:0]  wb_rd_addr,
    input  wire [31:0] wb_data,

    // ID/EX register outputs
    output wire [31:0] ex_pc,
    output wire [31:0] ex_pc_plus4,
    output wire [31:0] ex_rs1_data,
    output wire [31:0] ex_rs2_data,
    output wire [31:0] ex_immediate,
    output wire [4:0]  ex_rs1_addr,
    output wire [4:0]  ex_rs2_addr,
    output wire [4:0]  ex_rd_addr,
    output wire [1:0]  ex_alu_src_a,
    output wire        ex_alu_src_b,
    output wire [3:0]  ex_alu_control,
    output wire [2:0]  ex_imm_sel,
    output wire        ex_branch,
    output wire [2:0]  ex_branch_type,
    output wire        ex_jump,
    output wire        ex_jump_reg,
    output wire        ex_mem_read,
    output wire        ex_mem_write,
    output wire        ex_reg_write,
    output wire [1:0]  ex_wb_sel,
    output wire        ex_valid
);

    //--------------------------------------------------------------------------
    // Instruction fields
    //--------------------------------------------------------------------------
    wire [4:0] rs1_addr = id_instruction[19:15];
    wire [4:0] rs2_addr = id_instruction[24:20];
    wire [4:0] rd_addr  = id_instruction[11:7];

    //--------------------------------------------------------------------------
    // Control unit outputs
    //--------------------------------------------------------------------------
    wire       c_reg_write;
    wire       c_mem_read;
    wire       c_mem_write;
    wire       c_branch;
    wire       c_jump;
    wire       c_jump_reg;
    wire [1:0] c_alu_src_a;
    wire       c_alu_src_b;
    wire [3:0] c_alu_control;
    wire [2:0] c_imm_sel;
    wire [1:0] c_wb_sel;
    wire [2:0] c_branch_type;

    control_unit u_control (
        .instruction   (id_instruction),
        .reg_write     (c_reg_write),
        .mem_read      (c_mem_read),
        .mem_write     (c_mem_write),
        .branch        (c_branch),
        .jump          (c_jump),
        .jump_reg      (c_jump_reg),
        .alu_src_a     (c_alu_src_a),
        .alu_src_b     (c_alu_src_b),
        .alu_control   (c_alu_control),
        .imm_sel       (c_imm_sel),
        .wb_sel        (c_wb_sel),
        .branch_type   (c_branch_type),
        .illegal_instr ()                 // intentionally unconnected
    );

    //--------------------------------------------------------------------------
    // Immediate generator
    //--------------------------------------------------------------------------
    wire [31:0] imm_value;

    imm_gen u_imm_gen (
        .instruction (id_instruction),
        .imm_sel     (c_imm_sel),
        .immediate   (imm_value)
    );

    //--------------------------------------------------------------------------
    // Register file (write port driven by WB)
    //--------------------------------------------------------------------------
    wire [31:0] rf_read_data1;
    wire [31:0] rf_read_data2;
    wire        wb_write = wb_reg_write & wb_valid;

    register_file u_regfile (
        .clk          (clk),
        .reset        (reset),
        .read_addr1   (rs1_addr),
        .read_addr2   (rs2_addr),
        .read_data1   (rf_read_data1),
        .read_data2   (rf_read_data2),
        .write_enable (wb_write),
        .write_addr   (wb_rd_addr),
        .write_data   (wb_data)
    );

    //--------------------------------------------------------------------------
    // WB-to-ID bypass (outside the register file; x0 excluded)
    //--------------------------------------------------------------------------
    wire bypass1 = wb_write & (wb_rd_addr != 5'd0) & (wb_rd_addr == rs1_addr);
    wire bypass2 = wb_write & (wb_rd_addr != 5'd0) & (wb_rd_addr == rs2_addr);

    wire [31:0] id_rs1_data = bypass1 ? wb_data : rf_read_data1;
    wire [31:0] id_rs2_data = bypass2 ? wb_data : rf_read_data2;

    //--------------------------------------------------------------------------
    // ID/EX pipeline register
    //--------------------------------------------------------------------------
    id_ex_register u_id_ex (
        .clk             (clk),
        .reset           (reset),
        .enable          (1'b1),
        .flush           (redirect | id_ex_flush),

        .pc_in           (id_pc),
        .pc_plus4_in     (id_pc_plus4),
        .rs1_data_in     (id_rs1_data),
        .rs2_data_in     (id_rs2_data),
        .immediate_in    (imm_value),

        .rs1_addr_in     (rs1_addr),
        .rs2_addr_in     (rs2_addr),
        .rd_addr_in      (rd_addr),

        .alu_src_a_in    (c_alu_src_a),
        .alu_src_b_in    (c_alu_src_b),
        .alu_control_in  (c_alu_control),

        .imm_sel_in      (c_imm_sel),

        .branch_in       (c_branch),
        .branch_type_in  (c_branch_type),
        .jump_in         (c_jump),
        .jump_reg_in     (c_jump_reg),

        .mem_read_in     (c_mem_read),
        .mem_write_in    (c_mem_write),

        .reg_write_in    (c_reg_write),
        .wb_sel_in       (c_wb_sel),

        .valid_in        (id_valid),

        .pc_out          (ex_pc),
        .pc_plus4_out    (ex_pc_plus4),
        .rs1_data_out    (ex_rs1_data),
        .rs2_data_out    (ex_rs2_data),
        .immediate_out   (ex_immediate),

        .rs1_addr_out    (ex_rs1_addr),
        .rs2_addr_out    (ex_rs2_addr),
        .rd_addr_out     (ex_rd_addr),

        .alu_src_a_out   (ex_alu_src_a),
        .alu_src_b_out   (ex_alu_src_b),
        .alu_control_out (ex_alu_control),

        .imm_sel_out     (ex_imm_sel),

        .branch_out      (ex_branch),
        .branch_type_out (ex_branch_type),
        .jump_out        (ex_jump),
        .jump_reg_out    (ex_jump_reg),

        .mem_read_out    (ex_mem_read),
        .mem_write_out   (ex_mem_write),

        .reg_write_out   (ex_reg_write),
        .wb_sel_out      (ex_wb_sel),

        .valid_out       (ex_valid)
    );

endmodule