`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_riscv_cpu  (first integration test: ADDI / ADD only)
// DUT         : riscv_cpu with simulations/cpu_basic_test.hex
// Description : Runs the 9-instruction program, then checks architectural
//               register values read from the single register file inside
//               id_stage (hierarchy: uut.u_id.u_regfile.registers[n]).
//
// Timing (race-free): 10 ns clock, rising edges at 5, 15, 25 ... ns.
//   - reset is high for the first 3 rising edges and released at a FALLING
//     edge (t = 30 ns), away from any rising edge.
//   - After release, instruction i is written back at the (i+5)th rising edge
//     (no stalls expected for this program). Checks run 1 ns after an edge.
//
// Run from the repository root.
//==============================================================================

`define RF uut.u_id.u_regfile.registers

module tb_riscv_cpu;

    reg clk;
    reg reset;

    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer i;
    integer x0_violations;
    reg     monitor_on;

    riscv_cpu #(
        .INIT_FILE ("simulations/cpu_basic_test.hex")
    ) uut (
        .clk   (clk),
        .reset (reset)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("simulations/tb_riscv_cpu.vcd");
        $dumpvars(0, tb_riscv_cpu);
    end

    // Watchdog
    initial begin
        #20000;
        $display("[FAIL] WATCHDOG TIMEOUT");
        $display("RISCV CPU VERIFICATION FAILED");
        $finish;
    end

    // x0 monitor: sampled at every falling edge once reset is released
    always @(negedge clk) begin
        if (monitor_on && (`RF[0] !== 32'h00000000))
            x0_violations = x0_violations + 1;
    end

    // Compare one value (case inequality catches X/Z)
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

    // Wait for n rising edges, then 1 ns
    task edges;
        input integer n;
        integer j;
        begin
            for (j = 0; j < n; j = j + 1)
                @(posedge clk);
            #1;
        end
    endtask

    initial begin
        total_tests   = 0;
        passed_tests  = 0;
        failed_tests  = 0;
        x0_violations = 0;
        monitor_on    = 1'b0;
        reset         = 1'b1;

        $display("==============================================================");
        $display(" RISC-V CPU Integration Test 1 (ADDI / ADD) Started");
        $display("==============================================================");

        // Hold reset through 3 rising edges (5, 15, 25 ns); release at 30 ns
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
        reset      = 1'b0;
        monitor_on = 1'b1;

        //----------------------------------------------------------------------
        // Pipeline progression: x1 is written back at the 5th edge after
        // release; x8 (the 9th instruction) at the 13th edge. Unnecessary
        // stalls would delay them.
        //----------------------------------------------------------------------
        $display("--- Pipeline progression ---");
        edges(4);
        check("P1 x1 not yet written (4 edges)", `RF[1], 32'h00000000);
        edges(1);
        check("P2 x1 written at 5th edge",       `RF[1], 32'h0000000A);
        edges(7);
        check("P3 x8 not yet written (12 edges)", `RF[8], 32'h00000000);
        edges(1);
        check("P4 x8 written at 13th edge",      `RF[8], 32'h0000001E);

        // Let the pipeline drain well past the last write-back
        edges(10);

        //----------------------------------------------------------------------
        // Final architectural state
        //----------------------------------------------------------------------
        $display("--- Final register values ---");
        check("x0 = 0 (write ignored)", `RF[0], 32'h00000000);
        check("x1 = 10",                `RF[1], 32'h0000000A);
        check("x2 = 20",                `RF[2], 32'h00000014);
        check("x3 = 30 (x1+x2)",        `RF[3], 32'h0000001E);
        check("x4 = 35 (x3+5)",         `RF[4], 32'h00000023);
        check("x5 = 65 (x3+x4)",        `RF[5], 32'h00000041);
        check("x6 = -1",                `RF[6], 32'hFFFFFFFF);
        check("x7 = 9 (x6+x1)",         `RF[7], 32'h00000009);
        check("x8 = 30 (x1+x2)",        `RF[8], 32'h0000001E);
        check("x9 untouched",           `RF[9], 32'h00000000);

        // x0 never non-zero at any sampled point after reset release
        total_tests = total_tests + 1;
        if (x0_violations == 0) begin
            passed_tests = passed_tests + 1;
            $display("[PASS] #%0d x0 stayed zero at every cycle", total_tests);
        end
        else begin
            failed_tests = failed_tests + 1;
            $display("[FAIL] #%0d x0 was non-zero in %0d samples",
                     total_tests, x0_violations);
        end

        $display("==============================================================");
        $display(" RISC-V CPU INTEGRATION TEST 1 SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");
        if (failed_tests == 0)
            $display("RISCV CPU VERIFICATION PASSED");
        else
            $display("RISCV CPU VERIFICATION FAILED");
        $finish;
    end

endmodule