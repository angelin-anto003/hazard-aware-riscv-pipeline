`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_riscv_cpu_rtype  (integration test 6: R-type ALU)
// DUT         : riscv_cpu with simulations/cpu_rtype_test.hex
// Description : Runs a 21-instruction program of SUB, AND, OR, XOR and SLT
//               with positive and negative operands, signed SLT edge cases,
//               and dependent chains that exercise EX/MEM and MEM/WB
//               forwarding. The program has no branches or jumps, so no
//               redirect is expected, and no loads, so no stall is expected.
//
// Checks: no redirect, no load-use stall, all 32 architectural registers,
//         and x0 at every sampled cycle.
//
// Timing (race-free): 10 ns clock, rising edges at 5, 15, 25 ... ns.
//   reset is high for 3 rising edges and released at a FALLING edge (30 ns).
//   The monitor samples at falling edges; register checks run after the
//   pipeline has drained.
//
// Run from the repository root.
//==============================================================================

`define RF uut.u_id.u_regfile.registers

module tb_riscv_cpu_rtype;

    reg clk;
    reg reset;

    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer i;

    // Monitor state
    reg        monitor_on;
    integer    rd_count;
    integer    stall_count;
    integer    x0_viol;

    riscv_cpu #(
        .INIT_FILE ("simulations/cpu_rtype_test.hex")
    ) uut (
        .clk   (clk),
        .reset (reset)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("simulations/tb_riscv_cpu_rtype.vcd");
        $dumpvars(0, tb_riscv_cpu_rtype);
    end

    // Watchdog
    initial begin
        #20000;
        $display("[FAIL] WATCHDOG TIMEOUT");
        $display("RISCV CPU RTYPE VERIFICATION FAILED");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Monitor: sampled at every falling edge once enabled
    //--------------------------------------------------------------------------
    always @(negedge clk) begin
        if (monitor_on) begin
            // No branch or jump in this program, so no redirect may occur
            if (uut.redirect === 1'b1)
                rd_count = rd_count + 1;

            // No load in this program, so no load-use stall may occur
            if (uut.id_ex_flush !== 1'b0)
                stall_count = stall_count + 1;

            if (`RF[0] !== 32'h00000000)
                x0_viol = x0_viol + 1;
        end
    end

    //--------------------------------------------------------------------------
    // Checks
    //--------------------------------------------------------------------------
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
        rd_count     = 0;
        stall_count  = 0;
        x0_viol      = 0;
        reset        = 1'b1;

        $display("==============================================================");
        $display(" RISC-V CPU Integration Test 6 (R-type ALU) Started");
        $display("==============================================================");

        // Reset through 3 rising edges (5, 15, 25 ns); release at 30 ns
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        @(posedge clk);
        monitor_on = 1'b1;

        // 21 instructions + pipeline drain (no redirects or stalls expected)
        repeat (60) @(posedge clk);
        #1;

        //----------------------------------------------------------------------
        // Pipeline behaviour
        //----------------------------------------------------------------------
        $display("--- Pipeline behaviour ---");
        check("P1 no redirects (no branch or jump)", rd_count, 32'd0);
        check_zero("P2 no load-use stalls",          stall_count);
        check_zero("P3 x0 zero at every cycle",      x0_viol);

        //----------------------------------------------------------------------
        // Architectural registers
        //----------------------------------------------------------------------
        $display("--- Registers ---");
        check("R00 x0 = 0 (sub x0 discarded)",          `RF[0],  32'h00000000);
        check("R01 x1 = 10",                            `RF[1],  32'h0000000A);
        check("R02 x2 = -3",                            `RF[2],  32'hFFFFFFFD);
        check("R03 x3 = 10-(-3) = 13",                  `RF[3],  32'h0000000D);
        check("R04 x4 = -3-10 = -13",                   `RF[4],  32'hFFFFFFF3);
        check("R05 x5 = 13-(-13) = 26",                 `RF[5],  32'h0000001A);
        check("R06 x6 = 10 AND -3 = 8",                 `RF[6],  32'h00000008);
        check("R07 x7 = 10 OR -3 = -1",                 `RF[7],  32'hFFFFFFFF);
        check("R08 x8 = 8 XOR -1 = -9",                 `RF[8],  32'hFFFFFFF7);
        check("R09 x9 = x1 XOR x1 = 0",                 `RF[9],  32'h00000000);
        check("R10 x10 = (-3 < 10) signed = 1",         `RF[10], 32'h00000001);
        check("R11 x11 = (10 < -3) signed = 0",         `RF[11], 32'h00000000);
        check("R12 x12 = (13 < -3) signed = 0",         `RF[12], 32'h00000000);
        check("R13 x13 untouched = 0",                  `RF[13], 32'h00000000);
        check("R14 x14 = 0 - 1 = -1",                   `RF[14], 32'hFFFFFFFF);
        check("R15 x15 = (-1 < 0) signed = 1",          `RF[15], 32'h00000001);
        check("R16 x16 = 1 XOR -1 = -2",                `RF[16], 32'hFFFFFFFE);
        check("R17 x17 = -2 OR 1 = -1",                 `RF[17], 32'hFFFFFFFF);
        check("R18 x18 = -1 AND 10 = 10",               `RF[18], 32'h0000000A);
        check("R19 x19 = 10 - 10 = 0",                  `RF[19], 32'h00000000);
        check("R20 x20 = 26 OR -13 = -5",               `RF[20], 32'hFFFFFFFB);
        check("R21 x21 untouched = 0",                  `RF[21], 32'h00000000);
        check("R22 x22 untouched = 0",                  `RF[22], 32'h00000000);
        check("R23 x23 untouched = 0",                  `RF[23], 32'h00000000);
        check("R24 x24 untouched = 0",                  `RF[24], 32'h00000000);
        check("R25 x25 untouched = 0",                  `RF[25], 32'h00000000);
        check("R26 x26 untouched = 0",                  `RF[26], 32'h00000000);
        check("R27 x27 untouched = 0",                  `RF[27], 32'h00000000);
        check("R28 x28 untouched = 0",                  `RF[28], 32'h00000000);
        check("R29 x29 untouched = 0",                  `RF[29], 32'h00000000);
        check("R30 x30 untouched = 0",                  `RF[30], 32'h00000000);
        check("R31 x31 = -5 - 10 = -15",                `RF[31], 32'hFFFFFFF1);

        //----------------------------------------------------------------------
        // Summary
        //----------------------------------------------------------------------
        $display("==============================================================");
        $display(" RISC-V CPU R-TYPE TEST SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");
        if (failed_tests == 0)
            $display("RISCV CPU RTYPE VERIFICATION PASSED");
        else
            $display("RISCV CPU RTYPE VERIFICATION FAILED");
        $finish;
    end

endmodule