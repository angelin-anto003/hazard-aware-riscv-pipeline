`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_riscv_cpu_branch  (integration test 3: branches)
// DUT         : riscv_cpu with simulations/cpu_branch_test.hex
// Description : Runs a 32-instruction program with 4 taken and 3 not-taken
//               branches, then checks:
//                 - all 32 architectural registers (uut.u_id.u_regfile.registers)
//                 - redirect count, redirect target addresses and the PC of
//                   each redirecting branch (sampled every falling edge)
//                 - IF/ID and ID/EX flush inputs assert on every redirect and
//                   both stages hold a bubble in the following cycle
//                 - no wrong-path instruction ever reaches EX as valid
//                 - no load-use stall occurs (program has no loads)
//
// Timing (race-free): 10 ns clock, rising edges at 5, 15, 25 ... ns.
//   reset is high for 3 rising edges and released at a FALLING edge (30 ns).
//   The monitor samples at falling edges; register checks run 1 ns after a
//   rising edge, long after the program has drained.
//
// Run from the repository root.
//==============================================================================

`define RF uut.u_id.u_regfile.registers

module tb_riscv_cpu_branch;

    reg clk;
    reg reset;

    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer i;

    // Monitor state
    reg        monitor_on;
    reg        rd_prev;
    integer    rd_count;
    integer    br_count;
    integer    nt_count;
    integer    flush_viol;
    integer    bubble_viol;
    integer    wrong_viol;
    integer    stall_count;
    integer    x0_viol;
    reg [31:0] rd_target [0:7];
    reg [31:0] rd_pc     [0:7];

    riscv_cpu #(
        .INIT_FILE ("simulations/cpu_branch_test.hex")
    ) uut (
        .clk   (clk),
        .reset (reset)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("simulations/tb_riscv_cpu_branch.vcd");
        $dumpvars(0, tb_riscv_cpu_branch);
    end

    // Watchdog
    initial begin
        #20000;
        $display("[FAIL] WATCHDOG TIMEOUT");
        $display("RISCV CPU BRANCH VERIFICATION FAILED");
        $finish;
    end

    // PCs of the instructions that must never execute (wrong path)
    function is_wrong;
        input [31:0] pc;
        begin
            is_wrong = (pc == 32'h14) || (pc == 32'h18) ||
                       (pc == 32'h2C) || (pc == 32'h30) ||
                       (pc == 32'h44) || (pc == 32'h48) ||
                       (pc == 32'h54) || (pc == 32'h58);
        end
    endfunction

    //--------------------------------------------------------------------------
    // Monitor: sampled at every falling edge once enabled.
    //--------------------------------------------------------------------------
    always @(negedge clk) begin
        if (monitor_on) begin
            // Cycle after a redirect: ID and EX must hold bubbles
            if (rd_prev) begin
                if (uut.ex_valid !== 1'b0) bubble_viol = bubble_viol + 1;
                if (uut.id_valid !== 1'b0) bubble_viol = bubble_viol + 1;
            end

            if (uut.redirect === 1'b1) begin
                if (rd_count < 8) begin
                    rd_target[rd_count] = uut.redirect_target;
                    rd_pc[rd_count]     = uut.ex_pc;
                end
                rd_count = rd_count + 1;
                // IF/ID and ID/EX flush inputs must both be asserted
                if ((uut.u_if.u_if_id.flush !== 1'b1) ||
                    (uut.u_id.u_id_ex.flush !== 1'b1))
                    flush_viol = flush_viol + 1;
                rd_prev = 1'b1;
            end
            else begin
                rd_prev = 1'b0;
            end

            // Branch bookkeeping
            if ((uut.ex_valid === 1'b1) && (uut.ex_branch === 1'b1)) begin
                br_count = br_count + 1;
                if (uut.redirect !== 1'b1)
                    nt_count = nt_count + 1;
            end

            // Wrong-path instruction reached EX as a valid instruction
            if ((uut.ex_valid === 1'b1) && is_wrong(uut.ex_pc))
                wrong_viol = wrong_viol + 1;

            // No load in this program, so no load-use stall
            if (uut.id_ex_flush !== 1'b0)
                stall_count = stall_count + 1;

            if (`RF[0] !== 32'h00000000)
                x0_viol = x0_viol + 1;
        end
    end

    // Compare one 32-bit value (case inequality catches X/Z)
    task check;
        input [319:0] name;
        input [31:0]  actual;
        input [31:0]  expected;
        begin
            total_tests = total_tests + 1;
            if (actual !== expected) begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s | actual=%h expected=%h",
                         total_tests, name, actual, expected);
            end
            else begin
                passed_tests = passed_tests + 1;
                $display("[PASS] #%0d %0s | value=%h", total_tests, name, actual);
            end
        end
    endtask

    // Pass when a violation counter is zero
    task check_zero;
        input [319:0] name;
        input integer count;
        begin
            total_tests = total_tests + 1;
            if (count != 0) begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s | violations=%0d", total_tests, name, count);
            end
            else begin
                passed_tests = passed_tests + 1;
                $display("[PASS] #%0d %0s | no violations", total_tests, name);
            end
        end
    endtask

    initial begin
        total_tests  = 0;
        passed_tests = 0;
        failed_tests = 0;
        monitor_on   = 1'b0;
        rd_prev      = 1'b0;
        rd_count     = 0;
        br_count     = 0;
        nt_count     = 0;
        flush_viol   = 0;
        bubble_viol  = 0;
        wrong_viol   = 0;
        stall_count  = 0;
        x0_viol      = 0;
        for (i = 0; i < 8; i = i + 1) begin
            rd_target[i] = 32'hxxxxxxxx;
            rd_pc[i]     = 32'hxxxxxxxx;
        end
        reset = 1'b1;

        $display("==============================================================");
        $display(" RISC-V CPU Integration Test 3 (Branches) Started");
        $display("==============================================================");

        // Hold reset through 3 rising edges (5, 15, 25 ns); release at 30 ns
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        @(posedge clk);
        monitor_on = 1'b1;               // monitor starts at the next falling edge

        // ~32 instructions + 4 redirects x 2 bubbles + 4 pipeline stages
        repeat (80) @(posedge clk);
        #1;

        //----------------------------------------------------------------------
        // Branch / redirect behaviour
        //----------------------------------------------------------------------
        $display("--- Branch redirects ---");
        check("B1 redirects observed (expect 4)",   rd_count, 32'd4);
        check("B2 redirect 1 target 0x1C",          rd_target[0], 32'h0000001C);
        check("B3 redirect 2 target 0x34",          rd_target[1], 32'h00000034);
        check("B4 redirect 3 target 0x4C",          rd_target[2], 32'h0000004C);
        check("B5 redirect 4 target 0x5C",          rd_target[3], 32'h0000005C);
        check("B6 redirect 1 from branch at 0x10",  rd_pc[0], 32'h00000010);
        check("B7 redirect 2 from branch at 0x28",  rd_pc[1], 32'h00000028);
        check("B8 redirect 3 from branch at 0x40",  rd_pc[2], 32'h00000040);
        check("B9 redirect 4 from branch at 0x50",  rd_pc[3], 32'h00000050);
        check("B10 branches reaching EX (expect 7)", br_count, 32'd7);
        check("B11 not-taken branches (expect 3)",  nt_count, 32'd3);
        check_zero("B12 IF/ID+ID/EX flush on redirect", flush_viol);
        check_zero("B13 ID, EX bubbles after redirect", bubble_viol);
        check_zero("B14 wrong path never valid in EX",  wrong_viol);
        check_zero("B15 no load-use stalls",            stall_count);

        //----------------------------------------------------------------------
        // Architectural registers
        //----------------------------------------------------------------------
        $display("--- Registers ---");
        check("x0 = 0",                        `RF[0],  32'h00000000);
        check("x1 = 5",                        `RF[1],  32'h00000005);
        check("x2 = 5",                        `RF[2],  32'h00000005);
        check("x3 = 7",                        `RF[3],  32'h00000007);
        check("x4 = -3 (older instr, in MEM)", `RF[4],  32'hFFFFFFFD);
        check("x5 untouched",                  `RF[5],  32'h00000000);
        check("x6 untouched",                  `RF[6],  32'h00000000);
        check("x7 untouched",                  `RF[7],  32'h00000000);
        check("x8 untouched",                  `RF[8],  32'h00000000);
        check("x9 untouched",                  `RF[9],  32'h00000000);
        check("x10 wrong path (beq) = 0",      `RF[10], 32'h00000000);
        check("x11 wrong path (beq) = 0",      `RF[11], 32'h00000000);
        check("x12 beq target = 1",            `RF[12], 32'h00000001);
        check("x13 fall-through = 1",          `RF[13], 32'h00000001);
        check("x14 wrong path (bne) = 0",      `RF[14], 32'h00000000);
        check("x15 wrong path (bne) = 0",      `RF[15], 32'h00000000);
        check("x16 bne target = 1",            `RF[16], 32'h00000001);
        check("x17 fall-through = 1",          `RF[17], 32'h00000001);
        check("x18 wrong path (blt) = 0",      `RF[18], 32'h00000000);
        check("x19 wrong path (blt) = 0",      `RF[19], 32'h00000000);
        check("x20 blt target = 1",            `RF[20], 32'h00000001);
        check("x21 wrong path (bge) = 0",      `RF[21], 32'h00000000);
        check("x22 wrong path (bge) = 0",      `RF[22], 32'h00000000);
        check("x23 bge target = 1",            `RF[23], 32'h00000001);
        check("x24 not-taken blt fall = 1",    `RF[24], 32'h00000001);
        check("x25 untouched",                 `RF[25], 32'h00000000);
        check("x26 = x12+x13 = 2",             `RF[26], 32'h00000002);
        check("x27 = x26+x16 = 3",             `RF[27], 32'h00000003);
        check("x28 = x27+x17 = 4",             `RF[28], 32'h00000004);
        check("x29 = x28+x20 = 5",             `RF[29], 32'h00000005);
        check("x30 = x29+x23 = 6",             `RF[30], 32'h00000006);
        check("x31 = x30+x24 = 7 (final)",     `RF[31], 32'h00000007);
        check_zero("x0 zero at every cycle",   x0_viol);

        $display("==============================================================");
        $display(" RISC-V CPU BRANCH TEST SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");
        if (failed_tests == 0)
            $display("RISCV CPU BRANCH VERIFICATION PASSED");
        else
            $display("RISCV CPU BRANCH VERIFICATION FAILED");
        $finish;
    end

endmodule