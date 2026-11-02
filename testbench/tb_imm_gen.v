
`timescale 1ns / 1ps

//==============================================================================
// Module      : tb_imm_gen
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// DUT         : imm_gen
// Description : Self-checking verification environment for the RV32I
//               Immediate Generator.
//
// Verification Features:
//   - I-type, S-type, B-type, U-type and J-type immediate formats
//   - Positive and negative immediate values
//   - Minimum and maximum immediate boundaries
//   - Individual immediate-bit verification
//   - Independent instruction encoding functions
//   - Reference sign-extension function
//   - Invalid selector verification
//   - Combinational behaviour verification
//   - Automated PASS/FAIL reporting
//
// Immediate Selector:
//   000 : I-type
//   001 : S-type
//   010 : B-type
//   011 : U-type
//   100 : J-type
//   101-111 : Invalid
//
// Timing:
//   - Purely combinational DUT
//   - No clock or reset required
//   - 5 ns settling time after input changes
//
// Waveform:
//   simulations/imm_gen.vcd
//
// Note:
//   Run simulation from the project root directory.
//==============================================================================

module tb_imm_gen;

    //--------------------------------------------------------------------------
    // Immediate Format Selectors
    //--------------------------------------------------------------------------

    localparam [2:0] SEL_I = 3'b000;
    localparam [2:0] SEL_S = 3'b001;
    localparam [2:0] SEL_B = 3'b010;
    localparam [2:0] SEL_U = 3'b011;
    localparam [2:0] SEL_J = 3'b100;

    //--------------------------------------------------------------------------
    // DUT Inputs and Outputs
    //--------------------------------------------------------------------------

    reg  [31:0] instruction;
    reg  [2:0]  imm_sel;

    wire [31:0] immediate;

    //--------------------------------------------------------------------------
    // Verification Counters
    //--------------------------------------------------------------------------

    integer total_tests;
    integer passed_tests;
    integer failed_tests;

    integer k;

    //--------------------------------------------------------------------------
    // Temporary Verification Variables
    //--------------------------------------------------------------------------

    reg [31:0] tmp_imm;
    reg [31:0] tmp_exp;
    reg [31:0] tmp_instr;

    //--------------------------------------------------------------------------
    // DUT Instantiation
    //--------------------------------------------------------------------------

    imm_gen uut (
        .instruction (instruction),
        .imm_sel     (imm_sel),
        .immediate   (immediate)
    );

    //--------------------------------------------------------------------------
    // Waveform Generation
    //--------------------------------------------------------------------------

    initial begin
        $dumpfile("simulations/imm_gen.vcd");
        $dumpvars(0, tb_imm_gen);
    end

    //==========================================================================
    // FUNCTION 1: Reference Sign Extension
    //
    // Independently sign-extends an n-bit two's-complement value to 32 bits.
    //==========================================================================

    function [31:0] ref_sext;
        input [31:0] val;
        input integer nbits;

        begin
            if (val[nbits-1])
                ref_sext = val | (32'hFFFFFFFF << nbits);
            else
                ref_sext = val & ~(32'hFFFFFFFF << nbits);
        end
    endfunction

    //==========================================================================
    // FUNCTION 2: I-type Instruction Encoder
    //
    // Format:
    //   imm[11:0] | rs1 | funct3 | rd | opcode
    //==========================================================================

    function [31:0] enc_i;
        input [31:0] imm;

        begin
            enc_i = {
                imm[11:0],
                5'b01010,
                3'b101,
                5'b10101,
                7'b0010011
            };
        end
    endfunction

    //==========================================================================
    // FUNCTION 3: S-type Instruction Encoder
    //
    // Format:
    //   imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
    //==========================================================================

    function [31:0] enc_s;
        input [31:0] imm;

        begin
            enc_s = {
                imm[11:5],
                5'b11011,
                5'b01110,
                3'b010,
                imm[4:0],
                7'b0100011
            };
        end
    endfunction

    //==========================================================================
    // FUNCTION 4: B-type Instruction Encoder
    //
    // Format:
    //   imm[12] | imm[10:5] | rs2 | rs1 | funct3 |
    //   imm[4:1] | imm[11] | opcode
    //==========================================================================

    function [31:0] enc_b;
        input [31:0] imm;

        begin
            enc_b = {
                imm[12],
                imm[10:5],
                5'b10110,
                5'b01101,
                3'b001,
                imm[4:1],
                imm[11],
                7'b1100011
            };
        end
    endfunction

    //==========================================================================
    // FUNCTION 5: U-type Instruction Encoder
    //
    // Format:
    //   imm[31:12] | rd | opcode
    //==========================================================================

    function [31:0] enc_u;
        input [31:0] imm;

        begin
            enc_u = {
                imm[31:12],
                5'b11001,
                7'b0110111
            };
        end
    endfunction

    //==========================================================================
    // FUNCTION 6: J-type Instruction Encoder
    //
    // Format:
    //   imm[20] | imm[10:1] | imm[11] | imm[19:12] | rd | opcode
    //==========================================================================

    function [31:0] enc_j;
        input [31:0] imm;

        begin
            enc_j = {
                imm[20],
                imm[10:1],
                imm[11],
                imm[19:12],
                5'b00111,
                7'b1101111
            };
        end
    endfunction

    //==========================================================================
    // TASK 1: Immediate Value Verification
    //
    // Applies an instruction and selector, waits for combinational settling,
    // and compares the DUT output against the expected result.
    // Uses case inequality to detect X and Z values.
    //==========================================================================

    task check_imm;
        input [319:0] name;
        input [31:0]  instr;
        input [2:0]   sel;
        input [31:0]  expected;

        begin
            instruction = instr;
            imm_sel     = sel;

            #5;

            total_tests = total_tests + 1;

            if (immediate !== expected) begin

                failed_tests = failed_tests + 1;

                $display(
                    "[FAIL] %0s | Instruction = %h | Selector = %b | Actual = %h | Expected = %h",
                    name, instr, sel, immediate, expected
                );

            end
            else begin

                passed_tests = passed_tests + 1;

                $display(
                    "[PASS] %0s | Instruction = %h | Selector = %b | Immediate = %h",
                    name, instr, sel, immediate
                );

            end
        end
    endtask

    //==========================================================================
    // TASK 2: Immediate Property Verification
    //
    // Checks individual output properties such as:
    //   - B-type and J-type bit 0 must be zero.
    //   - U-type lower 12 bits must be zero.
    //   - Sign-extension bits must be correct.
    //==========================================================================

    task check_prop;
        input [319:0] name;
        input         ok;

        begin
            total_tests = total_tests + 1;

            if (ok !== 1'b1) begin

                failed_tests = failed_tests + 1;

                $display(
                    "[FAIL] %0s | Immediate = %h",
                    name, immediate
                );

            end
            else begin

                passed_tests = passed_tests + 1;

                $display(
                    "[PASS] %0s | Immediate = %h",
                    name, immediate
                );

            end
        end
    endtask

    //==========================================================================
    // MAIN TEST SEQUENCE
    //==========================================================================

    initial begin

        //----------------------------------------------------------------------
        // Initialisation
        //----------------------------------------------------------------------

        instruction  = 32'd0;
        imm_sel      = SEL_I;

        total_tests  = 0;
        passed_tests = 0;
        failed_tests = 0;

        #1;

        $display("==============================================================");
        $display("       IMMGEN SELF-CHECKING TESTBENCH");
        $display("==============================================================");

        //======================================================================
        // A. I-TYPE IMMEDIATE VERIFICATION
        //======================================================================

        $display("\n--- A. I-type Immediate Verification ---");

        check_imm("A1: I-type +1",
                  enc_i(32'd1), SEL_I, 32'h00000001);

        check_imm("A2: I-type +100",
                  enc_i(32'd100), SEL_I, 32'h00000064);

        check_imm("A3: I-type zero",
                  enc_i(32'd0), SEL_I, 32'h00000000);

        check_imm("A4: I-type -1",
                  enc_i(-1), SEL_I, 32'hFFFFFFFF);

        check_imm("A5: I-type -5",
                  enc_i(-5), SEL_I, 32'hFFFFFFFB);

        check_imm("A6: I-type maximum +2047",
                  enc_i(32'd2047), SEL_I, 32'h000007FF);

        check_imm("A7: I-type minimum -2048",
                  enc_i(-2048), SEL_I, 32'hFFFFF800);

        check_imm("A8: I-type positive 0x555",
                  enc_i(32'h555), SEL_I, 32'h00000555);

        check_imm("A9: I-type negative 0x556",
                  enc_i(-32'sh556), SEL_I, 32'hFFFFFAAA);

        // Real instruction: addi x1, x0, -1
        // Machine code: 0xFFF00093

        check_imm("A10: ADDI x1, x0, -1",
                  32'hFFF00093, SEL_I, 32'hFFFFFFFF);

        // Real instruction: addi x2, x0, 5
        // Machine code: 0x00500113

        check_imm("A11: ADDI x2, x0, 5",
                  32'h00500113, SEL_I, 32'h00000005);

        // Individual I-type immediate bit verification

        for (k = 0; k < 12; k = k + 1) begin

            tmp_imm   = 32'd1 << k;
            tmp_exp   = ref_sext(tmp_imm, 12);
            tmp_instr = enc_i(tmp_imm);

            check_imm("A12: I-type single-bit sweep",
                      tmp_instr, SEL_I, tmp_exp);

        end

        //======================================================================
        // B. S-TYPE IMMEDIATE VERIFICATION
        //======================================================================

        $display("\n--- B. S-type Immediate Verification ---");

        check_imm("B1: S-type +1",
                  enc_s(32'd1), SEL_S, 32'h00000001);

        check_imm("B2: S-type +100",
                  enc_s(32'd100), SEL_S, 32'h00000064);

        check_imm("B3: S-type zero",
                  enc_s(32'd0), SEL_S, 32'h00000000);

        check_imm("B4: S-type -1",
                  enc_s(-1), SEL_S, 32'hFFFFFFFF);

        check_imm("B5: S-type -5",
                  enc_s(-5), SEL_S, 32'hFFFFFFFB);

        check_imm("B6: S-type maximum +2047",
                  enc_s(32'd2047), SEL_S, 32'h000007FF);

        check_imm("B7: S-type minimum -2048",
                  enc_s(-2048), SEL_S, 32'hFFFFF800);

        check_imm("B8: S-type positive 0x555",
                  enc_s(32'h555), SEL_S, 32'h00000555);

        check_imm("B9: S-type negative 0x556",
                  enc_s(-32'sh556), SEL_S, 32'hFFFFFAAA);

        // Real instruction: sw x5, 8(x2)
        // Machine code: 0x00512423

        check_imm("B10: SW x5, 8(x2)",
                  32'h00512423, SEL_S, 32'h00000008);

        // Verify low and high immediate fields independently

        check_imm("B11: S-type low field",
                  enc_s(32'h01F), SEL_S, 32'h0000001F);

        check_imm("B12: S-type high field",
                  enc_s(32'h7E0), SEL_S, 32'h000007E0);

        // Individual S-type immediate bit verification

        for (k = 0; k < 12; k = k + 1) begin

            tmp_imm   = 32'd1 << k;
            tmp_exp   = ref_sext(tmp_imm, 12);
            tmp_instr = enc_s(tmp_imm);

            check_imm("B13: S-type single-bit sweep",
                      tmp_instr, SEL_S, tmp_exp);

        end

        //======================================================================
        // C. B-TYPE IMMEDIATE VERIFICATION
        //======================================================================

        $display("\n--- C. B-type Branch Immediate Verification ---");

        check_imm("C1: B-type +2",
                  enc_b(32'd2), SEL_B, 32'h00000002);

        check_imm("C2: B-type +8",
                  enc_b(32'd8), SEL_B, 32'h00000008);

        check_imm("C3: B-type zero",
                  enc_b(32'd0), SEL_B, 32'h00000000);

        check_imm("C4: B-type -2",
                  enc_b(-2), SEL_B, 32'hFFFFFFFE);

        check_imm("C5: B-type -4",
                  enc_b(-4), SEL_B, 32'hFFFFFFFC);

        check_imm("C6: B-type maximum +4094",
                  enc_b(32'd4094), SEL_B, 32'h00000FFE);

        check_imm("C7: B-type minimum -4096",
                  enc_b(-4096), SEL_B, 32'hFFFFF000);

        check_imm("C8: B-type positive 0xAAA",
                  enc_b(32'hAAA), SEL_B, 32'h00000AAA);

        check_imm("C9: B-type negative 0xAAA",
                  enc_b(-1366), SEL_B, 32'hFFFFFAAA);

        // Real instruction: beq x0, x0, -4
        // Machine code: 0xFE000EE3

        check_imm("C10: BEQ x0, x0, -4",
                  32'hFE000EE3, SEL_B, 32'hFFFFFFFC);

        // Individual B-type immediate bit verification

        for (k = 1; k < 13; k = k + 1) begin

            tmp_imm   = 32'd1 << k;
            tmp_exp   = ref_sext(tmp_imm, 13);
            tmp_instr = enc_b(tmp_imm);

            check_imm("C11: B-type single-bit sweep",
                      tmp_instr, SEL_B, tmp_exp);

            check_prop("C12: B-type bit 0 is zero",
                       immediate[0] === 1'b0);

        end

        check_imm("C13: B-type all-ones instruction",
                  32'hFFFFFFFF, SEL_B, 32'hFFFFFFFE);

        check_prop("C14: B-type bit 0 remains zero",
                   immediate[0] === 1'b0);

        check_prop("C15: B-type sign extension",
                   immediate[31:12] === 20'hFFFFF);

        check_imm("C16: B-type all-zero instruction",
                  32'h00000000, SEL_B, 32'h00000000);

        //======================================================================
        // D. U-TYPE IMMEDIATE VERIFICATION
        //======================================================================

        $display("\n--- D. U-type Immediate Verification ---");

        check_imm("D1: U-type upper 0x12345",
                  enc_u(32'h12345000), SEL_U, 32'h12345000);

        check_imm("D2: U-type upper 0xABCDE",
                  enc_u(32'hABCDE000), SEL_U, 32'hABCDE000);

        check_imm("D3: U-type all-zero upper field",
                  enc_u(32'h00000000), SEL_U, 32'h00000000);

        check_imm("D4: U-type all-ones upper field",
                  enc_u(32'hFFFFF000), SEL_U, 32'hFFFFF000);

        check_imm("D5: U-type upper 0xAAAAA",
                  enc_u(32'hAAAAA000), SEL_U, 32'hAAAAA000);

        check_imm("D6: U-type upper 0x55555",
                  enc_u(32'h55555000), SEL_U, 32'h55555000);

        check_imm("D7: U-type upper 0x80000",
                  enc_u(32'h80000000), SEL_U, 32'h80000000);

        check_imm("D8: U-type upper 0x7FFFF",
                  enc_u(32'h7FFFF000), SEL_U, 32'h7FFFF000);

        check_imm("D9: U-type upper 0x00001",
                  enc_u(32'h00001000), SEL_U, 32'h00001000);

        // Real instruction: lui x5, 0x12345
        // Machine code: 0x123452B7

        check_imm("D10: LUI x5, 0x12345",
                  32'h123452B7, SEL_U, 32'h12345000);

        check_imm("D11: U-type all-ones instruction",
                  32'hFFFFFFFF, SEL_U, 32'hFFFFF000);

        check_prop("D12: U-type lower 12 bits zero",
                   immediate[11:0] === 12'h000);

        // Individual U-type upper-bit verification

        for (k = 12; k < 32; k = k + 1) begin

            tmp_imm   = 32'd1 << k;
            tmp_instr = enc_u(tmp_imm);

            check_imm("D13: U-type single-bit sweep",
                      tmp_instr, SEL_U, tmp_imm);

            check_prop("D14: U-type lower 12 bits zero",
                       immediate[11:0] === 12'h000);

        end

        //======================================================================
        // E. J-TYPE IMMEDIATE VERIFICATION
        //======================================================================

        $display("\n--- E. J-type Jump Immediate Verification ---");

        check_imm("E1: J-type +2",
                  enc_j(32'd2), SEL_J, 32'h00000002);

        check_imm("E2: J-type +2048",
                  enc_j(32'd2048), SEL_J, 32'h00000800);

        check_imm("E3: J-type zero",
                  enc_j(32'd0), SEL_J, 32'h00000000);

        check_imm("E4: J-type -2",
                  enc_j(-2), SEL_J, 32'hFFFFFFFE);

        check_imm("E5: J-type -4",
                  enc_j(-4), SEL_J, 32'hFFFFFFFC);

        check_imm("E6: J-type maximum +1048574",
                  enc_j(32'd1048574), SEL_J, 32'h000FFFFE);

        check_imm("E7: J-type minimum -1048576",
                  enc_j(-1048576), SEL_J, 32'hFFF00000);

        check_imm("E8: J-type positive pattern",
                  enc_j(32'h0AAAAA), SEL_J, 32'h000AAAAA);

        check_imm("E9: J-type negative pattern",
                  enc_j(-32'sh55556), SEL_J, 32'hFFFAAAAA);

        // Real instruction: jal x1, 8
        // Machine code: 0x008000EF

        check_imm("E10: JAL x1, 8",
                  32'h008000EF, SEL_J, 32'h00000008);

        // Individual J-type immediate bit verification

        for (k = 1; k < 21; k = k + 1) begin

            tmp_imm   = 32'd1 << k;
            tmp_exp   = ref_sext(tmp_imm, 21);
            tmp_instr = enc_j(tmp_imm);

            check_imm("E11: J-type single-bit sweep",
                      tmp_instr, SEL_J, tmp_exp);

            check_prop("E12: J-type bit 0 is zero",
                       immediate[0] === 1'b0);

        end

        check_imm("E13: J-type all-ones instruction",
                  32'hFFFFFFFF, SEL_J, 32'hFFFFFFFE);

        check_prop("E14: J-type bit 0 remains zero",
                   immediate[0] === 1'b0);

        check_prop("E15: J-type sign extension",
                   immediate[31:21] === 11'h7FF);

        check_imm("E16: J-type all-zero instruction",
                  32'h00000000, SEL_J, 32'h00000000);

        //======================================================================
        // F. INVALID IMMEDIATE SELECTOR VERIFICATION
        //======================================================================

        $display("\n--- F. Invalid Selector Verification ---");

        check_imm("F1: Invalid selector 101",
                  32'hFFFFFFFF, 3'b101, 32'h00000000);

        check_imm("F2: Invalid selector 110",
                  32'hFFFFFFFF, 3'b110, 32'h00000000);

        check_imm("F3: Invalid selector 111",
                  32'hFFFFFFFF, 3'b111, 32'h00000000);

        check_imm("F4: Selector 101 with pattern",
                  32'hDEADBEEF, 3'b101, 32'h00000000);

        check_imm("F5: Selector 110 with pattern",
                  32'hA5A5A5A5, 3'b110, 32'h00000000);

        check_imm("F6: Selector 111 with pattern",
                  32'h12345678, 3'b111, 32'h00000000);

        check_imm("F7: Invalid selector with zero instruction",
                  32'h00000000, 3'b101, 32'h00000000);

        check_imm("F8: Invalid selector with negative I immediate",
                  enc_i(-1), 3'b111, 32'h00000000);

        //======================================================================
        // G. COMBINATIONAL BEHAVIOUR VERIFICATION
        //======================================================================

        $display("\n--- G. Combinational Behaviour Verification ---");

        // G1-G3: Keep selector fixed and change instruction only

        check_imm("G1: I-type instruction change +10",
                  enc_i(32'd10), SEL_I, 32'h0000000A);

        check_imm("G2: I-type instruction change -10",
                  enc_i(-10), SEL_I, 32'hFFFFFFF6);

        check_imm("G3: I-type instruction change +2047",
                  enc_i(32'd2047), SEL_I, 32'h000007FF);

        // G4-G9: Keep instruction fixed and change selector only.
        //
        // Fixed instruction: 0x80A5F0E3
        //
        // Expected values independently reconstructed:
        // I-type = 0xFFFFF80A
        // S-type = 0xFFFFF801
        // B-type = 0xFFFFF800
        // U-type = 0x80A5F000
        // J-type = 0xFFF5F00A

        check_imm("G4: Fixed instruction, I-type",
                  32'h80A5F0E3, SEL_I, 32'hFFFFF80A);

        check_imm("G5: Fixed instruction, S-type",
                  32'h80A5F0E3, SEL_S, 32'hFFFFF801);

        check_imm("G6: Fixed instruction, B-type",
                  32'h80A5F0E3, SEL_B, 32'hFFFFF800);

        check_imm("G7: Fixed instruction, U-type",
                  32'h80A5F0E3, SEL_U, 32'h80A5F000);

        check_imm("G8: Fixed instruction, J-type",
                  32'h80A5F0E3, SEL_J, 32'hFFF5F00A);

        check_imm("G9: Fixed instruction, invalid selector",
                  32'h80A5F0E3, 3'b101, 32'h00000000);

        // G10-G13: Directly observe output updates without a clock.

        instruction = enc_i(32'd7);
        imm_sel     = SEL_I;

        #5;

        check_prop("G10: Output follows I-type instruction",
                   immediate === 32'd7);

        instruction = enc_i(-7);

        #5;

        check_prop("G11: Output updates on instruction change",
                   immediate === 32'hFFFFFFF9);

        instruction = enc_u(32'h12345000);
        imm_sel     = SEL_U;

        #5;

        check_prop("G12: Output updates on instruction and selector change",
                   immediate === 32'h12345000);

        imm_sel = SEL_I;

        #5;

        check_prop("G13: Output updates on selector change only",
                   immediate === {{20{instruction[31]}},
                                  instruction[31:20]});

        //======================================================================
        // FINAL VERIFICATION SUMMARY
        //======================================================================

        #10;

        $display("\n==============================================================");
        $display("             IMMGEN VERIFICATION SUMMARY");
        $display("==============================================================");

        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);

        $display("==============================================================");

        if (failed_tests == 0) begin

            $display(" IMMGEN VERIFICATION PASSED");

        end
        else begin

            $display(" IMMGEN VERIFICATION FAILED");

        end

        $display("==============================================================");

        $finish;

    end

endmodule
