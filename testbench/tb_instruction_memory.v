
`timescale 1ns / 1ps

module tb_instruction_memory;

    // Testbench signals
    reg  [31:0] addr_z;
    wire [31:0] instr_z;

    reg  [31:0] addr_f;
    wire [31:0] instr_f;

    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer k;
    integer j;
    integer b;
    integer fails_before;

    reg [31:0] tmp_addr;
    reg [31:0] snap;

    // Default zero-initialized memory
    instruction_memory uut_zero (
        .address(addr_z),
        .instruction(instr_z)
    );

    // Memory initialized from hexadecimal file
    instruction_memory #(
        .INIT_FILE("simulations/imem_test.hex")
    ) uut_file (
        .address(addr_f),
        .instruction(instr_f)
    );

    // Generate waveform
    initial begin
        $dumpfile("simulations/instruction_memory.vcd");
        $dumpvars(0, tb_instruction_memory);
    end

    // Watchdog timeout
    initial begin
        #1000000;
        $display("[FAIL] WATCHDOG TIMEOUT");
        $display("INSTRUCTION MEMORY VERIFICATION FAILED");
        $finish;
    end

    // Independent expected-data table
    function [31:0] exp_file;
        input integer idx;
        begin
            case (idx)
                0:   exp_file = 32'h00500093;
                1:   exp_file = 32'h00A00113;
                2:   exp_file = 32'h002081B3;
                3:   exp_file = 32'h00312223;
                4:   exp_file = 32'hFE000EE3;
                5:   exp_file = 32'h008000EF;
                10:  exp_file = 32'hA5A5A5A5;
                128: exp_file = 32'hCAFEF00D;
                255: exp_file = 32'hDEADBEEF;
                default: exp_file = 32'h00000000;
            endcase
        end
    endfunction

    // Main comparison task
    task check_val;
        input [319:0] name;
        input [31:0] addr;
        input [31:0] actual;
        input [31:0] expected;
        input show_pass;

        begin
            total_tests = total_tests + 1;

            if (actual !== expected) begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] %0s | address=%h actual=%h expected=%h",
                         name, addr, actual, expected);
            end
            else begin
                passed_tests = passed_tests + 1;

                if (show_pass)
                    $display("[PASS] %0s | address=%h data=%h",
                             name, addr, actual);
            end
        end
    endtask

    // Check default memory
    task chk_z;
        input [319:0] name;
        input [31:0] addr;
        input [31:0] expected;
        input show_pass;

        begin
            addr_z = addr;
            #1;
            check_val(name, addr, instr_z, expected, show_pass);
        end
    endtask

    // Check file-loaded memory
    task chk_f;
        input [319:0] name;
        input [31:0] addr;
        input [31:0] expected;
        input show_pass;

        begin
            addr_f = addr;
            #1;
            check_val(name, addr, instr_f, expected, show_pass);
        end
    endtask

    // Check both instances return zero
    task chk_both_zero;
        input [319:0] name;
        input [31:0] addr;
        input show_pass;

        begin
            chk_z(name, addr, 32'h00000000, show_pass);
            chk_f(name, addr, 32'h00000000, show_pass);
        end
    endtask

    // Report sweep results
    task sweep_end;
        input [319:0] name;
        input [31:0] before;

        begin
            if (failed_tests == before)
                $display("[PASS] %0s | sweep completed, no mismatches", name);
            else
                $display("[FAIL] %0s | sweep had %0d mismatches",
                         name, failed_tests - before);
        end
    endtask

    // Main test sequence
    initial begin

        total_tests  = 0;
        passed_tests = 0;
        failed_tests = 0;

        addr_z = 32'h00000000;
        addr_f = 32'h00000000;

        #1;

        $display("==============================================================");
        $display(" INSTRUCTION MEMORY VERIFICATION STARTED");
        $display("==============================================================");

        //==============================================================
        // TEST GROUP 1: Default initialization
        //==============================================================

        $display("--- 1. Initialization ---");

        chk_z("First location is zero",
              32'h00000000, 32'h0, 1'b1);

        chk_z("Last location is zero",
              32'h000003FC, 32'h0, 1'b1);

        chk_z("Middle location is zero",
              32'h00000200, 32'h0, 1'b1);

        fails_before = failed_tests;

        for (k = 0; k < 256; k = k + 1)
            chk_z("Default entry is zero",
                  k * 4, 32'h0, 1'b0);

        sweep_end("All 256 default entries zero", fails_before);

        //==============================================================
        // TEST GROUP 2: Address decoding
        //==============================================================

        $display("--- 2. Address decoding ---");

        chk_f("Word 0",   32'h00000000, 32'h00500093, 1'b1);
        chk_f("Word 1",   32'h00000004, 32'h00A00113, 1'b1);
        chk_f("Word 2",   32'h00000008, 32'h002081B3, 1'b1);
        chk_f("Word 3",   32'h0000000C, 32'h00312223, 1'b1);
        chk_f("Word 4",   32'h00000010, 32'hFE000EE3, 1'b1);
        chk_f("Word 5",   32'h00000014, 32'h008000EF, 1'b1);
        chk_f("Word 6",   32'h00000018, 32'h00000000, 1'b1);
        chk_f("Word 10",  32'h00000028, 32'hA5A5A5A5, 1'b1);
        chk_f("Word 127", 32'h000001FC, 32'h00000000, 1'b1);
        chk_f("Word 128", 32'h00000200, 32'hCAFEF00D, 1'b1);
        chk_f("Word 129", 32'h00000204, 32'h00000000, 1'b1);
        chk_f("Word 254", 32'h000003F8, 32'h00000000, 1'b1);
        chk_f("Word 255", 32'h000003FC, 32'hDEADBEEF, 1'b1);

        // Check every word against independent expected table
        fails_before = failed_tests;

        for (k = 0; k < 256; k = k + 1)
            chk_f("Word matches expected table",
                  k * 4, exp_file(k), 1'b0);

        sweep_end("All 256 words match table", fails_before);

        //==============================================================
        // TEST GROUP 3: Invalid addresses
        //==============================================================

        $display("--- 3. Invalid addresses ---");

        // Misaligned addresses
        chk_both_zero("Misaligned 01", 32'h00000001, 1'b1);
        chk_both_zero("Misaligned 02", 32'h00000002, 1'b1);
        chk_both_zero("Misaligned 03", 32'h00000003, 1'b1);
        chk_both_zero("Misaligned 05", 32'h00000005, 1'b1);
        chk_both_zero("Misaligned 06", 32'h00000006, 1'b1);
        chk_both_zero("Misaligned 07", 32'h00000007, 1'b1);
        chk_both_zero("Misaligned 201", 32'h00000201, 1'b1);
        chk_both_zero("Misaligned 3FD", 32'h000003FD, 1'b1);
        chk_both_zero("Misaligned 3FE", 32'h000003FE, 1'b1);
        chk_both_zero("Misaligned 3FF", 32'h000003FF, 1'b1);

        // Out-of-range addresses
        chk_both_zero("Out of range 400", 32'h00000400, 1'b1);
        chk_both_zero("Out of range 404", 32'h00000404, 1'b1);
        chk_both_zero("Out of range 800", 32'h00000800, 1'b1);
        chk_both_zero("Out of range 10000", 32'h00010000, 1'b1);

        // High addresses
        chk_both_zero("High address 40000000", 32'h40000000, 1'b1);
        chk_both_zero("High address 7FFFFFFC", 32'h7FFFFFFC, 1'b1);
        chk_both_zero("High address 80000000", 32'h80000000, 1'b1);
        chk_both_zero("High address 80000004", 32'h80000004, 1'b1);
        chk_both_zero("High address 800003FC", 32'h800003FC, 1'b1);
        chk_both_zero("High address FFFFFFFC", 32'hFFFFFFFC, 1'b1);
        chk_both_zero("High address FFFFFFFF", 32'hFFFFFFFF, 1'b1);

        // Sweep all misaligned addresses in the memory range
        fails_before = failed_tests;

        for (k = 0; k < 256; k = k + 1)
            for (j = 1; j < 4; j = j + 1)
                chk_f("Misaligned address sweep",
                      k * 4 + j, 32'h0, 1'b0);

        sweep_end("All misaligned addresses return zero", fails_before);

        // Sweep out-of-range aliases
        fails_before = failed_tests;

        for (k = 0; k < 256; k = k + 1) begin
            chk_f("Alias plus 0x400",
                  32'h00000400 + k * 4, 32'h0, 1'b0);

            chk_f("Alias plus 0x80000000",
                  32'h80000000 + k * 4, 32'h0, 1'b0);

            chk_f("Alias high address",
                  32'hFFFFFC00 + k * 4, 32'h0, 1'b0);
        end

        sweep_end("Out-of-range aliases rejected", fails_before);

        // Test each upper address bit
        fails_before = failed_tests;

        for (b = 10; b < 32; b = b + 1) begin

            tmp_addr = 32'd1 << b;

            chk_both_zero("Single upper address bit",
                          tmp_addr, 1'b0);

            chk_f("Upper bit combined with 3FC",
                  tmp_addr | 32'h000003FC, 32'h0, 1'b0);
        end

        sweep_end("Every upper address bit rejected", fails_before);

        //==============================================================
        // TEST GROUP 4: Asynchronous read
        //==============================================================

        $display("--- 4. Asynchronous read ---");

        chk_f("Immediate read word 0",
              32'h00000000, 32'h00500093, 1'b1);

        chk_f("Immediate read word 1",
              32'h00000004, 32'h00A00113, 1'b1);

        chk_f("Immediate read word 2",
              32'h00000008, 32'h002081B3, 1'b1);

        chk_f("Immediate read word 4",
              32'h00000010, 32'hFE000EE3, 1'b1);

        chk_f("Immediate read word 128",
              32'h00000200, 32'hCAFEF00D, 1'b1);

        // Change address without any clock
        addr_f = 32'h00000000;
        #1;
        snap = instr_f;

        addr_f = 32'h00000004;
        #1;

        total_tests = total_tests + 1;

        if (instr_f !== snap) begin
            passed_tests = passed_tests + 1;
            $display("[PASS] Output changed with address");
        end
        else begin
            failed_tests = failed_tests + 1;
            $display("[FAIL] Output did not change with address");
        end

        // Verify stable output while address remains unchanged
        addr_f = 32'h00000008;
        #1;
        snap = instr_f;
        #50;

        check_val("Output stable while address held",
                  32'h00000008, instr_f, snap, 1'b1);

        check_val("Stable output equals word 2",
                  32'h00000008, instr_f,
                  32'h002081B3, 1'b1);

        // Compare two independent memory instances
        addr_z = 32'h00000200;
        addr_f = 32'h00000200;
        #1;

        check_val("Default memory remains zero",
                  32'h00000200, instr_z, 32'h0, 1'b1);

        check_val("Loaded memory contains data",
                  32'h00000200, instr_f,
                  32'hCAFEF00D, 1'b1);

        //==============================================================
        // TEST GROUP 5: Initialization file loading
        //==============================================================

        $display("--- 5. Initialization file loading ---");

        chk_f("Loaded ADDI instruction",
              32'h00000000, 32'h00500093, 1'b1);

        chk_f("Loaded ADDI instruction",
              32'h00000004, 32'h00A00113, 1'b1);

        chk_f("Loaded ADD instruction",
              32'h00000008, 32'h002081B3, 1'b1);

        chk_f("Loaded SW instruction",
              32'h0000000C, 32'h00312223, 1'b1);

        chk_f("Loaded BEQ instruction",
              32'h00000010, 32'hFE000EE3, 1'b1);

        chk_f("Loaded JAL instruction",
              32'h00000014, 32'h008000EF, 1'b1);

        chk_f("Loaded index 10",
              32'h00000028, 32'hA5A5A5A5, 1'b1);

        chk_f("Loaded index 128",
              32'h00000200, 32'hCAFEF00D, 1'b1);

        chk_f("Loaded index 255",
              32'h000003FC, 32'hDEADBEEF, 1'b1);

        // Locations not included in the file remain zero
        chk_f("Uninitialized index 6",
              32'h00000018, 32'h0, 1'b1);

        chk_f("Uninitialized index 7",
              32'h0000001C, 32'h0, 1'b1);

        chk_f("Uninitialized index 9",
              32'h00000024, 32'h0, 1'b1);

        chk_f("Uninitialized index 11",
              32'h0000002C, 32'h0, 1'b1);

        chk_f("Uninitialized index 127",
              32'h000001FC, 32'h0, 1'b1);

        chk_f("Uninitialized index 129",
              32'h00000204, 32'h0, 1'b1);

        chk_f("Uninitialized index 254",
              32'h000003F8, 32'h0, 1'b1);

        // Default instance remains unaffected
        chk_z("Default instance index 0",
              32'h00000000, 32'h0, 1'b1);

        chk_z("Default instance index 255",
              32'h000003FC, 32'h0, 1'b1);

        //==============================================================
        // TEST GROUP 6: Boundary and robustness
        //==============================================================

        $display("--- 6. Boundary and robustness ---");

        chk_f("First valid entry",
              32'h00000000, 32'h00500093, 1'b1);

        chk_f("Last valid entry",
              32'h000003FC, 32'hDEADBEEF, 1'b1);

        chk_f("Address 3F8",
              32'h000003F8, 32'h00000000, 1'b1);

        chk_f("Address 3FC",
              32'h000003FC, 32'hDEADBEEF, 1'b1);

        chk_f("Address 400 invalid",
              32'h00000400, 32'h00000000, 1'b1);

        chk_f("Return to address 3FC",
              32'h000003FC, 32'hDEADBEEF, 1'b1);

        chk_f("Address 1FC",
              32'h000001FC, 32'h00000000, 1'b1);

        chk_f("Address 200",
              32'h00000200, 32'hCAFEF00D, 1'b1);

        chk_f("Address 204",
              32'h00000204, 32'h00000000, 1'b1);

        // Invalid-to-valid and valid-to-invalid transitions
        chk_f("Invalid address 1",
              32'h00000001, 32'h0, 1'b1);

        chk_f("Valid address 0",
              32'h00000000, 32'h00500093, 1'b1);

        chk_f("Invalid address 2",
              32'h00000002, 32'h0, 1'b1);

        chk_f("Valid address 4",
              32'h00000004, 32'h00A00113, 1'b1);

        chk_f("Invalid FFFFFFFF",
              32'hFFFFFFFF, 32'h0, 1'b1);

        chk_f("Valid address 3FC",
              32'h000003FC, 32'hDEADBEEF, 1'b1);

        chk_f("Invalid FFFFFFFC",
              32'hFFFFFFFC, 32'h0, 1'b1);

        chk_f("Valid address 200",
              32'h00000200, 32'hCAFEF00D, 1'b1);

        chk_f("Invalid 80000200",
              32'h80000200, 32'h0, 1'b1);

        chk_f("Valid address 28",
              32'h00000028, 32'hA5A5A5A5, 1'b1);

        // Repeated reads
        for (k = 0; k < 5; k = k + 1)
            chk_f("Repeated read at 3FC",
                  32'h000003FC, 32'hDEADBEEF, 1'b1);

        for (k = 0; k < 5; k = k + 1)
            chk_f("Repeated read at 000",
                  32'h00000000, 32'h00500093, 1'b1);

        // Ascending and descending address walk
        fails_before = failed_tests;

        for (k = 0; k < 8; k = k + 1)
            chk_f("Ascending address walk",
                  k * 4, exp_file(k), 1'b0);

        for (k = 7; k >= 0; k = k - 1)
            chk_f("Descending address walk",
                  k * 4, exp_file(k), 1'b0);

        sweep_end("Ascending and descending walk", fails_before);

        //==============================================================
        // FINAL SUMMARY
        //==============================================================

        #10;

        $display("");
        $display("==============================================================");
        $display(" INSTRUCTION MEMORY VERIFICATION SUMMARY");
        $display("==============================================================");

        $display("Total Tests : %0d", total_tests);
        $display("Passed      : %0d", passed_tests);
        $display("Failed      : %0d", failed_tests);

        $display("==============================================================");

        if (failed_tests == 0)
            $display("INSTRUCTION MEMORY VERIFICATION PASSED");
        else
            $display("INSTRUCTION MEMORY VERIFICATION FAILED");

        $display("==============================================================");

        $finish;
    end

endmodule
