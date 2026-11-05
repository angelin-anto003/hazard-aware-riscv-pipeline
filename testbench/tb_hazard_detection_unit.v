
`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_hazard_detection_unit
// DUT         : hazard_detection_unit
// Description : Self-checking Verilog-2001 testbench.
//
// Tests:
//   1. Directed tests (25 cases)
//   2. Exhaustive sweep:
//      mem_read (2) x rd (32) x rs1 (32) x rs2 (32)
//      = 65,536 combinations
//
// Total expected tests: 65,561
//==============================================================================

module tb_hazard_detection_unit;

    // DUT inputs
    reg        id_ex_mem_read;
    reg  [4:0] id_ex_rd_addr;
    reg  [4:0] if_id_rs1_addr;
    reg  [4:0] if_id_rs2_addr;

    // DUT outputs
    wire       pc_write;
    wire       if_id_write;
    wire       id_ex_flush;

    // Test bookkeeping
    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer fails_before;

    integer m;
    integer rd;
    integer r1;
    integer r2;

    reg verbose;
    reg exp_hazard;

    // Temporary registers for exhaustive sweep
    reg       t_mr;
    reg [4:0] t_rd;
    reg [4:0] t_rs1;
    reg [4:0] t_rs2;

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------

    hazard_detection_unit uut (
        .id_ex_mem_read (id_ex_mem_read),
        .id_ex_rd_addr  (id_ex_rd_addr),
        .if_id_rs1_addr (if_id_rs1_addr),
        .if_id_rs2_addr (if_id_rs2_addr),
        .pc_write       (pc_write),
        .if_id_write    (if_id_write),
        .id_ex_flush    (id_ex_flush)
    );

    //--------------------------------------------------------------------------
    // Waveform generation
    //--------------------------------------------------------------------------

    initial begin
        $dumpfile("simulations/hazard_detection_unit.vcd");
        $dumpvars(0, tb_hazard_detection_unit);
    end

    //--------------------------------------------------------------------------
    // Watchdog
    //--------------------------------------------------------------------------

    initial begin
        #10000000;
        $display("[FAIL] WATCHDOG TIMEOUT: simulation did not finish");
        $display("HAZARD DETECTION UNIT VERIFICATION FAILED");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Self-checking task
    //--------------------------------------------------------------------------

    task chk;
        input [319:0] name;
        input         mr;
        input [4:0]   rd_a;
        input [4:0]   rs1;
        input [4:0]   rs2;
        input         hazard;

        begin
            id_ex_mem_read = mr;
            id_ex_rd_addr  = rd_a;
            if_id_rs1_addr = rs1;
            if_id_rs2_addr = rs2;

            #1;

            total_tests = total_tests + 1;

            if ((pc_write !== ~hazard) ||
                (if_id_write !== ~hazard) ||
                (id_ex_flush !== hazard)) begin

                failed_tests = failed_tests + 1;

                $display("[FAIL] #%0d %0s | mr=%b rd=%0d rs1=%0d rs2=%0d",
                         total_tests, name, mr, rd_a, rs1, rs2);

                $display("       pc_write=%b (exp %b) if_id_write=%b (exp %b) id_ex_flush=%b (exp %b)",
                         pc_write, ~hazard,
                         if_id_write, ~hazard,
                         id_ex_flush, hazard);
            end
            else begin
                passed_tests = passed_tests + 1;

                if (verbose) begin
                    $display("[PASS] #%0d %0s | stall=%b",
                             total_tests, name, hazard);
                end
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Sweep summary task
    //--------------------------------------------------------------------------

    task sweep_end;
        input [319:0] name;
        input integer before;

        begin
            if (failed_tests == before) begin
                $display("[PASS] %0s | sweep completed, no mismatches", name);
            end
            else begin
                $display("[FAIL] %0s | sweep had %0d mismatches",
                         name, failed_tests - before);
            end
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

        id_ex_mem_read = 1'b0;
        id_ex_rd_addr  = 5'd0;
        if_id_rs1_addr = 5'd0;
        if_id_rs2_addr = 5'd0;

        #1;

        $display("==============================================================");
        $display(" Hazard Detection Unit Self-Checking Testbench Started");
        $display("==============================================================");

        //----------------------------------------------------------------------
        // 1. Load matching rs1 / rs2 / both
        //----------------------------------------------------------------------

        $display("--- 1. Load matching rs1 / rs2 / both ---");

        chk("1.1 load rd matches rs1 only",
            1'b1, 5'd5, 5'd5, 5'd6, 1'b1);

        chk("1.2 load rd matches rs2 only",
            1'b1, 5'd5, 5'd6, 5'd5, 1'b1);

        chk("1.3 load rd matches both",
            1'b1, 5'd5, 5'd5, 5'd5, 1'b1);

        //----------------------------------------------------------------------
        // 2. No match
        //----------------------------------------------------------------------

        $display("--- 2. No match ---");

        chk("2.1 load, no match",
            1'b1, 5'd5, 5'd6, 5'd7, 1'b0);

        chk("2.2 load, different registers",
            1'b1, 5'd10, 5'd11, 5'd9, 1'b0);

        //----------------------------------------------------------------------
        // 3. Non-load instructions
        //----------------------------------------------------------------------

        $display("--- 3. Non-load instructions ---");

        chk("3.1 non-load, matches rs1",
            1'b0, 5'd5, 5'd5, 5'd6, 1'b0);

        chk("3.2 non-load, matches rs2",
            1'b0, 5'd5, 5'd6, 5'd5, 1'b0);

        chk("3.3 non-load, matches both",
            1'b0, 5'd5, 5'd5, 5'd5, 1'b0);

        //----------------------------------------------------------------------
        // 4. Destination x0
        //----------------------------------------------------------------------

        $display("--- 4. Destination x0 ---");

        chk("4.1 load rd=x0, rs1=x0",
            1'b1, 5'd0, 5'd0, 5'd6, 1'b0);

        chk("4.2 load rd=x0, rs2=x0",
            1'b1, 5'd0, 5'd6, 5'd0, 1'b0);

        chk("4.3 load rd=x0, both x0",
            1'b1, 5'd0, 5'd0, 5'd0, 1'b0);

        chk("4.4 load rd=x0, nonzero sources",
            1'b1, 5'd0, 5'd3, 5'd4, 1'b0);

        //----------------------------------------------------------------------
        // 5. Boundary registers
        //----------------------------------------------------------------------

        $display("--- 5. Boundary registers ---");

        chk("5.1 load x1 matches rs1",
            1'b1, 5'd1, 5'd1, 5'd2, 1'b1);

        chk("5.2 load x1 matches rs2",
            1'b1, 5'd1, 5'd2, 5'd1, 1'b1);

        chk("5.3 load x31 matches rs1",
            1'b1, 5'd31, 5'd31, 5'd2, 1'b1);

        chk("5.4 load x31 matches rs2",
            1'b1, 5'd31, 5'd2, 5'd31, 1'b1);

        chk("5.5 load x31 matches both",
            1'b1, 5'd31, 5'd31, 5'd31, 1'b1);

        chk("5.6 load x31, sources x30/x1",
            1'b1, 5'd31, 5'd30, 5'd1, 1'b0);

        chk("5.7 load x1, sources x0/x31",
            1'b1, 5'd1, 5'd0, 5'd31, 1'b0);

        //----------------------------------------------------------------------
        // 6. Back-to-back changes
        //----------------------------------------------------------------------

        $display("--- 6. Back-to-back changes ---");

        chk("6.1 hazard",
            1'b1, 5'd9, 5'd9, 5'd1, 1'b1);

        chk("6.2 clears when mem_read drops",
            1'b0, 5'd9, 5'd9, 5'd1, 1'b0);

        chk("6.3 hazard again",
            1'b1, 5'd9, 5'd9, 5'd1, 1'b1);

        chk("6.4 clears when rd changes",
            1'b1, 5'd8, 5'd9, 5'd1, 1'b0);

        chk("6.5 hazard again",
            1'b1, 5'd9, 5'd9, 5'd1, 1'b1);

        chk("6.6 clears when rs1 changes",
            1'b1, 5'd9, 5'd10, 5'd1, 1'b0);

        //----------------------------------------------------------------------
        // 7. Exhaustive sweep: 65,536 combinations
        //----------------------------------------------------------------------

        $display("--- 7. Exhaustive sweep (65536 tests) ---");

        verbose      = 1'b0;
        fails_before = failed_tests;

        for (m = 0; m < 2; m = m + 1) begin

            for (rd = 0; rd < 32; rd = rd + 1) begin

                for (r1 = 0; r1 < 32; r1 = r1 + 1) begin

                    for (r2 = 0; r2 < 32; r2 = r2 + 1) begin

                        // Convert integer loop values into fixed-width regs
                        t_mr  = m;
                        t_rd  = rd;
                        t_rs1 = r1;
                        t_rs2 = r2;

                        // Independent reference model
                        exp_hazard = 1'b0;

                        if (m == 1) begin
                            if (rd != 0) begin

                                if (r1 == rd) begin
                                    exp_hazard = 1'b1;
                                end

                                if (r2 == rd) begin
                                    exp_hazard = 1'b1;
                                end

                            end
                        end

                        chk("7 sweep",
                            t_mr, t_rd, t_rs1, t_rs2, exp_hazard);

                    end
                end
            end
        end

        sweep_end("7 exhaustive sweep (65536 tests)", fails_before);

        verbose = 1'b1;

        //----------------------------------------------------------------------
        // Final summary
        //----------------------------------------------------------------------

        #5;

        $display("==============================================================");
        $display(" HAZARD DETECTION UNIT VERIFICATION SUMMARY");
        $display("==============================================================");

        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);

        $display("==============================================================");

        if (failed_tests == 0) begin
            $display("HAZARD DETECTION UNIT VERIFICATION PASSED");
        end
        else begin
            $display("HAZARD DETECTION UNIT VERIFICATION FAILED");
        end

        $finish;

    end

endmodule
