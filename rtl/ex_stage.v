`timescale 1ns / 1ps

//==============================================================================
// Module      : ex_stage
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : Execute stage wiring. Instantiates forwarding_unit, alu,
//               branch_comparator and ex_mem_register, and implements the
//               forwarding muxes, ALU operand muxes and redirect logic.
//
// Forwarding (select from forwarding_unit, EX/MEM already has priority there):
//   00 : ID/EX register value      10 : EX/MEM forward value
//   01 : wb_data (final WB mux)    11 : never generated (register value)
//
// EX/MEM forward value (the instruction one ahead, now in MEM):
//   mem_wb_sel == 10 -> PC+4  (JAL/JALR link)
//   mem_wb_sel == 11 -> immediate (LUI)
//   otherwise        -> ALU result
//   Loads are blocked by the forwarding unit and never use this value.
//
// ALU A : alu_src_a 00 forwarded rs1, 01 PC, 10 zero, 11 zero (never generated)
// ALU B : alu_src_b 0 forwarded rs2, 1 immediate
// Comparator and store data use the FORWARDED rs1/rs2, not the ALU operands.
//
// Redirect (resolved in EX, qualified by the ID/EX valid bit):
//   redirect        = valid & ((branch & taken) | jump)
//   redirect_target = jump_reg ? (alu_result & ~1) : alu_result
//
// EX/MEM register: enable = 1, flush = 0. Side effects in the outputs are
// NOT masked; MEM and WB must qualify them with mem_valid.
//==============================================================================

module ex_stage (
    input  wire        clk,
    input  wire        reset,

    // ID/EX register outputs used by this stage
    input  wire [31:0] id_ex_pc,
    input  wire [31:0] id_ex_pc_plus4,
    input  wire [31:0] id_ex_rs1_data,
    input  wire [31:0] id_ex_rs2_data,
    input  wire [31:0] id_ex_immediate,
    input  wire [4:0]  id_ex_rs1_addr,
    input  wire [4:0]  id_ex_rs2_addr,
    input  wire [4:0]  id_ex_rd_addr,
    input  wire [1:0]  id_ex_alu_src_a,
    input  wire        id_ex_alu_src_b,
    input  wire [3:0]  id_ex_alu_control,
    input  wire        id_ex_branch,
    input  wire [2:0]  id_ex_branch_type,
    input  wire        id_ex_jump,
    input  wire        id_ex_jump_reg,
    input  wire        id_ex_mem_read,
    input  wire        id_ex_mem_write,
    input  wire        id_ex_reg_write,
    input  wire [1:0]  id_ex_wb_sel,
    input  wire        id_ex_valid,

    // Write-back values for forwarding (from MEM/WB and the WB mux)
    input  wire [4:0]  wb_rd_addr,
    input  wire        wb_reg_write,
    input  wire        wb_valid,
    input  wire [31:0] wb_data,

    // Redirect to the IF stage and pipeline flush logic
    output wire        redirect,
    output wire [31:0] redirect_target,

    // EX/MEM register outputs (to the MEM stage)
    output wire [31:0] mem_pc_plus4,
    output wire [31:0] mem_alu_result,
    output wire [31:0] mem_store_data,
    output wire [31:0] mem_immediate,
    output wire [4:0]  mem_rd_addr,
    output wire        mem_mem_read,
    output wire        mem_mem_write,
    output wire        mem_reg_write,
    output wire [1:0]  mem_wb_sel,
    output wire        mem_valid
);

    //--------------------------------------------------------------------------
    // Forwarding unit
    //--------------------------------------------------------------------------
    wire [1:0] forward_a;
    wire [1:0] forward_b;

    forwarding_unit u_fwd (
        .id_ex_rs1_addr   (id_ex_rs1_addr),
        .id_ex_rs2_addr   (id_ex_rs2_addr),
        .ex_mem_rd_addr   (mem_rd_addr),
        .ex_mem_reg_write (mem_reg_write),
        .ex_mem_mem_read  (mem_mem_read),
        .ex_mem_valid     (mem_valid),
        .mem_wb_rd_addr   (wb_rd_addr),
        .mem_wb_reg_write (wb_reg_write),
        .mem_wb_valid     (wb_valid),
        .forward_a        (forward_a),
        .forward_b        (forward_b)
    );

    //--------------------------------------------------------------------------
    // EX/MEM forward value
    //--------------------------------------------------------------------------
    wire [31:0] em_fwd_value = (mem_wb_sel == 2'b10) ? mem_pc_plus4 :
                               (mem_wb_sel == 2'b11) ? mem_immediate :
                                                       mem_alu_result;

    //--------------------------------------------------------------------------
    // Forwarding muxes
    //--------------------------------------------------------------------------
    reg [31:0] fwd_rs1;
    reg [31:0] fwd_rs2;

    always @(*) begin
        case (forward_a)
            2'b10:   fwd_rs1 = em_fwd_value;
            2'b01:   fwd_rs1 = wb_data;
            default: fwd_rs1 = id_ex_rs1_data;
        endcase
    end

    always @(*) begin
        case (forward_b)
            2'b10:   fwd_rs2 = em_fwd_value;
            2'b01:   fwd_rs2 = wb_data;
            default: fwd_rs2 = id_ex_rs2_data;
        endcase
    end

    //--------------------------------------------------------------------------
    // ALU operand muxes
    //--------------------------------------------------------------------------
    reg [31:0] alu_a;
    reg [31:0] alu_b;

    always @(*) begin
        case (id_ex_alu_src_a)
            2'b00:   alu_a = fwd_rs1;
            2'b01:   alu_a = id_ex_pc;
            default: alu_a = 32'h00000000;   // 10 = zero; 11 never generated
        endcase
    end

    always @(*) begin
        if (id_ex_alu_src_b)
            alu_b = id_ex_immediate;
        else
            alu_b = fwd_rs2;
    end

    //--------------------------------------------------------------------------
    // ALU
    //--------------------------------------------------------------------------
    wire [31:0] alu_result;

    alu u_alu (
        .a           (alu_a),
        .b           (alu_b),
        .alu_control (id_ex_alu_control),
        .result      (alu_result),
        .zero        ()                    // unused
    );

    //--------------------------------------------------------------------------
    // Branch comparator (forwarded operands, not the ALU inputs)
    //--------------------------------------------------------------------------
    wire cmp_taken;

    branch_comparator u_cmp (
        .rs1_data     (fwd_rs1),
        .rs2_data     (fwd_rs2),
        .branch_type  (id_ex_branch_type),
        .branch_taken (cmp_taken)
    );

    //--------------------------------------------------------------------------
    // Redirect: valid-qualified, JALR clears bit 0 of the target
    //--------------------------------------------------------------------------
    wire taken_branch = id_ex_valid & id_ex_branch & cmp_taken;
    wire taken_jump   = id_ex_valid & id_ex_jump;

    assign redirect        = taken_branch | taken_jump;
    assign redirect_target = id_ex_jump_reg ? (alu_result & 32'hFFFFFFFE)
                                            : alu_result;

    //--------------------------------------------------------------------------
    // EX/MEM pipeline register (enable = 1, flush = 0)
    //--------------------------------------------------------------------------
    ex_mem_register u_ex_mem (
        .clk            (clk),
        .reset          (reset),
        .enable         (1'b1),
        .flush          (1'b0),

        .pc_plus4_in    (id_ex_pc_plus4),
        .alu_result_in  (alu_result),
        .store_data_in  (fwd_rs2),
        .immediate_in   (id_ex_immediate),

        .rd_addr_in     (id_ex_rd_addr),

        .mem_read_in    (id_ex_mem_read),
        .mem_write_in   (id_ex_mem_write),

        .reg_write_in   (id_ex_reg_write),
        .wb_sel_in      (id_ex_wb_sel),

        .valid_in       (id_ex_valid),

        .pc_plus4_out   (mem_pc_plus4),
        .alu_result_out (mem_alu_result),
        .store_data_out (mem_store_data),
        .immediate_out  (mem_immediate),

        .rd_addr_out    (mem_rd_addr),

        .mem_read_out   (mem_mem_read),
        .mem_write_out  (mem_mem_write),

        .reg_write_out  (mem_reg_write),
        .wb_sel_out     (mem_wb_sel),

        .valid_out      (mem_valid)
    );

endmodule