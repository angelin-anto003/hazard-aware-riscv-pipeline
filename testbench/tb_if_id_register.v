`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_if_id_register
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// DUT         : if_id_register (rtl/if_id_register.v)
// Description : Self-checking Verilog-2001 testbench.
//
// Timing (race-free):
//   - 10 ns clock, rising edges at 5, 15, 25 ... ns; falling edges at 10, 20 ...
//   - Stimulus changes only at the FALLING edge (mid-cycle).
//   - Results are checked 1 ns AFTER a rising edge.
//   - "Not before the edge" checks sample 2 ns after a falling edge, i.e.
//     3 ns before the next rising edge.
//
// Expected values are written as literals in every check; the testbench has
// no model of the DUT's priority logic.
//
// Note: reset and flush leave the register in the identical state, so the
// priority of reset over flush cannot be observed; reset over enable and
// flush over enable are both checked.
//
// Run from the repository root (the VCD path is relative).
//==============================================================================

module tb_if_id_register;

    localparam [31:0] NOP = 32'h00000013;

    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------
    reg         clk;
    reg         reset;
    reg         enable;
    reg         flush;
    reg  [31:0] pc_in;
    reg  [31:0] pc_plus4_in;
    reg  [31:0] instruction_in;
    wire [31:0] pc_out;
    wire [31:0] pc_plus4_out;
    wire [31:0] instruction_out;
    wire        valid_out;

    //--------------------------------------------------------------------------
    // Bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer fails_before;
    integer i;
    reg     verbose;

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    if_id_register uut (
        .clk             (clk),
        .reset           (reset),
        .enable          (enable),
        .flush           (flush),
        .pc_in           (pc_in),
        .pc_plus4_in     (pc_plus4_in),
        .instruction_in  (instruction_in),
        .pc_out          (pc_out),
        .pc_plus4_out    (pc_plus4_out),
        .instruction_out (instruction_out),
        .valid_out       (valid_out)
    );

    //--------------------------------------------------------------------------
    // 10 ns clock (starts low)
    //--------------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    //--------------------------------------------------------------------------
    // Waveform
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("simulations/if_id_register.vcd");
        $dumpvars(0, tb_if_id_register);
    end

    //--------------------------------------------------------------------------
    // Watchdog
    //--------------------------------------------------------------------------
    initial begin
        #100000;
        $display("[FAIL] WATCHDOG TIMEOUT: simulation did not finish");
        $display("IF/ID REGISTER VERIFICATION FAILED");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Task: compare all four outputs (case inequality catches X/Z)
    //--------------------------------------------------------------------------
    task check_out;
        input [319:0] name;
        input [31:0]  e_pc;
        input [31:0]  e_pc4;
        input [31:0]  e_instr;
        input         e_valid;
        reg           bad;
        begin
            total_tests = total_tests + 1;
            bad = 1'b0;
            if (pc_out          !== e_pc)    bad = 1'b1;
            if (pc_plus4_out    !== e_pc4)   bad = 1'b1;
            if (instruction_out !== e_instr) bad = 1'b1;
            if (valid_out       !== e_valid) bad = 1'b1;

            if (!bad) begin
                passed_tests = passed_tests + 1;
                if (verbose)
                    $display("[PASS] #%0d %0s | pc=%h pc4=%h instr=%h valid=%b",
                             total_tests, name, pc_out, pc_plus4_out,
                             instruction_out, valid_out);
            end
            else begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s", total_tests, name);
                if (pc_out !== e_pc)
                    $display("       pc_out          actual=%h expected=%h", pc_out, e_pc);
                if (pc_plus4_out !== e_pc4)
                    $display("       pc_plus4_out    actual=%h expected=%h", pc_plus4_out, e_pc4);
                if (instruction_out !== e_instr)
                    $display("       instruction_out actual=%h expected=%h", instruction_out, e_instr);
                if (valid_out !== e_valid)
                    $display("       valid_out       actual=%b expected=%b", valid_out, e_valid);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: one full clock cycle. Inputs are driven at the falling edge,
    //       captured at the rising edge; returns 1 ns after that edge.
    //--------------------------------------------------------------------------
    task cycle;
        input        rst;
        input        fl;
        input        en;
        input [31:0] pc;
        input [31:0] pc4;
        input [31:0] instr;
        begin
            @(negedge clk);
            reset          = rst;
            flush          = fl;
            enable         = en;
            pc_in          = pc;
            pc_plus4_in    = pc4;
            instruction_in = instr;
            @(posedge clk);
            #1;
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: summary line for sweeps without per-test PASS lines
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
        total_tests    = 0;
        passed_tests   = 0;
        failed_tests   = 0;
        verbose        = 1'b1;
        reset          = 1'b0;
        enable         = 1'b0;
        flush          = 1'b0;
        pc_in          = 32'hAAAAAAAA;
        pc_plus4_in    = 32'hBBBBBBBB;
        instruction_in = 32'hCCCCCCCC;
        #1;

        $display("==============================================================");
        $display(" IF/ID Register Self-Checking Testbench Started");
        $display("==============================================================");

        //======================================================================
        // 1. Unknown state before reset (nothing has cleared the flip-flops)
        //======================================================================
        $display("--- 1. Unknown state before reset ---");
        check_out("1.1 outputs unknown at time 0",
                  32'hxxxxxxxx, 32'hxxxxxxxx, 32'hxxxxxxxx, 1'bx);
        @(posedge clk);
        #1;
        check_out("1.2 hold (en=0) keeps unknown",
                  32'hxxxxxxxx, 32'hxxxxxxxx, 32'hxxxxxxxx, 1'bx);

        //======================================================================
        // 2. Synchronous reset
        //======================================================================
        $display("--- 2. Synchronous reset ---");
        cycle(1'b1, 1'b0, 1'b0, 32'hAAAAAAAA, 32'hBBBBBBBB, 32'hCCCCCCCC);
        check_out("2.1 reset clears, NOP, valid=0", 32'h0, 32'h0, NOP, 1'b0);

        //======================================================================
        // 3. Capture
        //======================================================================
        $display("--- 3. Capture ---");
        cycle(1'b0, 1'b0, 1'b1, 32'h00000100, 32'h00000104, 32'h00500093);
        check_out("3.1 capture pc/pc4/instr, valid=1",
                  32'h00000100, 32'h00000104, 32'h00500093, 1'b1);

        //======================================================================
        // 4. Consecutive captures
        //======================================================================
        $display("--- 4. Consecutive captures ---");
        cycle(1'b0, 1'b0, 1'b1, 32'h00000104, 32'h00000108, 32'h00A00113);
        check_out("4.1 second instruction",
                  32'h00000104, 32'h00000108, 32'h00A00113, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, 32'h00000108, 32'h0000010C, 32'h002081B3);
        check_out("4.2 third instruction",
                  32'h00000108, 32'h0000010C, 32'h002081B3, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, 32'h0000010C, 32'h00000110, 32'h00312223);
        check_out("4.3 fourth instruction",
                  32'h0000010C, 32'h00000110, 32'h00312223, 1'b1);

        // 32 back-to-back captures; each must show the value presented in
        // the previous cycle
        verbose      = 1'b0;
        fails_before = failed_tests;
        for (i = 0; i < 32; i = i + 1) begin
            cycle(1'b0, 1'b0, 1'b1,
                  32'h00001000 + i * 4,
                  32'h00001004 + i * 4,
                  32'h12340000 + i * 32'h101);
            check_out("4.4 back-to-back capture",
                      32'h00001000 + i * 4,
                      32'h00001004 + i * 4,
                      32'h12340000 + i * 32'h101,
                      1'b1);
        end
        sweep_end("4.4 32 back-to-back captures", fails_before);
        verbose = 1'b1;

        //======================================================================
        // 5. Hold (enable = 0): all fields retained
        //======================================================================
        $display("--- 5. Hold ---");
        cycle(1'b0, 1'b0, 1'b1, 32'h00000200, 32'h00000204, 32'h0020A023);
        check_out("5.0 capture before hold test",
                  32'h00000200, 32'h00000204, 32'h0020A023, 1'b1);
        cycle(1'b0, 1'b0, 1'b0, 32'h00000300, 32'h00000304, 32'h11111111);
        check_out("5.1 hold, inputs changed",
                  32'h00000200, 32'h00000204, 32'h0020A023, 1'b1);
        cycle(1'b0, 1'b0, 1'b0, 32'h00000400, 32'h00000404, 32'h22222222);
        check_out("5.2 hold, second cycle",
                  32'h00000200, 32'h00000204, 32'h0020A023, 1'b1);
        cycle(1'b0, 1'b0, 1'b0, 32'h00000000, 32'h00000000, 32'h00000000);
        check_out("5.3 hold, inputs all zero",
                  32'h00000200, 32'h00000204, 32'h0020A023, 1'b1);
        cycle(1'b0, 1'b0, 1'b0, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF);
        check_out("5.4 hold, inputs all ones",
                  32'h00000200, 32'h00000204, 32'h0020A023, 1'b1);

        //======================================================================
        // 6. Flush
        //======================================================================
        $display("--- 6. Flush ---");
        cycle(1'b0, 1'b1, 1'b0, 32'h00000300, 32'h00000304, 32'h00100093);
        check_out("6.1 flush: bubble, NOP, valid=0", 32'h0, 32'h0, NOP, 1'b0);

        //======================================================================
        // 7. Flush while enable = 1: flush wins
        //======================================================================
        $display("--- 7. Flush beats enable ---");
        cycle(1'b0, 1'b0, 1'b1, 32'h00000400, 32'h00000404, 32'hDEADBEEF);
        check_out("7.0 capture before flush",
                  32'h00000400, 32'h00000404, 32'hDEADBEEF, 1'b1);
        cycle(1'b0, 1'b1, 1'b1, 32'h00000404, 32'h00000408, 32'h00C58533);
        check_out("7.1 flush+enable: flush wins", 32'h0, 32'h0, NOP, 1'b0);
        cycle(1'b0, 1'b1, 1'b1, 32'h00000408, 32'h0000040C, 32'h00B50533);
        check_out("7.2 flush+enable again: still bubble", 32'h0, 32'h0, NOP, 1'b0);

        //======================================================================
        // 8. Reset beats flush and enable
        //======================================================================
        $display("--- 8. Reset priority ---");
        cycle(1'b0, 1'b0, 1'b1, 32'h00000500, 32'h00000504, 32'hCAFEBABE);
        check_out("8.0 capture before reset",
                  32'h00000500, 32'h00000504, 32'hCAFEBABE, 1'b1);
        cycle(1'b1, 1'b1, 1'b1, 32'h00000504, 32'h00000508, 32'h12345678);
        check_out("8.1 reset+flush+enable: reset wins", 32'h0, 32'h0, NOP, 1'b0);
        cycle(1'b0, 1'b0, 1'b1, 32'h00000504, 32'h00000508, 32'h12345678);
        check_out("8.2 capture before reset+enable",
                  32'h00000504, 32'h00000508, 32'h12345678, 1'b1);
        cycle(1'b1, 1'b0, 1'b1, 32'h00000508, 32'h0000050C, 32'h87654321);
        check_out("8.3 reset+enable: reset wins", 32'h0, 32'h0, NOP, 1'b0);
        cycle(1'b0, 1'b0, 1'b1, 32'h00000508, 32'h0000050C, 32'h87654321);
        check_out("8.4 capture before reset+flush",
                  32'h00000508, 32'h0000050C, 32'h87654321, 1'b1);
        cycle(1'b1, 1'b1, 1'b0, 32'h0000050C, 32'h00000510, 32'h0F0F0F0F);
        check_out("8.5 reset+flush: cleared", 32'h0, 32'h0, NOP, 1'b0);

        //======================================================================
        // 9. Enable after flush
        //======================================================================
        $display("--- 9. Enable after flush ---");
        cycle(1'b0, 1'b1, 1'b0, 32'h00000600, 32'h00000604, 32'h11110000);
        check_out("9.1 flush", 32'h0, 32'h0, NOP, 1'b0);
        cycle(1'b0, 1'b0, 1'b0, 32'h00000600, 32'h00000604, 32'h11110000);
        check_out("9.2 hold keeps the bubble", 32'h0, 32'h0, NOP, 1'b0);
        cycle(1'b0, 1'b0, 1'b1, 32'h00000600, 32'h00000604, 32'h00B50533);
        check_out("9.3 enable after flush: valid again",
                  32'h00000600, 32'h00000604, 32'h00B50533, 1'b1);

        //======================================================================
        // 10. Reset after nonzero values
        //======================================================================
        $display("--- 10. Reset after nonzero values ---");
        cycle(1'b0, 1'b0, 1'b1, 32'h7FFFFFFC, 32'h80000000, 32'hFFFFFFFF);
        check_out("10.1 capture extreme values",
                  32'h7FFFFFFC, 32'h80000000, 32'hFFFFFFFF, 1'b1);
        cycle(1'b1, 1'b0, 1'b0, 32'h00000000, 32'h00000000, 32'h00000000);
        check_out("10.2 reset clears extreme values", 32'h0, 32'h0, NOP, 1'b0);

        //======================================================================
        // 11. Repeated reset cycles
        //======================================================================
        $display("--- 11. Repeated reset ---");
        cycle(1'b1, 1'b0, 1'b0, 32'h11111111, 32'h22222222, 32'h33333333);
        check_out("11.1 reset cycle 1", 32'h0, 32'h0, NOP, 1'b0);
        cycle(1'b1, 1'b0, 1'b1, 32'h44444444, 32'h55555555, 32'h66666666);
        check_out("11.2 reset cycle 2 (enable high)", 32'h0, 32'h0, NOP, 1'b0);
        cycle(1'b1, 1'b0, 1'b0, 32'h77777777, 32'h88888888, 32'h99999999);
        check_out("11.3 reset cycle 3", 32'h0, 32'h0, NOP, 1'b0);
        cycle(1'b0, 1'b0, 1'b0, 32'h77777777, 32'h88888888, 32'h99999999);
        check_out("11.4 reset released, hold stays reset", 32'h0, 32'h0, NOP, 1'b0);
        cycle(1'b0, 1'b0, 1'b1, 32'h00000010, 32'h00000014, 32'h00000093);
        check_out("11.5 capture after reset cycles",
                  32'h00000010, 32'h00000014, 32'h00000093, 1'b1);

        //======================================================================
        // 15. Input changes do not reach the outputs before the rising edge
        //======================================================================
        $display("--- 15. Outputs change only on the clock edge ---");
        cycle(1'b0, 1'b0, 1'b1, 32'h00000800, 32'h00000804, 32'h00000093);
        check_out("15.0 baseline capture",
                  32'h00000800, 32'h00000804, 32'h00000093, 1'b1);

        @(negedge clk);
        enable         = 1'b1;
        pc_in          = 32'h00000900;
        pc_plus4_in    = 32'h00000904;
        instruction_in = 32'h11111111;
        #2;                                        // 3 ns before rising edge
        check_out("15.1 inputs changed, no edge: old",
                  32'h00000800, 32'h00000804, 32'h00000093, 1'b1);
        pc_in          = 32'h00000A00;
        pc_plus4_in    = 32'h00000A04;
        instruction_in = 32'h22222222;
        #1;
        check_out("15.2 inputs changed again: still old",
                  32'h00000800, 32'h00000804, 32'h00000093, 1'b1);
        @(posedge clk);
        #1;
        check_out("15.3 after the edge: new values",
                  32'h00000A00, 32'h00000A04, 32'h22222222, 1'b1);

        // An enable pulse that is gone before the edge must not capture
        @(negedge clk);
        enable         = 1'b1;
        pc_in          = 32'h00000B00;
        pc_plus4_in    = 32'h00000B04;
        instruction_in = 32'h33333333;
        #2;
        enable         = 1'b0;                     // removed before the edge
        @(posedge clk);
        #1;
        check_out("15.4 enable glitch between edges ignored",
                  32'h00000A00, 32'h00000A04, 32'h22222222, 1'b1);

        //======================================================================
        // 16. Reset and flush are synchronous
        //======================================================================
        $display("--- 16. Reset/flush are synchronous ---");

        // Reset pulse that never overlaps a rising edge
        @(negedge clk);
        reset          = 1'b1;
        enable         = 1'b0;
        flush          = 1'b0;
        pc_in          = 32'h00000F00;
        pc_plus4_in    = 32'h00000F04;
        instruction_in = 32'h44444444;
        #2;
        check_out("16.1 reset asserted mid-cycle: no effect",
                  32'h00000A00, 32'h00000A04, 32'h22222222, 1'b1);
        reset          = 1'b0;                     // removed before the edge
        @(posedge clk);
        #1;
        check_out("16.2 reset glitch never seen at edge",
                  32'h00000A00, 32'h00000A04, 32'h22222222, 1'b1);

        // Reset held through a rising edge
        @(negedge clk);
        reset          = 1'b1;
        #2;
        check_out("16.3 reset high, before edge: no effect",
                  32'h00000A00, 32'h00000A04, 32'h22222222, 1'b1);
        @(posedge clk);
        #1;
        check_out("16.4 reset takes effect at the edge", 32'h0, 32'h0, NOP, 1'b0);
        reset = 1'b0;

        // Flush held through a rising edge
        cycle(1'b0, 1'b0, 1'b1, 32'h00000C00, 32'h00000C04, 32'h55555555);
        check_out("16.5 recapture before flush test",
                  32'h00000C00, 32'h00000C04, 32'h55555555, 1'b1);
        @(negedge clk);
        flush          = 1'b1;
        enable         = 1'b0;
        #2;
        check_out("16.6 flush high, before edge: no effect",
                  32'h00000C00, 32'h00000C04, 32'h55555555, 1'b1);
        @(posedge clk);
        #1;
        check_out("16.7 flush takes effect at the edge", 32'h0, 32'h0, NOP, 1'b0);
        flush = 1'b0;

        // Flush pulse that never overlaps a rising edge
        cycle(1'b0, 1'b0, 1'b1, 32'h00000D00, 32'h00000D04, 32'h66666666);
        check_out("16.8 recapture before flush glitch",
                  32'h00000D00, 32'h00000D04, 32'h66666666, 1'b1);
        @(negedge clk);
        flush          = 1'b1;
        enable         = 1'b0;
        pc_in          = 32'h00000E00;
        pc_plus4_in    = 32'h00000E04;
        instruction_in = 32'h77777777;
        #2;
        flush          = 1'b0;                     // removed before the edge
        @(posedge clk);
        #1;
        check_out("16.9 flush glitch never seen at edge",
                  32'h00000D00, 32'h00000D04, 32'h66666666, 1'b1);

        //======================================================================
        // Summary
        //======================================================================
        #10;
        $display("==============================================================");
        $display(" IF/ID REGISTER VERIFICATION SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");

        if (failed_tests == 0)
            $display("IF/ID REGISTER VERIFICATION PASSED");
        else
            $display("IF/ID REGISTER VERIFICATION FAILED");

        $finish;
    end

endmodule