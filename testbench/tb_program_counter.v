
`timescale 1ns / 1ps

module tb_program_counter;

    reg clk;
    reg reset;
    reg enable;
    reg [31:0] next_pc;

    wire [31:0] pc;

    integer total_tests;
    integer passed_tests;
    integer failed_tests;

    // Instantiate Program Counter
    program_counter uut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .next_pc(next_pc),
        .pc(pc)
    );

    // Clock generation: 10 ns period
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Generate waveform
    initial begin
        $dumpfile("simulations/program_counter.vcd");
        $dumpvars(0, tb_program_counter);
    end

    // Check expected PC value
    task check_pc;
        input [31:0] expected_pc;
        input [8*80:1] test_name;
        begin
            total_tests = total_tests + 1;

            if (pc !== expected_pc) begin
                failed_tests = failed_tests + 1;
                $display("FAIL: %0s | Expected = %h | Actual = %h",
                         test_name, expected_pc, pc);
            end
            else begin
                passed_tests = passed_tests + 1;
                $display("PASS: %0s | PC = %h", test_name, pc);
            end
        end
    endtask

    // Apply inputs at falling edge and check after rising edge
    task drive_and_check;
        input reset_value;
        input enable_value;
        input [31:0] next_pc_value;
        input [31:0] expected_pc;
        input [8*80:1] test_name;
        begin
            @(negedge clk);

            reset   = reset_value;
            enable  = enable_value;
            next_pc = next_pc_value;

            @(posedge clk);
            #1;

            check_pc(expected_pc, test_name);
        end
    endtask

    // Main test sequence
    initial begin

        total_tests  = 0;
        passed_tests = 0;
        failed_tests = 0;

        reset   = 1'b0;
        enable  = 1'b0;
        next_pc = 32'h00000000;

        $display("------------------------------------------");
        $display(" PROGRAM COUNTER VERIFICATION STARTED");
        $display("------------------------------------------");

        // TEST 1: Check uninitialized PC
        #1;
        check_pc(32'hxxxxxxxx, "Power-up state is unknown");

        // TEST 2: Initial reset
        drive_and_check(1'b1, 1'b0, 32'h00000000,
                        32'h00000000, "Initial reset");

        // TEST 3: Sequential PC updates
        drive_and_check(1'b0, 1'b1, 32'h00000004,
                        32'h00000004, "PC update to 4");

        drive_and_check(1'b0, 1'b1, 32'h00000008,
                        32'h00000008, "PC update to 8");

        drive_and_check(1'b0, 1'b1, 32'h0000000C,
                        32'h0000000C, "PC update to 12");

        drive_and_check(1'b0, 1'b1, 32'h00000010,
                        32'h00000010, "PC update to 16");

        drive_and_check(1'b0, 1'b1, 32'h00000014,
                        32'h00000014, "PC update to 20");

        // TEST 4: Arbitrary next PC values
        drive_and_check(1'b0, 1'b1, 32'h00000100,
                        32'h00000100, "Arbitrary address 0x100");

        drive_and_check(1'b0, 1'b1, 32'h00001000,
                        32'h00001000, "Arbitrary address 0x1000");

        drive_and_check(1'b0, 1'b1, 32'h80000000,
                        32'h80000000, "High address 0x80000000");

        // TEST 5: Hold when enable is low
        drive_and_check(1'b0, 1'b0, 32'h00000004,
                        32'h80000000, "PC hold with enable low");

        drive_and_check(1'b0, 1'b0, 32'hFFFFFFFF,
                        32'h80000000, "PC remains unchanged");

        // TEST 6: Resume after hold
        drive_and_check(1'b0, 1'b1, 32'h00000020,
                        32'h00000020, "PC resumes updating");

        // TEST 7: Consecutive updates
        drive_and_check(1'b0, 1'b1, 32'h00000024,
                        32'h00000024, "Consecutive update 1");

        drive_and_check(1'b0, 1'b1, 32'h00000028,
                        32'h00000028, "Consecutive update 2");

        // TEST 8: Reset from nonzero address
        drive_and_check(1'b1, 1'b0, 32'h00000040,
                        32'h00000000, "Reset from nonzero PC");

        // TEST 9: Reset priority over enable
        drive_and_check(1'b1, 1'b1, 32'h00000100,
                        32'h00000000, "Reset priority over enable");

        // TEST 10: Load after reset
        drive_and_check(1'b0, 1'b1, 32'h00000004,
                        32'h00000004, "Load after reset");

        // TEST 11: Reset while enable is unknown
        drive_and_check(1'b1, 1'bx, 32'h00000100,
                        32'h00000000, "Reset with unknown enable");

        // TEST 12: Multiple reset cycles
        drive_and_check(1'b1, 1'b0, 32'h00000000,
                        32'h00000000, "First reset cycle");

        drive_and_check(1'b1, 1'b0, 32'h00000000,
                        32'h00000000, "Second reset cycle");

        // TEST 13: Boundary values
        drive_and_check(1'b0, 1'b1, 32'h00000000,
                        32'h00000000, "Load zero address");

        drive_and_check(1'b0, 1'b1, 32'hFFFFFFFF,
                        32'hFFFFFFFF, "Load maximum address");

        drive_and_check(1'b0, 1'b1, 32'h7FFFFFFF,
                        32'h7FFFFFFF, "Load maximum positive address");

        // Final report
        $display("");
        $display("------------------------------------------");
        $display(" PROGRAM COUNTER VERIFICATION SUMMARY");
        $display("------------------------------------------");
        $display("Total Tests  : %0d", total_tests);
        $display("Passed       : %0d", passed_tests);
        $display("Failed       : %0d", failed_tests);
        $display("------------------------------------------");

        if (failed_tests == 0)
            $display("PROGRAM COUNTER VERIFICATION PASSED");
        else
            $display("PROGRAM COUNTER VERIFICATION FAILED");

        $display("------------------------------------------");

        $finish;
    end

    // Watchdog timeout
    initial begin
        #5000;
        $display("ERROR: Testbench watchdog timeout!");
        $finish;
    end

endmodule
