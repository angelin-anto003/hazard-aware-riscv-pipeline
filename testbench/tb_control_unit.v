
`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_control_unit
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// DUT         : control_unit (rtl/control_unit.v)
// Description : Self-checking Verilog-2001 testbench for the combinational
//               RV32I control unit. No clock is used.
//
// Waveform    : simulations/control_unit.vcd
//==============================================================================

module tb_control_unit;

    //--------------------------------------------------------------------------
    // DUT INPUT AND OUTPUTS
    //--------------------------------------------------------------------------

    reg  [31:0] instruction;

    wire        reg_write;
    wire        mem_read;
    wire        mem_write;
    wire        branch;
    wire        jump;
    wire        jump_reg;
    wire [1:0]  alu_src_a;
    wire        alu_src_b;
    wire [3:0]  alu_control;
    wire [2:0]  imm_sel;
    wire [1:0]  wb_sel;
    wire [2:0]  branch_type;
    wire        illegal_instr;

    //--------------------------------------------------------------------------
    // TESTBENCH CONSTANTS
    //--------------------------------------------------------------------------

    localparam T = 1'b1;
    localparam F = 1'b0;

    // Opcodes
    localparam [6:0] OPC_R      = 7'b0110011;
    localparam [6:0] OPC_I      = 7'b0010011;
    localparam [6:0] OPC_LOAD   = 7'b0000011;
    localparam [6:0] OPC_STORE  = 7'b0100011;
    localparam [6:0] OPC_BRANCH = 7'b1100011;
    localparam [6:0] OPC_LUI    = 7'b0110111;
    localparam [6:0] OPC_AUIPC  = 7'b0010111;
    localparam [6:0] OPC_JAL    = 7'b1101111;
    localparam [6:0] OPC_JALR   = 7'b1100111;

    // ALU input selection
    localparam [1:0] A_RS1  = 2'b00;
    localparam [1:0] A_PC   = 2'b01;
    localparam [1:0] A_ZERO = 2'b10;

    localparam B_RS2 = 1'b0;
    localparam B_IMM = 1'b1;

    // ALU control
    localparam [3:0] C_ADD  = 4'b0000;
    localparam [3:0] C_SUB  = 4'b0001;
    localparam [3:0] C_AND  = 4'b0010;
    localparam [3:0] C_OR   = 4'b0011;
    localparam [3:0] C_XOR  = 4'b0100;
    localparam [3:0] C_SLT  = 4'b0101;
    localparam [3:0] C_SLTU = 4'b0110;

    // Immediate selection
    localparam [2:0] I_I = 3'b000;
    localparam [2:0] I_S = 3'b001;
    localparam [2:0] I_B = 3'b010;
    localparam [2:0] I_U = 3'b011;
    localparam [2:0] I_J = 3'b100;

    // Write-back selection
    localparam [1:0] WB_ALU = 2'b00;
    localparam [1:0] WB_MEM = 2'b01;
    localparam [1:0] WB_PC4 = 2'b10;
    localparam [1:0] WB_IMM = 2'b11;

    // Branch types
    localparam [2:0] BR_EQ  = 3'b000;
    localparam [2:0] BR_NE  = 3'b001;
    localparam [2:0] BR_LT  = 3'b010;
    localparam [2:0] BR_GE  = 3'b011;
    localparam [2:0] BR_LTU = 3'b100;
    localparam [2:0] BR_GEU = 3'b101;

    //--------------------------------------------------------------------------
    // TEST COUNTERS AND TEMPORARY VARIABLES
    //--------------------------------------------------------------------------

    integer total_tests;
    integer passed_tests;
    integer failed_tests;

    integer k;
    integer m;
    integer n;

    reg [4:0]  v_rd;
    reg [4:0]  v_rs1;
    reg [4:0]  v_rs2;

    reg [31:0] tmp32;

    reg [11:0] v_imm12;
    reg [12:0] v_imm13;
    reg [19:0] v_imm20;
    reg [20:0] v_imm21;

    reg [31:0] imm_tab [0:3];
    reg [31:0] u_tab   [0:3];

    reg legal_flag;

    //--------------------------------------------------------------------------
    // DUT INSTANTIATION
    //--------------------------------------------------------------------------

    control_unit uut (
        .instruction   (instruction),
        .reg_write     (reg_write),
        .mem_read      (mem_read),
        .mem_write     (mem_write),
        .branch        (branch),
        .jump          (jump),
        .jump_reg      (jump_reg),
        .alu_src_a     (alu_src_a),
        .alu_src_b     (alu_src_b),
        .alu_control   (alu_control),
        .imm_sel       (imm_sel),
        .wb_sel        (wb_sel),
        .branch_type   (branch_type),
        .illegal_instr (illegal_instr)
    );

    //--------------------------------------------------------------------------
    // WAVEFORM GENERATION
    //--------------------------------------------------------------------------

    initial begin
        $dumpfile("simulations/control_unit.vcd");
        $dumpvars(0, tb_control_unit);
    end

    //--------------------------------------------------------------------------
    // INSTRUCTION ENCODER FUNCTIONS
    //--------------------------------------------------------------------------

    // R-type
    function [31:0] enc_r;
        input [6:0] f7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] f3;
        input [4:0] rd;
        input [6:0] opc;
        begin
            enc_r = {f7, rs2, rs1, f3, rd, opc};
        end
    endfunction

    // I-type
    function [31:0] enc_i;
        input [11:0] imm;
        input [4:0]  rs1;
        input [2:0]  f3;
        input [4:0]  rd;
        input [6:0]  opc;
        begin
            enc_i = {imm, rs1, f3, rd, opc};
        end
    endfunction

    // S-type
    function [31:0] enc_s;
        input [11:0] imm;
        input [4:0]  rs2;
        input [4:0]  rs1;
        input [2:0]  f3;
        begin
            enc_s = {imm[11:5], rs2, rs1, f3, imm[4:0], OPC_STORE};
        end
    endfunction

    // B-type
    function [31:0] enc_b;
        input [12:0] imm;
        input [4:0]  rs2;
        input [4:0]  rs1;
        input [2:0]  f3;
        begin
            enc_b = {
                imm[12], imm[10:5], rs2, rs1,
                f3, imm[4:1], imm[11], OPC_BRANCH
            };
        end
    endfunction

    // U-type
    function [31:0] enc_u;
        input [19:0] imm20;
        input [4:0]  rd;
        input [6:0]  opc;
        begin
            enc_u = {imm20, rd, opc};
        end
    endfunction

    // J-type
    function [31:0] enc_j;
        input [20:0] imm;
        input [4:0]  rd;
        begin
            enc_j = {
                imm[20], imm[10:1], imm[11],
                imm[19:12], rd, OPC_JAL
            };
        end
    endfunction

    //--------------------------------------------------------------------------
    // LEGAL OPCODE CHECK FUNCTION
    //--------------------------------------------------------------------------

    function is_legal_opcode;
        input [6:0] opc;
        begin
            is_legal_opcode =
                (opc == OPC_R)      ||
                (opc == OPC_I)      ||
                (opc == OPC_LOAD)   ||
                (opc == OPC_STORE)  ||
                (opc == OPC_BRANCH) ||
                (opc == OPC_LUI)    ||
                (opc == OPC_AUIPC)  ||
                (opc == OPC_JAL)    ||
                (opc == OPC_JALR);
        end
    endfunction

    //--------------------------------------------------------------------------
    // CORE CHECKING TASK
    // Compares all 13 DUT outputs.
    //--------------------------------------------------------------------------

    task check_all;
        input [319:0] name;
        input [31:0]  instr;

        input e_rw;
        input e_mr;
        input e_mw;
        input e_br;
        input e_jp;
        input e_jr;

        input [1:0] e_asa;
        input       e_asb;
        input [3:0] e_ctl;
        input [2:0] e_imm;
        input [1:0] e_wb;
        input [2:0] e_bt;
        input       e_ill;

        reg [12:0] mm;

        begin
            instruction = instr;
            #2;

            mm = 13'b0;

            if (reg_write     !== e_rw ) mm[0]  = 1'b1;
            if (mem_read      !== e_mr ) mm[1]  = 1'b1;
            if (mem_write     !== e_mw ) mm[2]  = 1'b1;
            if (branch        !== e_br ) mm[3]  = 1'b1;
            if (jump          !== e_jp ) mm[4]  = 1'b1;
            if (jump_reg      !== e_jr ) mm[5]  = 1'b1;
            if (alu_src_a     !== e_asa) mm[6]  = 1'b1;
            if (alu_src_b     !== e_asb) mm[7]  = 1'b1;
            if (alu_control   !== e_ctl) mm[8]  = 1'b1;
            if (imm_sel       !== e_imm) mm[9]  = 1'b1;
            if (wb_sel        !== e_wb ) mm[10] = 1'b1;
            if (branch_type   !== e_bt ) mm[11] = 1'b1;
            if (illegal_instr !== e_ill) mm[12] = 1'b1;

            total_tests = total_tests + 1;

            if (mm == 13'b0) begin
                passed_tests = passed_tests + 1;
                $display("[PASS] %0s | instr=%h", name, instr);
            end
            else begin
                failed_tests = failed_tests + 1;

                $display("[FAIL] %0s | instr=%h", name, instr);

                if (mm[0])  $display(" reg_write     actual=%b expected=%b", reg_write, e_rw);
                if (mm[1])  $display(" mem_read      actual=%b expected=%b", mem_read, e_mr);
                if (mm[2])  $display(" mem_write     actual=%b expected=%b", mem_write, e_mw);
                if (mm[3])  $display(" branch        actual=%b expected=%b", branch, e_br);
                if (mm[4])  $display(" jump          actual=%b expected=%b", jump, e_jp);
                if (mm[5])  $display(" jump_reg      actual=%b expected=%b", jump_reg, e_jr);
                if (mm[6])  $display(" alu_src_a     actual=%b expected=%b", alu_src_a, e_asa);
                if (mm[7])  $display(" alu_src_b     actual=%b expected=%b", alu_src_b, e_asb);
                if (mm[8])  $display(" alu_control   actual=%b expected=%b", alu_control, e_ctl);
                if (mm[9])  $display(" imm_sel       actual=%b expected=%b", imm_sel, e_imm);
                if (mm[10]) $display(" wb_sel        actual=%b expected=%b", wb_sel, e_wb);
                if (mm[11]) $display(" branch_type   actual=%b expected=%b", branch_type, e_bt);
                if (mm[12]) $display(" illegal_instr actual=%b expected=%b", illegal_instr, e_ill);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // VALID INSTRUCTION TASK
    //--------------------------------------------------------------------------

    task check_valid;
        input [319:0] name;
        input [31:0] instr;

        input e_rw;
        input e_mr;
        input e_mw;
        input e_br;
        input e_jp;
        input e_jr;

        input [1:0] e_asa;
        input       e_asb;
        input [3:0] e_ctl;
        input [2:0] e_imm;
        input [1:0] e_wb;
        input [2:0] e_bt;

        begin
            check_all(
                name, instr,
                e_rw, e_mr, e_mw, e_br, e_jp, e_jr,
                e_asa, e_asb, e_ctl, e_imm, e_wb, e_bt,
                1'b0
            );
        end
    endtask

    //--------------------------------------------------------------------------
    // ILLEGAL INSTRUCTION TASK
    //--------------------------------------------------------------------------

    task check_illegal;
        input [319:0] name;
        input [31:0] instr;

        begin
            check_all(
                name, instr,
                F, F, F, F, F, F,
                A_RS1, B_RS2, C_ADD,
                I_I, WB_ALU, BR_EQ,
                1'b1
            );
        end
    endtask

    //--------------------------------------------------------------------------
    // MAIN TEST SEQUENCE
    //--------------------------------------------------------------------------

    initial begin

        instruction  = 32'h00000013;
        total_tests  = 0;
        passed_tests = 0;
        failed_tests = 0;

        imm_tab[0] = 32'h00000001;
        imm_tab[1] = 32'h000007FF;
        imm_tab[2] = 32'h00000800;
        imm_tab[3] = 32'h00000ABC;

        u_tab[0] = 32'h00000000;
        u_tab[1] = 32'h000FFFFF;
        u_tab[2] = 32'h00012345;
        u_tab[3] = 32'h000AAAAA;

        #1;

        $display("==============================================================");
        $display(" CONTROL UNIT SELF-CHECKING TESTBENCH STARTED");
        $display("==============================================================");

        //======================================================================
        // 1. REAL MACHINE-CODE INSTRUCTIONS
        //======================================================================

        $display("--- 1. Real machine-code words ---");

        check_valid("NOP",          32'h00000013, T,F,F,F,F,F, A_RS1,B_IMM,C_ADD,I_I,WB_ALU,BR_EQ);
        check_valid("ADD",          32'h002081B3, T,F,F,F,F,F, A_RS1,B_RS2,C_ADD,I_I,WB_ALU,BR_EQ);
        check_valid("SUB",          32'h402081B3, T,F,F,F,F,F, A_RS1,B_RS2,C_SUB,I_I,WB_ALU,BR_EQ);
        check_valid("ADDI",         32'h00500093, T,F,F,F,F,F, A_RS1,B_IMM,C_ADD,I_I,WB_ALU,BR_EQ);
        check_valid("LW",           32'h00812283, T,T,F,F,F,F, A_RS1,B_IMM,C_ADD,I_I,WB_MEM,BR_EQ);
        check_valid("SW",           32'h00512423, F,F,T,F,F,F, A_RS1,B_IMM,C_ADD,I_S,WB_ALU,BR_EQ);
        check_valid("BEQ",          32'hFE000EE3, F,F,F,T,F,F, A_PC,B_IMM,C_ADD,I_B,WB_ALU,BR_EQ);
        check_valid("LUI",          32'h123452B7, T,F,F,F,F,F, A_ZERO,B_IMM,C_ADD,I_U,WB_IMM,BR_EQ);
        check_valid("AUIPC",        32'h00000097, T,F,F,F,F,F, A_PC,B_IMM,C_ADD,I_U,WB_ALU,BR_EQ);
        check_valid("JAL",          32'h008000EF, T,F,F,F,T,F, A_PC,B_IMM,C_ADD,I_J,WB_PC4,BR_EQ);
        check_valid("JALR",         32'h00008067, T,F,F,F,T,T, A_RS1,B_IMM,C_ADD,I_I,WB_PC4,BR_EQ);

        //======================================================================
        // 2. LEGAL INSTRUCTIONS WITH DIFFERENT FIELD VALUES
        //======================================================================

        $display("--- 2. Legal instruction field variants ---");

        for (k = 0; k < 4; k = k + 1) begin

            v_rd    = 5'd1  + k * 7;
            v_rs1   = 5'd2  + k * 9;
            v_rs2   = 5'd31 - k * 6;

            tmp32   = imm_tab[k];
            v_imm12 = tmp32[11:0];
            v_imm13 = {tmp32[11:0], 1'b0};

            tmp32   = u_tab[k];
            v_imm20 = tmp32[19:0];
            v_imm21 = {tmp32[19:0], 1'b0};

            // R-type
            check_valid("R: ADD", enc_r(7'b0000000,v_rs2,v_rs1,3'b000,v_rd,OPC_R), T,F,F,F,F,F,A_RS1,B_RS2,C_ADD,I_I,WB_ALU,BR_EQ);
            check_valid("R: SUB", enc_r(7'b0100000,v_rs2,v_rs1,3'b000,v_rd,OPC_R), T,F,F,F,F,F,A_RS1,B_RS2,C_SUB,I_I,WB_ALU,BR_EQ);
            check_valid("R: AND", enc_r(7'b0000000,v_rs2,v_rs1,3'b111,v_rd,OPC_R), T,F,F,F,F,F,A_RS1,B_RS2,C_AND,I_I,WB_ALU,BR_EQ);
            check_valid("R: OR",  enc_r(7'b0000000,v_rs2,v_rs1,3'b110,v_rd,OPC_R), T,F,F,F,F,F,A_RS1,B_RS2,C_OR,I_I,WB_ALU,BR_EQ);
            check_valid("R: XOR", enc_r(7'b0000000,v_rs2,v_rs1,3'b100,v_rd,OPC_R), T,F,F,F,F,F,A_RS1,B_RS2,C_XOR,I_I,WB_ALU,BR_EQ);
            check_valid("R: SLT", enc_r(7'b0000000,v_rs2,v_rs1,3'b010,v_rd,OPC_R), T,F,F,F,F,F,A_RS1,B_RS2,C_SLT,I_I,WB_ALU,BR_EQ);
            check_valid("R: SLTU",enc_r(7'b0000000,v_rs2,v_rs1,3'b011,v_rd,OPC_R), T,F,F,F,F,F,A_RS1,B_RS2,C_SLTU,I_I,WB_ALU,BR_EQ);

            // I-type arithmetic
            check_valid("I: ADDI",enc_i(v_imm12,v_rs1,3'b000,v_rd,OPC_I),T,F,F,F,F,F,A_RS1,B_IMM,C_ADD,I_I,WB_ALU,BR_EQ);
            check_valid("I: ANDI",enc_i(v_imm12,v_rs1,3'b111,v_rd,OPC_I),T,F,F,F,F,F,A_RS1,B_IMM,C_AND,I_I,WB_ALU,BR_EQ);
            check_valid("I: ORI", enc_i(v_imm12,v_rs1,3'b110,v_rd,OPC_I),T,F,F,F,F,F,A_RS1,B_IMM,C_OR,I_I,WB_ALU,BR_EQ);
            check_valid("I: XORI",enc_i(v_imm12,v_rs1,3'b100,v_rd,OPC_I),T,F,F,F,F,F,A_RS1,B_IMM,C_XOR,I_I,WB_ALU,BR_EQ);

            // Memory
            check_valid("M: LW",enc_i(v_imm12,v_rs1,3'b010,v_rd,OPC_LOAD),T,T,F,F,F,F,A_RS1,B_IMM,C_ADD,I_I,WB_MEM,BR_EQ);
            check_valid("M: SW",enc_s(v_imm12,v_rs2,v_rs1,3'b010),F,F,T,F,F,F,A_RS1,B_IMM,C_ADD,I_S,WB_ALU,BR_EQ);

            // Branches
            check_valid("B: BEQ", enc_b(v_imm13,v_rs2,v_rs1,3'b000),F,F,F,T,F,F,A_PC,B_IMM,C_ADD,I_B,WB_ALU,BR_EQ);
            check_valid("B: BNE", enc_b(v_imm13,v_rs2,v_rs1,3'b001),F,F,F,T,F,F,A_PC,B_IMM,C_ADD,I_B,WB_ALU,BR_NE);
            check_valid("B: BLT", enc_b(v_imm13,v_rs2,v_rs1,3'b100),F,F,F,T,F,F,A_PC,B_IMM,C_ADD,I_B,WB_ALU,BR_LT);
            check_valid("B: BGE", enc_b(v_imm13,v_rs2,v_rs1,3'b101),F,F,F,T,F,F,A_PC,B_IMM,C_ADD,I_B,WB_ALU,BR_GE);
            check_valid("B: BLTU",enc_b(v_imm13,v_rs2,v_rs1,3'b110),F,F,F,T,F,F,A_PC,B_IMM,C_ADD,I_B,WB_ALU,BR_LTU);
            check_valid("B: BGEU",enc_b(v_imm13,v_rs2,v_rs1,3'b111),F,F,F,T,F,F,A_PC,B_IMM,C_ADD,I_B,WB_ALU,BR_GEU);

            // Upper immediate
            check_valid("U: LUI",enc_u(v_imm20,v_rd,OPC_LUI),T,F,F,F,F,F,A_ZERO,B_IMM,C_ADD,I_U,WB_IMM,BR_EQ);
            check_valid("U: AUIPC",enc_u(v_imm20,v_rd,OPC_AUIPC),T,F,F,F,F,F,A_PC,B_IMM,C_ADD,I_U,WB_ALU,BR_EQ);

            // Jumps
            check_valid("J: JAL",enc_j(v_imm21,v_rd),T,F,F,F,T,F,A_PC,B_IMM,C_ADD,I_J,WB_PC4,BR_EQ);
            check_valid("J: JALR",enc_i(v_imm12,v_rs1,3'b000,v_rd,OPC_JALR),T,F,F,F,T,T,A_RS1,B_IMM,C_ADD,I_I,WB_PC4,BR_EQ);

        end

        // Extreme field values
        check_valid("X: LUI all ones",enc_u(20'hFFFFF,5'd31,OPC_LUI),T,F,F,F,F,F,A_ZERO,B_IMM,C_ADD,I_U,WB_IMM,BR_EQ);
        check_valid("X: AUIPC all ones",enc_u(20'hFFFFF,5'd31,OPC_AUIPC),T,F,F,F,F,F,A_PC,B_IMM,C_ADD,I_U,WB_ALU,BR_EQ);
        check_valid("X: JAL all ones",enc_j(21'h1FFFFF,5'd31),T,F,F,F,T,F,A_PC,B_IMM,C_ADD,I_J,WB_PC4,BR_EQ);
        check_valid("X: ADDI imm -1",enc_i(12'hFFF,5'd31,3'b000,5'd31,OPC_I),T,F,F,F,F,F,A_RS1,B_IMM,C_ADD,I_I,WB_ALU,BR_EQ);
        check_valid("X: ADDI imm bit30",enc_i(12'h400,5'd1,3'b000,5'd2,OPC_I),T,F,F,F,F,F,A_RS1,B_IMM,C_ADD,I_I,WB_ALU,BR_EQ);

        //======================================================================
        // 3. ILLEGAL R-TYPE INSTRUCTIONS
        //======================================================================

        $display("--- 3. Illegal R-type ---");

        check_illegal("R: SLL",32'h003110B3);
        check_illegal("R: MUL",32'h023100B3);
        check_illegal("R: SRL",enc_r(7'b0000000,5'd3,5'd2,3'b101,5'd1,OPC_R));
        check_illegal("R: SRA",enc_r(7'b0100000,5'd3,5'd2,3'b101,5'd1,OPC_R));

        check_illegal("R: AND wrong funct7",enc_r(7'b0100000,5'd3,5'd2,3'b111,5'd1,OPC_R));
        check_illegal("R: OR wrong funct7",enc_r(7'b0100000,5'd3,5'd2,3'b110,5'd1,OPC_R));
        check_illegal("R: XOR wrong funct7",enc_r(7'b0100000,5'd3,5'd2,3'b100,5'd1,OPC_R));
        check_illegal("R: SLT wrong funct7",enc_r(7'b0100000,5'd3,5'd2,3'b010,5'd1,OPC_R));
        check_illegal("R: SLTU wrong funct7",enc_r(7'b0100000,5'd3,5'd2,3'b011,5'd1,OPC_R));

        check_illegal("R: ADD wrong funct7 1",enc_r(7'b0000001,5'd3,5'd2,3'b000,5'd1,OPC_R));
        check_illegal("R: ADD wrong funct7 2",enc_r(7'b1111111,5'd3,5'd2,3'b000,5'd1,OPC_R));
        check_illegal("R: SUB wrong funct7 1",enc_r(7'b0100001,5'd3,5'd2,3'b000,5'd1,OPC_R));
        check_illegal("R: SUB wrong funct7 2",enc_r(7'b0000010,5'd3,5'd2,3'b000,5'd1,OPC_R));

        // Representative funct7/funct3 sweep
        for (m = 0; m < 5; m = m + 1) begin
            for (n = 0; n < 8; n = n + 1) begin

                case (m)
                    0: tmp32 = 32'h00;
                    1: tmp32 = 32'h20;
                    2: tmp32 = 32'h01;
                    3: tmp32 = 32'h7F;
                    default: tmp32 = 32'h21;
                endcase

                legal_flag =
                    ((m == 0) && (n != 1) && (n != 5)) ||
                    ((m == 1) && (n == 0));

                if (!legal_flag)
                    check_illegal(
                        "R: funct7/funct3 sweep",
                        enc_r(tmp32[6:0],5'd7,5'd9,n[2:0],5'd11,OPC_R)
                    );

            end
        end

        //======================================================================
        // 4. ILLEGAL I-TYPE ARITHMETIC
        //======================================================================

        $display("--- 4. Illegal I-type ---");

        check_illegal("I: SLLI",32'h00311093);
        check_illegal("I: SLTI",32'h00312093);
        check_illegal("I: SRAI",32'h40315093);

        for (k = 0; k < 4; k = k + 1) begin
            tmp32 = imm_tab[k];
            v_imm12 = tmp32[11:0];

            check_illegal("I: funct3 001",enc_i(v_imm12,5'd2,3'b001,5'd1,OPC_I));
            check_illegal("I: funct3 010",enc_i(v_imm12,5'd2,3'b010,5'd1,OPC_I));
            check_illegal("I: funct3 011",enc_i(v_imm12,5'd2,3'b011,5'd1,OPC_I));
            check_illegal("I: funct3 101",enc_i(v_imm12,5'd2,3'b101,5'd1,OPC_I));
        end

        //======================================================================
        // 5. ILLEGAL LOAD / STORE
        //======================================================================

        $display("--- 5. Illegal load/store ---");

        check_illegal("L: LB",32'h00010083);
        check_illegal("L: LBU",32'h00014083);
        check_illegal("S: SB",32'h00110023);

        for (n = 0; n < 8; n = n + 1) begin
            if (n != 2) begin
                check_illegal("L: invalid funct3",
                    enc_i(12'h010,5'd2,n[2:0],5'd1,OPC_LOAD));

                check_illegal("S: invalid funct3",
                    enc_s(12'h010,5'd1,5'd2,n[2:0]));
            end
        end

        //======================================================================
        // 6. RESERVED BRANCH FUNCT3
        //======================================================================

        $display("--- 6. Reserved branch funct3 ---");

        check_illegal("B: reserved funct3 010",enc_b(13'h0010,5'd2,5'd1,3'b010));
        check_illegal("B: reserved funct3 011",enc_b(13'h0010,5'd2,5'd1,3'b011));
        check_illegal("B: reserved 010 negative",enc_b(13'h1FFC,5'd9,5'd8,3'b010));
        check_illegal("B: reserved 011 negative",enc_b(13'h1FFC,5'd9,5'd8,3'b011));

        //======================================================================
        // 7. INVALID JALR FUNCT3
        //======================================================================

        $display("--- 7. Invalid JALR funct3 ---");

        for (n = 1; n < 8; n = n + 1) begin
            check_illegal(
                "JALR: invalid funct3",
                enc_i(12'h004,5'd1,n[2:0],5'd1,OPC_JALR)
            );
        end

        //======================================================================
        // 8. UNSUPPORTED OPCODES
        //======================================================================

        $display("--- 8. Unsupported opcodes ---");

        check_illegal("OP: all zero",32'h00000000);
        check_illegal("OP: all ones",32'hFFFFFFFF);
        check_illegal("OP: opcode 0000000",{25'h0AAAAAA,7'b0000000});
        check_illegal("OP: opcode 1111111",{25'h0555555,7'b1111111});
        check_illegal("OP: ECALL",32'h00000073);
        check_illegal("OP: EBREAK",32'h00100073);
        check_illegal("OP: FENCE",32'h0FF0000F);

        check_illegal("OP: FLW-like",
            enc_i(12'h010,5'd2,3'b010,5'd1,7'b0000111));

        check_illegal("OP: FP",
            enc_r(7'b0000000,5'd3,5'd2,3'b000,5'd1,7'b1010011));

        check_illegal("OP: AMO",
            enc_r(7'b0000100,5'd3,5'd2,3'b010,5'd1,7'b0101111));

        check_illegal("OP: MISC-MEM",
            enc_i(12'h000,5'd0,3'b001,5'd0,7'b0001111));

        check_illegal("OP: compressed-like",32'h00004001);

        // All 128 opcode values, with two upper-bit patterns
        for (m = 0; m < 128; m = m + 1) begin
            if (!is_legal_opcode(m[6:0])) begin

                check_illegal(
                    "OP: opcode sweep pattern 0",
                    {25'h0000000,m[6:0]}
                );

                check_illegal(
                    "OP: opcode sweep pattern 1",
                    {25'h1FFFFFF,m[6:0]}
                );

            end
        end

        //======================================================================
        // 9. COMBINATIONAL / BACK-TO-BACK TESTS
        //======================================================================

        $display("--- 9. Combinational behaviour ---");

        check_valid("C1: LW",32'h00812283,T,T,F,F,F,F,A_RS1,B_IMM,C_ADD,I_I,WB_MEM,BR_EQ);
        check_illegal("C2: illegal after LW",32'h00000000);
        check_valid("C3: SW after illegal",32'h00512423,F,F,T,F,F,F,A_RS1,B_IMM,C_ADD,I_S,WB_ALU,BR_EQ);
        check_valid("C4: BEQ after SW",32'hFE000EE3,F,F,F,T,F,F,A_PC,B_IMM,C_ADD,I_B,WB_ALU,BR_EQ);
        check_valid("C5: JAL after BEQ",32'h008000EF,T,F,F,F,T,F,A_PC,B_IMM,C_ADD,I_J,WB_PC4,BR_EQ);
        check_valid("C6: JALR after JAL",32'h00008067,T,F,F,F,T,T,A_RS1,B_IMM,C_ADD,I_I,WB_PC4,BR_EQ);
        check_illegal("C7: illegal after JALR",32'hFFFFFFFF);
        check_valid("C8: LUI after illegal",32'h123452B7,T,F,F,F,F,F,A_ZERO,B_IMM,C_ADD,I_U,WB_IMM,BR_EQ);
        check_valid("C9: ADD after LUI",32'h002081B3,T,F,F,F,F,F,A_RS1,B_RS2,C_ADD,I_I,WB_ALU,BR_EQ);
        check_valid("C10: SUB after ADD",32'h402081B3,T,F,F,F,F,F,A_RS1,B_RS2,C_SUB,I_I,WB_ALU,BR_EQ);
        check_valid("C11: ADD after SUB",32'h002081B3,T,F,F,F,F,F,A_RS1,B_RS2,C_ADD,I_I,WB_ALU,BR_EQ);
        check_illegal("C12: invalid ADD",32'h022081B3);
        check_valid("C13: ADD again",32'h002081B3,T,F,F,F,F,F,A_RS1,B_RS2,C_ADD,I_I,WB_ALU,BR_EQ);

        // Branch condition cycling
        check_valid("C14: BEQ",enc_b(13'h0008,5'd2,5'd1,3'b000),F,F,F,T,F,F,A_PC,B_IMM,C_ADD,I_B,WB_ALU,BR_EQ);
        check_valid("C15: BGEU",enc_b(13'h0008,5'd2,5'd1,3'b111),F,F,F,T,F,F,A_PC,B_IMM,C_ADD,I_B,WB_ALU,BR_GEU);
        check_valid("C16: BNE",enc_b(13'h0008,5'd2,5'd1,3'b001),F,F,F,T,F,F,A_PC,B_IMM,C_ADD,I_B,WB_ALU,BR_NE);
        check_valid("C17: BLTU",enc_b(13'h0008,5'd2,5'd1,3'b110),F,F,F,T,F,F,A_PC,B_IMM,C_ADD,I_B,WB_ALU,BR_LTU);
        check_valid("C18: BLT",enc_b(13'h0008,5'd2,5'd1,3'b100),F,F,F,T,F,F,A_PC,B_IMM,C_ADD,I_B,WB_ALU,BR_LT);
        check_valid("C19: BGE",enc_b(13'h0008,5'd2,5'd1,3'b101),F,F,F,T,F,F,A_PC,B_IMM,C_ADD,I_B,WB_ALU,BR_GE);
        check_illegal("C20: reserved branch",enc_b(13'h0008,5'd2,5'd1,3'b010));

        // Rapid input changes
        instruction = 32'h00812283; #1;
        instruction = 32'h00512423; #1;
        instruction = 32'h008000EF; #1;
        instruction = 32'h00000000; #1;

        check_valid("C21: rapid changes ADDI",
            32'h00500093,T,F,F,F,F,F,A_RS1,B_IMM,C_ADD,I_I,WB_ALU,BR_EQ);

        // Opcode-only changes
        for (k = 0; k < 9; k = k + 1) begin

            case (k)
                0: tmp32 = {25'h0000000,OPC_R};
                1: tmp32 = {25'h0000000,OPC_I};
                2: tmp32 = {25'h0000000,OPC_LOAD};
                3: tmp32 = {25'h0000000,OPC_STORE};
                4: tmp32 = {25'h0000000,OPC_BRANCH};
                5: tmp32 = {25'h0000000,OPC_LUI};
                6: tmp32 = {25'h0000000,OPC_AUIPC};
                7: tmp32 = {25'h0000000,OPC_JAL};
                default: tmp32 = {25'h0000000,OPC_JALR};
            endcase

            case (k)
                0: check_valid("C22: R ADD",tmp32,T,F,F,F,F,F,A_RS1,B_RS2,C_ADD,I_I,WB_ALU,BR_EQ);
                1: check_valid("C22: I ADDI",tmp32,T,F,F,F,F,F,A_RS1,B_IMM,C_ADD,I_I,WB_ALU,BR_EQ);
                2: check_illegal("C22: LOAD LB",tmp32);
                3: check_illegal("C22: STORE SB",tmp32);
                4: check_valid("C22: BRANCH",tmp32,F,F,F,T,F,F,A_PC,B_IMM,C_ADD,I_B,WB_ALU,BR_EQ);
                5: check_valid("C22: LUI",tmp32,T,F,F,F,F,F,A_ZERO,B_IMM,C_ADD,I_U,WB_IMM,BR_EQ);
                6: check_valid("C22: AUIPC",tmp32,T,F,F,F,F,F,A_PC,B_IMM,C_ADD,I_U,WB_ALU,BR_EQ);
                7: check_valid("C22: JAL",tmp32,T,F,F,F,T,F,A_PC,B_IMM,C_ADD,I_J,WB_PC4,BR_EQ);
                default: check_valid("C22: JALR",tmp32,T,F,F,F,T,T,A_RS1,B_IMM,C_ADD,I_I,WB_PC4,BR_EQ);
            endcase

        end

        //======================================================================
        // FINAL SUMMARY
        //======================================================================

        #10;

        $display("==============================================================");
        $display(" CONTROL UNIT VERIFICATION SUMMARY");
        $display("==============================================================");

        $display(" Total Tests : %0d",total_tests);
        $display(" Passed      : %0d",passed_tests);
        $display(" Failed      : %0d",failed_tests);

        $display("==============================================================");

        if (failed_tests == 0)
            $display("CONTROL UNIT VERIFICATION PASSED");
        else
            $display("CONTROL UNIT VERIFICATION FAILED");

        $finish;

    end

endmodule
