
`timescale 1ns / 1ps

//==============================================================================
// Module      : control_unit
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : Combinational RV32I instruction decoder.
//
// Supported instructions:
//   R-type  : ADD, SUB, AND, OR, XOR, SLT, SLTU
//   I-type  : ADDI, ANDI, ORI, XORI
//   Memory  : LW, SW
//   Branch  : BEQ, BNE, BLT, BGE, BLTU, BGEU
//   Upper   : LUI, AUIPC
//   Jump    : JAL, JALR
//
// Branch comparison is performed by a separate comparator.
// The ALU calculates branch/JAL targets using PC + immediate.
// JALR target bit 0 must be cleared by the datapath.
//==============================================================================

module control_unit (
    input  wire [31:0] instruction,

    output reg         reg_write,
    output reg         mem_read,
    output reg         mem_write,
    output reg         branch,
    output reg         jump,
    output reg         jump_reg,

    output reg  [1:0]  alu_src_a,
    output reg         alu_src_b,
    output reg  [3:0]  alu_control,
    output reg  [2:0]  imm_sel,
    output reg  [1:0]  wb_sel,
    output reg  [2:0]  branch_type,

    output reg         illegal_instr
);

    //--------------------------------------------------------------------------
    // OPCODE DEFINITIONS
    //--------------------------------------------------------------------------

    localparam [6:0] OP_RTYPE  = 7'b0110011;
    localparam [6:0] OP_ITYPE  = 7'b0010011;
    localparam [6:0] OP_LOAD   = 7'b0000011;
    localparam [6:0] OP_STORE  = 7'b0100011;
    localparam [6:0] OP_BRANCH = 7'b1100011;
    localparam [6:0] OP_LUI    = 7'b0110111;
    localparam [6:0] OP_AUIPC  = 7'b0010111;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;

    //--------------------------------------------------------------------------
    // FUNCTION FIELD DEFINITIONS
    //--------------------------------------------------------------------------

    localparam [6:0] F7_NORMAL = 7'b0000000;
    localparam [6:0] F7_ALT    = 7'b0100000;

    localparam [2:0] F3_ADD_SUB = 3'b000;
    localparam [2:0] F3_SLT     = 3'b010;
    localparam [2:0] F3_SLTU    = 3'b011;
    localparam [2:0] F3_XOR     = 3'b100;
    localparam [2:0] F3_OR      = 3'b110;
    localparam [2:0] F3_AND     = 3'b111;

    localparam [2:0] F3_WORD = 3'b010;

    localparam [2:0] F3_BEQ  = 3'b000;
    localparam [2:0] F3_BNE  = 3'b001;
    localparam [2:0] F3_BLT  = 3'b100;
    localparam [2:0] F3_BGE  = 3'b101;
    localparam [2:0] F3_BLTU = 3'b110;
    localparam [2:0] F3_BGEU = 3'b111;

    localparam [2:0] F3_JALR = 3'b000;

    //--------------------------------------------------------------------------
    // ALU CONTROL ENCODINGS (MATCH rtl/alu.v)
    //--------------------------------------------------------------------------

    localparam [3:0] ALU_ADD  = 4'b0000;
    localparam [3:0] ALU_SUB  = 4'b0001;
    localparam [3:0] ALU_AND  = 4'b0010;
    localparam [3:0] ALU_OR   = 4'b0011;
    localparam [3:0] ALU_XOR  = 4'b0100;
    localparam [3:0] ALU_SLT  = 4'b0101;
    localparam [3:0] ALU_SLTU = 4'b0110;

    //--------------------------------------------------------------------------
    // IMMEDIATE SELECT ENCODINGS (MATCH rtl/imm_gen.v)
    //--------------------------------------------------------------------------

    localparam [2:0] IMM_I = 3'b000;
    localparam [2:0] IMM_S = 3'b001;
    localparam [2:0] IMM_B = 3'b010;
    localparam [2:0] IMM_U = 3'b011;
    localparam [2:0] IMM_J = 3'b100;

    //--------------------------------------------------------------------------
    // ALU INPUT A SELECT
    //--------------------------------------------------------------------------

    localparam [1:0] SRC_A_RS1  = 2'b00;
    localparam [1:0] SRC_A_PC   = 2'b01;
    localparam [1:0] SRC_A_ZERO = 2'b10;

    //--------------------------------------------------------------------------
    // ALU INPUT B SELECT
    //--------------------------------------------------------------------------

    localparam SRC_B_RS2 = 1'b0;
    localparam SRC_B_IMM = 1'b1;

    //--------------------------------------------------------------------------
    // WRITE-BACK SELECT
    //--------------------------------------------------------------------------

    localparam [1:0] WB_ALU = 2'b00;
    localparam [1:0] WB_MEM = 2'b01;
    localparam [1:0] WB_PC4 = 2'b10;
    localparam [1:0] WB_IMM = 2'b11;

    //--------------------------------------------------------------------------
    // BRANCH TYPE ENCODINGS
    //--------------------------------------------------------------------------

    localparam [2:0] BR_BEQ  = 3'b000;
    localparam [2:0] BR_BNE  = 3'b001;
    localparam [2:0] BR_BLT  = 3'b010;
    localparam [2:0] BR_BGE  = 3'b011;
    localparam [2:0] BR_BLTU = 3'b100;
    localparam [2:0] BR_BGEU = 3'b101;

    //--------------------------------------------------------------------------
    // INSTRUCTION FIELD EXTRACTION
    //--------------------------------------------------------------------------

    wire [6:0] opcode = instruction[6:0];
    wire [2:0] funct3 = instruction[14:12];
    wire [6:0] funct7 = instruction[31:25];

    //--------------------------------------------------------------------------
    // COMBINATIONAL INSTRUCTION DECODER
    //--------------------------------------------------------------------------

    always @(*) begin

        // Safe defaults: no architectural side effects.

        reg_write     = 1'b0;
        mem_read      = 1'b0;
        mem_write     = 1'b0;
        branch        = 1'b0;
        jump          = 1'b0;
        jump_reg      = 1'b0;

        alu_src_a     = SRC_A_RS1;
        alu_src_b     = SRC_B_RS2;
        alu_control   = ALU_ADD;
        imm_sel       = IMM_I;
        wb_sel        = WB_ALU;
        branch_type   = BR_BEQ;

        illegal_instr = 1'b0;

        case (opcode)

            //==============================================================
            // R-TYPE: ADD, SUB, AND, OR, XOR, SLT, SLTU
            //==============================================================

            OP_RTYPE: begin
                case ({funct7, funct3})

                    {F7_NORMAL, F3_ADD_SUB}: begin
                        reg_write   = 1'b1;
                        alu_control = ALU_ADD;
                    end

                    {F7_ALT, F3_ADD_SUB}: begin
                        reg_write   = 1'b1;
                        alu_control = ALU_SUB;
                    end

                    {F7_NORMAL, F3_AND}: begin
                        reg_write   = 1'b1;
                        alu_control = ALU_AND;
                    end

                    {F7_NORMAL, F3_OR}: begin
                        reg_write   = 1'b1;
                        alu_control = ALU_OR;
                    end

                    {F7_NORMAL, F3_XOR}: begin
                        reg_write   = 1'b1;
                        alu_control = ALU_XOR;
                    end

                    {F7_NORMAL, F3_SLT}: begin
                        reg_write   = 1'b1;
                        alu_control = ALU_SLT;
                    end

                    {F7_NORMAL, F3_SLTU}: begin
                        reg_write   = 1'b1;
                        alu_control = ALU_SLTU;
                    end

                    default: illegal_instr = 1'b1;

                endcase
            end

            //==============================================================
            // I-TYPE: ADDI, ANDI, ORI, XORI
            //==============================================================

            OP_ITYPE: begin
                case (funct3)

                    F3_ADD_SUB: begin
                        reg_write   = 1'b1;
                        alu_src_b   = SRC_B_IMM;
                        imm_sel     = IMM_I;
                        alu_control = ALU_ADD;
                    end

                    F3_AND: begin
                        reg_write   = 1'b1;
                        alu_src_b   = SRC_B_IMM;
                        imm_sel     = IMM_I;
                        alu_control = ALU_AND;
                    end

                    F3_OR: begin
                        reg_write   = 1'b1;
                        alu_src_b   = SRC_B_IMM;
                        imm_sel     = IMM_I;
                        alu_control = ALU_OR;
                    end

                    F3_XOR: begin
                        reg_write   = 1'b1;
                        alu_src_b   = SRC_B_IMM;
                        imm_sel     = IMM_I;
                        alu_control = ALU_XOR;
                    end

                    default: illegal_instr = 1'b1;

                endcase
            end

            //==============================================================
            // LOAD: LW
            //==============================================================

            OP_LOAD: begin
                if (funct3 == F3_WORD) begin
                    reg_write   = 1'b1;
                    mem_read    = 1'b1;
                    alu_src_b   = SRC_B_IMM;
                    imm_sel     = IMM_I;
                    alu_control = ALU_ADD;
                    wb_sel      = WB_MEM;
                end
                else begin
                    illegal_instr = 1'b1;
                end
            end

            //==============================================================
            // STORE: SW
            //==============================================================

            OP_STORE: begin
                if (funct3 == F3_WORD) begin
                    mem_write   = 1'b1;
                    alu_src_b   = SRC_B_IMM;
                    imm_sel     = IMM_S;
                    alu_control = ALU_ADD;
                end
                else begin
                    illegal_instr = 1'b1;
                end
            end

            //==============================================================
            // CONDITIONAL BRANCHES
            //==============================================================

            OP_BRANCH: begin
                case (funct3)

                    F3_BEQ: begin
                        branch      = 1'b1;
                        branch_type = BR_BEQ;
                    end

                    F3_BNE: begin
                        branch      = 1'b1;
                        branch_type = BR_BNE;
                    end

                    F3_BLT: begin
                        branch      = 1'b1;
                        branch_type = BR_BLT;
                    end

                    F3_BGE: begin
                        branch      = 1'b1;
                        branch_type = BR_BGE;
                    end

                    F3_BLTU: begin
                        branch      = 1'b1;
                        branch_type = BR_BLTU;
                    end

                    F3_BGEU: begin
                        branch      = 1'b1;
                        branch_type = BR_BGEU;
                    end

                    default: illegal_instr = 1'b1;

                endcase

                if (!illegal_instr) begin
                    alu_src_a   = SRC_A_PC;
                    alu_src_b   = SRC_B_IMM;
                    alu_control = ALU_ADD;
                    imm_sel     = IMM_B;
                end
            end

            //==============================================================
            // LUI
            //==============================================================

            OP_LUI: begin
                reg_write   = 1'b1;
                alu_src_a   = SRC_A_ZERO;
                alu_src_b   = SRC_B_IMM;
                alu_control = ALU_ADD;
                imm_sel     = IMM_U;
                wb_sel      = WB_IMM;
            end

            //==============================================================
            // AUIPC
            //==============================================================

            OP_AUIPC: begin
                reg_write   = 1'b1;
                alu_src_a   = SRC_A_PC;
                alu_src_b   = SRC_B_IMM;
                alu_control = ALU_ADD;
                imm_sel     = IMM_U;
                wb_sel      = WB_ALU;
            end

            //==============================================================
            // JAL
            //==============================================================

            OP_JAL: begin
                reg_write   = 1'b1;
                jump        = 1'b1;
                alu_src_a   = SRC_A_PC;
                alu_src_b   = SRC_B_IMM;
                alu_control = ALU_ADD;
                imm_sel     = IMM_J;
                wb_sel      = WB_PC4;
            end

            //==============================================================
            // JALR
            //==============================================================

            OP_JALR: begin
                if (funct3 == F3_JALR) begin
                    reg_write   = 1'b1;
                    jump        = 1'b1;
                    jump_reg    = 1'b1;
                    alu_src_a   = SRC_A_RS1;
                    alu_src_b   = SRC_B_IMM;
                    alu_control = ALU_ADD;
                    imm_sel     = IMM_I;
                    wb_sel      = WB_PC4;
                end
                else begin
                    illegal_instr = 1'b1;
                end
            end

            //==============================================================
            // UNSUPPORTED OPCODE
            //==============================================================

            default: begin
                illegal_instr = 1'b1;
            end

        endcase

    end

endmodule
