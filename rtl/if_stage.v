`timescale 1ns / 1ps

//==============================================================================
// Module      : if_stage
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : Instruction Fetch stage wiring. Instantiates program_counter,
//               instruction_memory and if_id_register.
//
// Connections:
//   next_pc = redirect ? redirect_target : pc + 4
//   PC enable      = pc_write | redirect   (a redirect is never lost)
//   IF/ID enable   = if_id_write           (0 holds IF/ID during a stall)
//   IF/ID flush    = redirect              (flush beats enable in IF/ID)
//
// Parameter:
//   INIT_FILE : forwarded to instruction_memory ($readmemh file).
//==============================================================================

module if_stage #(
    parameter INIT_FILE = ""
)(
    input  wire        clk,
    input  wire        reset,

    // Controls from the rest of the pipeline
    input  wire        pc_write,          // from hazard detection unit
    input  wire        if_id_write,       // from hazard detection unit
    input  wire        redirect,          // taken branch / jump (from EX)
    input  wire [31:0] redirect_target,   // target address (from EX)

    // Current fetch PC (for observation and debug)
    output wire [31:0] pc,

    // IF/ID register outputs, passed on to the ID stage
    output wire [31:0] id_pc,
    output wire [31:0] id_pc_plus4,
    output wire [31:0] id_instruction,
    output wire        id_valid
);

    //--------------------------------------------------------------------------
    // PC + 4 and next-PC selection
    //--------------------------------------------------------------------------
    wire [31:0] pc_plus4 = pc + 32'd4;
    wire [31:0] next_pc  = redirect ? redirect_target : pc_plus4;
    wire        pc_enable = pc_write | redirect;

    wire [31:0] fetched_instruction;

    //--------------------------------------------------------------------------
    // Program counter
    //--------------------------------------------------------------------------
    program_counter u_pc (
        .clk     (clk),
        .reset   (reset),
        .enable  (pc_enable),
        .next_pc (next_pc),
        .pc      (pc)
    );

    //--------------------------------------------------------------------------
    // Instruction memory (asynchronous read)
    //--------------------------------------------------------------------------
    instruction_memory #(
        .INIT_FILE (INIT_FILE)
    ) u_imem (
        .address     (pc),
        .instruction (fetched_instruction)
    );

    //--------------------------------------------------------------------------
    // IF/ID pipeline register
    //--------------------------------------------------------------------------
    if_id_register u_if_id (
        .clk             (clk),
        .reset           (reset),
        .enable          (if_id_write),
        .flush           (redirect),

        .pc_in           (pc),
        .pc_plus4_in     (pc_plus4),
        .instruction_in  (fetched_instruction),

        .pc_out          (id_pc),
        .pc_plus4_out    (id_pc_plus4),
        .instruction_out (id_instruction),
        .valid_out       (id_valid)
    );

endmodule