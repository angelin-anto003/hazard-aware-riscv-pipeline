`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_branch_comparator
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// DUT         : branch_comparator (rtl/branch_comparator.v)
// Description : Self-checking Verilog-2001 testbench. No clock: the DUT is
//               purely combinational, so every check waits 1 ns after the
//               inputs change.
//
// Independence of expected values:
//   - Directed tests use hand-worked literal results.
//   - The boundary-value sweep lists 8 values in ascending UNSIGNED order.
//     The index in that list is the unsigned rank; the signed rank is
//     computed from it by srank() (the two's-complement order is the same
//     list rotated by half). Expected results come from comparing RANKS as
//     plain integers, never from $signed() or the DUT's operators.
//   - Walking-bit tests use known properties (only bit 31 changes the signed
//     result of 2^k versus 0).
//
// Sections: A BEQ, B BNE, C BLT, D BGE, E BLTU, F BGEU, G reserved,
//           H asynchronous behaviour, I robustness, J unknown inputs.
//
// Run from the repository root (the VCD path is relative).
//==============================================================================

module tb_branch_comparator;

    //--------------------------------------------------------------------------
    // branch_type encodings (match control_unit.v)
    //--------------------------------------------------------------------------
    localparam [2:0] BEQ  = 3'b000;
    localparam [2:0] BNE  = 3'b001;
    localparam [2:0] BLT  = 3'b010;
    localparam [2:0] BGE  = 3'b011;
    localparam [2:0] BLTU = 3'b100;
    localparam [2:0] BGEU = 3'b101;
    localparam [2:0] RSV6 = 3'b110;
    localparam [2:0] RSV7 = 3'b111;

    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------
    reg  [31:0] rs1_data;
    reg  [31:0] rs2_data;
    reg  [2:0]  branch_type;
    wire        branch_taken;

    //--------------------------------------------------------------------------
    // Bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer fails_before;
    integer i;
    integer j;
    integer k;
    reg     verbose;                 // 1 = print every PASS line
    reg [31:0] bv [0:7];             // boundary values, ascending UNSIGNED order
    reg [31:0] tmp;

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    branch_comparator uut (
        .rs1_data     (rs1_data),
        .rs2_data     (rs2_data),
        .branch_type  (branch_type),
        .branch_taken (branch_taken)
    );

    //--------------------------------------------------------------------------
    // Waveform generation
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("simulations/branch_comparator.vcd");
        $dumpvars(0, tb_branch_comparator);
    end

    //--------------------------------------------------------------------------
    // Watchdog timeout
    //--------------------------------------------------------------------------
    initial begin
        #1000000;
        $display("[FAIL] WATCHDOG TIMEOUT: simulation did not finish");
        $display("BRANCH COMPARATOR VERIFICATION FAILED");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Signed rank of the value at unsigned-rank position idx (0..7).
    // Unsigned order: 0,1,7FFFFFFE,7FFFFFFF,80000000,80000001,FFFFFFFE,FFFFFFFF
    // Signed order  : 80000000 ... FFFFFFFF, 0, 1, ... 7FFFFFFF  (rotated by 4)
    //--------------------------------------------------------------------------
    function integer srank;
        input integer idx;
        begin
            if (idx < 4)
                srank = idx + 4;
            else
                srank = idx - 4;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Task: compare current output with the expected value (case inequality
    //       catches X/Z). Inputs must already be applied and settled.
    //--------------------------------------------------------------------------
    task evaluate;
        input [319:0] name;
        input         expected;
        begin
            total_tests = total_tests + 1;
            if (branch_taken !== expected) begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s | type=%b rs1=%h rs2=%h expected=%b actual=%b",
                         total_tests, name, branch_type, rs1_data, rs2_data,
                         expected, branch_taken);
            end
            else begin
                passed_tests = passed_tests + 1;
                if (verbose)
                    $display("[PASS] #%0d %0s | type=%b rs1=%h rs2=%h taken=%b",
                             total_tests, name, branch_type, rs1_data, rs2_data,
                             branch_taken);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: apply all three inputs, wait 1 ns, check
    //--------------------------------------------------------------------------
    task check;
        input [319:0] name;
        input [31:0]  a;
        input [31:0]  b;
        input [2:0]   bt;
        input         expected;
        begin
            rs1_data    = a;
            rs2_data    = b;
            branch_type = bt;
            #1;
            evaluate(name, expected);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: both reserved encodings (110 and 111) must give 0 (2 tests)
    //--------------------------------------------------------------------------
    task check_reserved;
        input [319:0] name;
        input [31:0]  a;
        input [31:0]  b;
        begin
            check(name, a, b, RSV6, 1'b0);
            check(name, a, b, RSV7, 1'b0);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: the four ordering comparisons for one operand pair (4 tests)
    //--------------------------------------------------------------------------
    task check_cmp4;
        input [319:0] name;
        input [31:0]  a;
        input [31:0]  b;
        input         e_blt;
        input         e_bge;
        input         e_bltu;
        input         e_bgeu;
        begin
            check(name, a, b, BLT,  e_blt);
            check(name, a, b, BGE,  e_bge);
            check(name, a, b, BLTU, e_bltu);
            check(name, a, b, BGEU, e_bgeu);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: summary line for sweeps that print no per-test PASS lines
    //--------------------------------------------------------------------------
    task sweep_end;
        input [319:0] name;
        input integer before;
        begin
            if (failed_tests == before)
                $display("[PASS] %0s | sweep completed, no mismatches", name);
            else
                $display("[FAIL] %0s | sweep had %0d mismatches",
                         name, failed_tests - before);
        end
    endtask

    //--------------------------------------------------------------------------
    // Main stimulus
    //--------------------------------------------------------------------------
    initial begin
        total_tests  = 0;
        passed_tests = 0;
        failed_tests = 0;
        verbose      = 1'b1;
        rs1_data     = 32'h0;
        rs2_data     = 32'h0;
        branch_type  = BEQ;

        bv[0] = 32'h00000000;
        bv[1] = 32'h00000001;
        bv[2] = 32'h7FFFFFFE;
        bv[3] = 32'h7FFFFFFF;
        bv[4] = 32'h80000000;
        bv[5] = 32'h80000001;
        bv[6] = 32'hFFFFFFFE;
        bv[7] = 32'hFFFFFFFF;
        #1;

        $display("==============================================================");
        $display(" Branch Comparator Self-Checking Testbench Started");
        $display("==============================================================");

        //======================================================================
        // A. BEQ (7 tests)
        //======================================================================
        $display("--- A. BEQ ---");
        check("A1 BEQ zero == zero",          32'h00000000, 32'h00000000, BEQ, 1'b1);
        check("A2 BEQ equal positive",        32'h00000005, 32'h00000005, BEQ, 1'b1);
        check("A3 BEQ equal negative",        32'hFFFFFFFB, 32'hFFFFFFFB, BEQ, 1'b1);
        check("A4 BEQ different 5 vs 6",      32'h00000005, 32'h00000006, BEQ, 1'b0);
        check("A5 BEQ equal max unsigned",    32'hFFFFFFFF, 32'hFFFFFFFF, BEQ, 1'b1);
        check("A6 BEQ differ only in bit 0",  32'h80000000, 32'h80000001, BEQ, 1'b0);
        check("A7 BEQ differ only in bit 31", 32'h00000000, 32'h80000000, BEQ, 1'b0);

        //======================================================================
        // B. BNE (8 tests)
        //======================================================================
        $display("--- B. BNE ---");
        check("B1 BNE equal 7 vs 7",          32'h00000007, 32'h00000007, BNE, 1'b0);
        check("B2 BNE different positive",    32'h00000003, 32'h00000004, BNE, 1'b1);
        check("B3 BNE positive vs negative",  32'h00000005, 32'hFFFFFFFB, BNE, 1'b1);
        check("B4 BNE zero vs nonzero",       32'h00000000, 32'h00000001, BNE, 1'b1);
        check("B5 BNE nonzero vs zero",       32'h00000001, 32'h00000000, BNE, 1'b1);
        check("B6 BNE zero vs zero",          32'h00000000, 32'h00000000, BNE, 1'b0);
        check("B7 BNE equal max unsigned",    32'hFFFFFFFF, 32'hFFFFFFFF, BNE, 1'b0);
        check("B8 BNE differ only in bit 31", 32'h00000000, 32'h80000000, BNE, 1'b1);

        //======================================================================
        // C. BLT, signed (17 tests)
        //======================================================================
        $display("--- C. BLT (signed) ---");
        check("C1 BLT -5 < 3",                32'hFFFFFFFB, 32'h00000003, BLT, 1'b1);
        check("C2 BLT 3 < -5",                32'h00000003, 32'hFFFFFFFB, BLT, 1'b0);
        check("C3 BLT -1 < 0",                32'hFFFFFFFF, 32'h00000000, BLT, 1'b1);
        check("C4 BLT 0 < 1",                 32'h00000000, 32'h00000001, BLT, 1'b1);
        check("C5 BLT -5 < -3",               32'hFFFFFFFB, 32'hFFFFFFFD, BLT, 1'b1);
        check("C6 BLT -3 < -5",               32'hFFFFFFFD, 32'hFFFFFFFB, BLT, 1'b0);
        check("C7 BLT 5 < 5",                 32'h00000005, 32'h00000005, BLT, 1'b0);
        check("C8 BLT -5 < -5",               32'hFFFFFFFB, 32'hFFFFFFFB, BLT, 1'b0);
        check("C9 BLT INT_MIN < INT_MAX",     32'h80000000, 32'h7FFFFFFF, BLT, 1'b1);
        check("C10 BLT INT_MAX < INT_MIN",    32'h7FFFFFFF, 32'h80000000, BLT, 1'b0);
        check("C11 BLT INT_MIN < 0",          32'h80000000, 32'h00000000, BLT, 1'b1);
        check("C12 BLT 0 < INT_MIN",          32'h00000000, 32'h80000000, BLT, 1'b0);
        check("C13 BLT INT_MIN < INT_MIN",    32'h80000000, 32'h80000000, BLT, 1'b0);
        check("C14 BLT INT_MAX < INT_MAX",    32'h7FFFFFFF, 32'h7FFFFFFF, BLT, 1'b0);
        check("C15 BLT 0 < 0",                32'h00000000, 32'h00000000, BLT, 1'b0);
        check("C16 BLT INT_MAX < 0",          32'h7FFFFFFF, 32'h00000000, BLT, 1'b0);
        check("C17 BLT 0 < INT_MAX",          32'h00000000, 32'h7FFFFFFF, BLT, 1'b1);

        //======================================================================
        // D. BGE, signed (14 tests)
        //======================================================================
        $display("--- D. BGE (signed) ---");
        check("D1 BGE 5 >= -5",               32'h00000005, 32'hFFFFFFFB, BGE, 1'b1);
        check("D2 BGE -5 >= 5",               32'hFFFFFFFB, 32'h00000005, BGE, 1'b0);
        check("D3 BGE -5 >= -5",              32'hFFFFFFFB, 32'hFFFFFFFB, BGE, 1'b1);
        check("D4 BGE 0 >= -1",               32'h00000000, 32'hFFFFFFFF, BGE, 1'b1);
        check("D5 BGE 0 >= 0",                32'h00000000, 32'h00000000, BGE, 1'b1);
        check("D6 BGE INT_MAX >= INT_MIN",    32'h7FFFFFFF, 32'h80000000, BGE, 1'b1);
        check("D7 BGE INT_MIN >= INT_MAX",    32'h80000000, 32'h7FFFFFFF, BGE, 1'b0);
        check("D8 BGE INT_MIN >= INT_MIN",    32'h80000000, 32'h80000000, BGE, 1'b1);
        check("D9 BGE INT_MAX >= INT_MAX",    32'h7FFFFFFF, 32'h7FFFFFFF, BGE, 1'b1);
        check("D10 BGE -3 >= -5",             32'hFFFFFFFD, 32'hFFFFFFFB, BGE, 1'b1);
        check("D11 BGE -5 >= -3",             32'hFFFFFFFB, 32'hFFFFFFFD, BGE, 1'b0);
        check("D12 BGE -1 >= 0",              32'hFFFFFFFF, 32'h00000000, BGE, 1'b0);
        check("D13 BGE 0 >= 1",               32'h00000000, 32'h00000001, BGE, 1'b0);
        check("D14 BGE 1 >= 0",               32'h00000001, 32'h00000000, BGE, 1'b1);

        //======================================================================
        // E. BLTU, unsigned (14 tests)
        //======================================================================
        $display("--- E. BLTU (unsigned) ---");
        check("E1 BLTU 1 < 100",              32'h00000001, 32'h00000064, BLTU, 1'b1);
        check("E2 BLTU 0x80000000 < 0x7FFFFFFF", 32'h80000000, 32'h7FFFFFFF, BLTU, 1'b0);
        check("E3 BLTU 0x7FFFFFFF < 0x80000000", 32'h7FFFFFFF, 32'h80000000, BLTU, 1'b1);
        check("E4 BLTU 0 < MAX",              32'h00000000, 32'hFFFFFFFF, BLTU, 1'b1);
        check("E5 BLTU 9 < 9",                32'h00000009, 32'h00000009, BLTU, 1'b0);
        check("E6 BLTU MAX < 0",              32'hFFFFFFFF, 32'h00000000, BLTU, 1'b0);
        check("E7 BLTU MAX < MAX-1",          32'hFFFFFFFF, 32'hFFFFFFFE, BLTU, 1'b0);
        check("E8 BLTU MAX-1 < MAX",          32'hFFFFFFFE, 32'hFFFFFFFF, BLTU, 1'b1);
        check("E9 BLTU 0 < 0",                32'h00000000, 32'h00000000, BLTU, 1'b0);
        check("E10 BLTU 0 < 1",               32'h00000000, 32'h00000001, BLTU, 1'b1);
        check("E11 BLTU 1 < 0",               32'h00000001, 32'h00000000, BLTU, 1'b0);
        check("E12 BLTU MAX < MAX",           32'hFFFFFFFF, 32'hFFFFFFFF, BLTU, 1'b0);
        check("E13 BLTU -5 < 3 (unsigned)",   32'hFFFFFFFB, 32'h00000003, BLTU, 1'b0);
        check("E14 BLTU 3 < -5 (unsigned)",   32'h00000003, 32'hFFFFFFFB, BLTU, 1'b1);

        //======================================================================
        // F. BGEU, unsigned (12 tests)
        //======================================================================
        $display("--- F. BGEU (unsigned) ---");
        check("F1 BGEU 100 >= 1",             32'h00000064, 32'h00000001, BGEU, 1'b1);
        check("F2 BGEU MAX >= 0x80000000",    32'hFFFFFFFF, 32'h80000000, BGEU, 1'b1);
        check("F3 BGEU 9 >= 9",               32'h00000009, 32'h00000009, BGEU, 1'b1);
        check("F4 BGEU 0 >= 1",               32'h00000000, 32'h00000001, BGEU, 1'b0);
        check("F5 BGEU 0x80000000 >= 0x7FFFFFFF", 32'h80000000, 32'h7FFFFFFF, BGEU, 1'b1);
        check("F6 BGEU 0x7FFFFFFF >= 0x80000000", 32'h7FFFFFFF, 32'h80000000, BGEU, 1'b0);
        check("F7 BGEU 0 >= MAX",             32'h00000000, 32'hFFFFFFFF, BGEU, 1'b0);
        check("F8 BGEU MAX >= 0",             32'hFFFFFFFF, 32'h00000000, BGEU, 1'b1);
        check("F9 BGEU 0 >= 0",               32'h00000000, 32'h00000000, BGEU, 1'b1);
        check("F10 BGEU MAX >= MAX",          32'hFFFFFFFF, 32'hFFFFFFFF, BGEU, 1'b1);
        check("F11 BGEU 3 >= -5 (unsigned)",  32'h00000003, 32'hFFFFFFFB, BGEU, 1'b0);
        check("F12 BGEU -5 >= 3 (unsigned)",  32'hFFFFFFFB, 32'h00000003, BGEU, 1'b1);

        //======================================================================
        // G. Reserved encodings 110 and 111 (7 pairs x 2 = 14 tests)
        //======================================================================
        $display("--- G. Reserved encodings ---");
        check_reserved("G1 reserved equal 5,5",     32'h00000005, 32'h00000005);
        check_reserved("G2 reserved different 5,6", 32'h00000005, 32'h00000006);
        check_reserved("G3 reserved zero,zero",     32'h00000000, 32'h00000000);
        check_reserved("G4 reserved 0,MAX",         32'h00000000, 32'hFFFFFFFF);
        check_reserved("G5 reserved MAX,0",         32'hFFFFFFFF, 32'h00000000);
        check_reserved("G6 reserved INT_MIN,INT_MAX",32'h80000000, 32'h7FFFFFFF);
        check_reserved("G7 reserved MAX,MAX",       32'hFFFFFFFF, 32'hFFFFFFFF);

        //======================================================================
        // H. Asynchronous behaviour: change ONE input at a time, no clock
        //    (11 tests)
        //======================================================================
        $display("--- H. Asynchronous behaviour ---");
        rs1_data = 32'd5; rs2_data = 32'd5; branch_type = BEQ;
        #1; evaluate("H1 BEQ 5,5 -> 1", 1'b1);
        rs2_data = 32'd6;
        #1; evaluate("H2 rs2 -> 6 only: BEQ 0", 1'b0);
        rs2_data = 32'd5;
        #1; evaluate("H3 rs2 -> 5 only: BEQ 1", 1'b1);
        rs1_data = 32'd7;
        #1; evaluate("H4 rs1 -> 7 only: BEQ 0", 1'b0);
        branch_type = BNE;
        #1; evaluate("H5 type -> BNE only: 7!=5", 1'b1);
        branch_type = BGE;
        #1; evaluate("H6 type -> BGE only: 7>=5", 1'b1);
        branch_type = BLT;
        #1; evaluate("H7 type -> BLT only: 7<5", 1'b0);
        branch_type = RSV6;
        #1; evaluate("H8 type -> 110 only: 0", 1'b0);
        branch_type = BLT; rs1_data = 32'd2;
        #1; evaluate("H9 BLT, rs1 -> 2: 2<5", 1'b1);
        branch_type = BEQ;
        #1; evaluate("H10 type -> BEQ only: 2==5", 1'b0);
        #20; evaluate("H11 output stable, inputs held", 1'b0);

        //======================================================================
        // I. Robustness
        //======================================================================
        $display("--- I. Robustness ---");

        // I1: alternating branch types, rs1 = 0xFFFFFFFF, rs2 = 1 (12 tests)
        //     signed: -1 vs 1   unsigned: 4294967295 vs 1
        check("I1 alt BEQ  (MAX,1)",  32'hFFFFFFFF, 32'h00000001, BEQ,  1'b0);
        check("I2 alt BNE  (MAX,1)",  32'hFFFFFFFF, 32'h00000001, BNE,  1'b1);
        check("I3 alt BLT  (MAX,1)",  32'hFFFFFFFF, 32'h00000001, BLT,  1'b1);
        check("I4 alt BGE  (MAX,1)",  32'hFFFFFFFF, 32'h00000001, BGE,  1'b0);
        check("I5 alt BLTU (MAX,1)",  32'hFFFFFFFF, 32'h00000001, BLTU, 1'b0);
        check("I6 alt BGEU (MAX,1)",  32'hFFFFFFFF, 32'h00000001, BGEU, 1'b1);
        check("I7 alt BGEU (MAX,1)",  32'hFFFFFFFF, 32'h00000001, BGEU, 1'b1);
        check("I8 alt BLTU (MAX,1)",  32'hFFFFFFFF, 32'h00000001, BLTU, 1'b0);
        check("I9 alt BGE  (MAX,1)",  32'hFFFFFFFF, 32'h00000001, BGE,  1'b0);
        check("I10 alt BLT (MAX,1)",  32'hFFFFFFFF, 32'h00000001, BLT,  1'b1);
        check("I11 alt BNE (MAX,1)",  32'hFFFFFFFF, 32'h00000001, BNE,  1'b1);
        check("I12 alt BEQ (MAX,1)",  32'hFFFFFFFF, 32'h00000001, BEQ,  1'b0);

        // Signed vs unsigned disagreement (4 pairs x 4 = 16 tests)
        //                                           BLT   BGE   BLTU  BGEU
        check_cmp4("I13 signed/unsigned MAX vs 0",   32'hFFFFFFFF, 32'h00000000, 1'b1, 1'b0, 1'b0, 1'b1);
        check_cmp4("I14 signed/unsigned MIN vs MAX", 32'h80000000, 32'h7FFFFFFF, 1'b1, 1'b0, 1'b0, 1'b1);
        check_cmp4("I15 signed/unsigned 0 vs MIN",   32'h00000000, 32'h80000000, 1'b0, 1'b1, 1'b1, 1'b0);
        check_cmp4("I16 signed/unsigned 7FFF.. vs -1",32'h7FFFFFFF, 32'hFFFFFFFF, 1'b0, 1'b1, 1'b1, 1'b0);

        // Boundary-value sweep: 8 x 8 pairs x 8 branch types = 512 tests
        verbose      = 1'b0;
        fails_before = failed_tests;
        for (i = 0; i < 8; i = i + 1) begin
            for (j = 0; j < 8; j = j + 1) begin
                check("I17 sweep BEQ",   bv[i], bv[j], BEQ,  (i == j));
                check("I17 sweep BNE",   bv[i], bv[j], BNE,  (i != j));
                check("I17 sweep BLT",   bv[i], bv[j], BLT,  (srank(i) <  srank(j)));
                check("I17 sweep BGE",   bv[i], bv[j], BGE,  (srank(i) >= srank(j)));
                check("I17 sweep BLTU",  bv[i], bv[j], BLTU, (i <  j));
                check("I17 sweep BGEU",  bv[i], bv[j], BGEU, (i >= j));
                check("I17 sweep RSV6",  bv[i], bv[j], RSV6, 1'b0);
                check("I17 sweep RSV7",  bv[i], bv[j], RSV7, 1'b0);
            end
        end
        sweep_end("I17 boundary sweep (512 tests)", fails_before);

        // Walking-one tests: 3 loops x 32 bits (192 + 192 + 64 = 448 tests)
        fails_before = failed_tests;
        for (k = 0; k < 32; k = k + 1) begin
            tmp = 32'd1 << k;
            // 2^k versus 0. Only k = 31 is negative when read as signed.
            check("I18 walk 2^k vs 0 BEQ",  tmp, 32'h0, BEQ,  1'b0);
            check("I18 walk 2^k vs 0 BNE",  tmp, 32'h0, BNE,  1'b1);
            check("I18 walk 2^k vs 0 BLT",  tmp, 32'h0, BLT,  (k == 31));
            check("I18 walk 2^k vs 0 BGE",  tmp, 32'h0, BGE,  (k != 31));
            check("I18 walk 2^k vs 0 BLTU", tmp, 32'h0, BLTU, 1'b0);
            check("I18 walk 2^k vs 0 BGEU", tmp, 32'h0, BGEU, 1'b1);
        end
        for (k = 0; k < 32; k = k + 1) begin
            tmp = 32'd1 << k;
            // Equal operands: only the "or equal" conditions are true.
            check("I19 walk equal BEQ",  tmp, tmp, BEQ,  1'b1);
            check("I19 walk equal BNE",  tmp, tmp, BNE,  1'b0);
            check("I19 walk equal BLT",  tmp, tmp, BLT,  1'b0);
            check("I19 walk equal BGE",  tmp, tmp, BGE,  1'b1);
            check("I19 walk equal BLTU", tmp, tmp, BLTU, 1'b0);
            check("I19 walk equal BGEU", tmp, tmp, BGEU, 1'b1);
        end
        for (k = 0; k < 32; k = k + 1) begin
            tmp = 32'hFFFFFFFF ^ (32'd1 << k);
            // Operands differ in exactly one bit: every bit must be compared.
            check("I20 one-bit diff BEQ", 32'hFFFFFFFF, tmp, BEQ, 1'b0);
            check("I20 one-bit diff BNE", 32'hFFFFFFFF, tmp, BNE, 1'b1);
        end
        sweep_end("I18-20 walking-bit sweeps (448 tests)", fails_before);
        verbose = 1'b1;

        //======================================================================
        // J. Unknown inputs (6 tests). These document the chosen RTL behaviour:
        //    - an unknown branch_type matches no case item -> default -> 0
        //    - an unknown operand makes the comparison result unknown (x)
        //======================================================================
        $display("--- J. Unknown inputs ---");
        check("J1 type=xxx, equal operands",  32'h00000005, 32'h00000005, 3'bxxx, 1'b0);
        check("J2 type=zzz, equal operands",  32'h00000005, 32'h00000005, 3'bzzz, 1'b0);
        check("J3 type=xxx, different operands", 32'h00000005, 32'h00000006, 3'bxxx, 1'b0);
        check("J4 rs1=x, BEQ -> x",           32'hxxxxxxxx, 32'h00000005, BEQ,  1'bx);
        check("J5 rs2=x, BNE -> x",           32'h00000005, 32'hxxxxxxxx, BNE,  1'bx);
        check("J6 rs1=x, BLTU -> x",          32'hxxxxxxxx, 32'h00000005, BLTU, 1'bx);

        //======================================================================
        // Final summary
        //======================================================================
        #10;
        $display("==============================================================");
        $display(" BRANCH COMPARATOR VERIFICATION SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");

        if (failed_tests == 0)
            $display("BRANCH COMPARATOR VERIFICATION PASSED");
        else
            $display("BRANCH COMPARATOR VERIFICATION FAILED");

        $finish;
    end

endmodule