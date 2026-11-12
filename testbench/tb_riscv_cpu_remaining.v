`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_riscv_cpu_remaining  (integration test 5)
// DUT         : riscv_cpu with simulations/cpu_remaining_test.hex
// Description : Covers the instructions not exercised by tests 1-4:
//               LUI, AUIPC, SLTU, ANDI, ORI, XORI, BLTU, BGEU, and signed vs
//               unsigned comparison edge cases.
//
//               Four BLTU/BGEU redirects, two not-taken BLTU/BGEU, and wrong-path
//               instructions after every taken branch.
//
// Checks: redirect count, redirect PCs and targets, branch count, not-taken
//         count, flush/bubble behaviour, older instruction in MEM, wrong-path
//         suppression, no load-use stalls, all 32 architectural registers,
//         and x0 at every cycle.
//
// Timing (race-free): 10 ns clock, rising edges at 5, 15, 25 ... ns.
//   reset is high for 3 rising edges and released at a FALLING edge (30 ns).
//   The monitor samples at falling edges; register checks run after the
//   pipeline has drained.
//
// Run from the repository root.
//==============================================================================

`define RF uut.u_id.u_regfile.registers

module tb_riscv_cpu_remaining;

    reg clk;
    reg reset;

    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer i;

    // Monitor state
    reg        monitor_on;
    reg        rd_prev;
    reg [31:0] prev_target;
    integer    rd_count;
    integer    br_count;
    integer    nt_count;
    reg [31:0] rd_pc     [0:7];
    reg [31:0] rd_target [0:7];
    integer    pc_viol;
    integer    bubble_viol;
    integer    flush_viol;
    integer    older_viol;
    integer    wrong_viol;
    integer    stall_count;
    integer    x0_viol;

    riscv_cpu #(
        .INIT_FILE ("simulations/cpu_remaining_test.hex")
    ) uut (
        .clk   (clk),
        .reset (reset)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("simulations/tb_riscv_cpu_remaining.vcd");
        $dumpvars(0, tb_riscv_cpu_remaining);
    end

    // Watchdog
    initial begin
        #20000;
        $display("[FAIL] WATCHDOG TIMEOUT");
        $display("RISCV CPU REMAINING VERIFICATION FAILED");
        $finish;
    end

    // PCs of wrong-path instructions (must never be valid in EX)
    function is_wrong;
        input [31:0] pc;
        begin
            is_wrong = (pc == 32'h38) || (pc == 32'h3C) ||
                       (pc == 32'h48) || (pc == 32'h4C) ||
                       (pc == 32'h68) || (pc == 32'h6C) ||
                       (pc == 32'h78);
        end
    endfunction

    //--------------------------------------------------------------------------
    // Monitor: sampled at every falling edge once enabled
    //--------------------------------------------------------------------------
    always @(negedge clk) begin
        if (monitor_on) begin
            // Cycle after a redirect
            if (rd_prev) begin
                if (uut.u_if.pc !== prev_target)
                    pc_viol = pc_viol + 1;
                if ((uut.id_valid !== 1'b0) || (uut.ex_valid !== 1'b0))
                    bubble_viol = bubble_viol + 1;
            end

            if (uut.redirect === 1'b1) begin
                if (rd_count < 8) begin
                    rd_pc[rd_count]     = uut.ex_pc;
                    rd_target[rd_count] = uut.redirect_target;
                end
                rd_count = rd_count + 1;

                // Older instruction in MEM must still be valid
                if (uut.mem_valid !== 1'b1)
                    older_viol = older_viol + 1;

                // IF/ID and ID/EX flush inputs must be asserted
                if ((uut.u_if.u_if_id.flush !== 1'b1) ||
                    (uut.u_id.u_id_ex.flush !== 1'b1))
                    flush_viol = flush_viol + 1;

                prev_target = uut.redirect_target;
                rd_prev     = 1'b1;
            end
            else begin
                rd_prev = 1'b0;
            end

            // Branch bookkeeping (branch in EX, valid)
            if ((uut.ex_valid === 1'b1) && (uut.ex_branch === 1'b1)) begin
                br_count = br_count + 1;
                if (uut.redirect !== 1'b1)
                    nt_count = nt_count + 1;
            end

            // Wrong-path instruction valid in EX
            if ((uut.ex_valid === 1'b1) && is_wrong(uut.ex_pc))
                wrong_viol = wrong_viol + 1;

            // No loads in this program, so no load-use stall
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
        rd_prev      = 1'b0;
        prev_target  = 32'h0;
        rd_count     = 0;
        br_count     = 0;
        nt_count     = 0;
        pc_viol      = 0;
        bubble_viol  = 0;
        flush_viol   = 0;
        older_viol   = 0;
        wrong_viol   = 0;
        stall_count  = 0;
        x0_viol      = 0;
        for (i = 0; i < 8; i = i + 1) begin
            rd_pc[i]     = 32'hxxxxxxxx;
            rd_target[i] = 32'hxxxxxxxx;
        end
        reset = 1'b1;

        $display("==============================================================");
        $display(" RISC-V CPU Integration Test 5 (Remaining Instructions) Started");
        $display("==============================================================");

        // Reset through 3 rising edges (5, 15, 25 ns); release at 30 ns
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        @(posedge clk);
        monitor_on = 1'b1;

        // 37 instructions + 4 redirects x 2 bubbles + pipeline drain
        repeat (90) @(posedge clk);
        #1;

        //----------------------------------------------------------------------
        // Branch redirects (BLTU / BGEU, including unsigned-only outcomes)
        //----------------------------------------------------------------------
        $display("--- Branch redirects ---");
        check("B1 redirects observed (expect 4)",   rd_count, 32'd4);
        check("B2 redirect 1 PC = 0x34 (bltu)",     rd_pc[0], 32'h00000034);
        check("B3 redirect 1 target = 0x40",        rd_target[0], 32'h00000040);
        check("B4 redirect 2 PC = 0x44 (bgeu)",     rd_pc[1], 32'h00000044);
        check("B5 redirect 2 target = 0x50",        rd_target[1], 32'h00000050);
        check("B6 redirect 3 PC = 0x64 (bgeu x0)",  rd_pc[2], 32'h00000064);
        check("B7 redirect 3 target = 0x70",        rd_target[2], 32'h00000070);
        check("B8 redirect 4 PC = 0x74 (bltu x0)",  rd_pc[3], 32'h00000074);
        check("B9 redirect 4 target = 0x7C",        rd_target[3], 32'h0000007C);
        check("B10 branches reaching EX (expect 6)", br_count, 32'd6);
        check("B11 not-taken branches (expect 2)",   nt_count, 32'd2);
        check_zero("B12 PC loads target after redirect", pc_viol);
        check_zero("B13 ID/EX bubble after redirect",    bubble_viol);
        check_zero("B14 IF/ID+ID/EX flush asserted",     flush_viol);
        check_zero("B15 older instr valid in MEM",       older_viol);
        check_zero("B16 wrong path never valid in EX",   wrong_viol);
        check_zero("B17 no load-use stalls",             stall_count);

        //----------------------------------------------------------------------
        // Architectural registers
        //----------------------------------------------------------------------
        $display("--- Registers ---");
        check("R00 x0 = 0",                          `RF[0],  32'h00000000);
        check("R01 x1 = lui 0x12345000",             `RF[1],  32'h12345000);
        check("R02 x2 = lui 0xFFFFF000",             `RF[2],  32'hFFFFF000);
        check("R03 x3 = auipc 0 at 0x08 = 8",        `RF[3],  32'h00000008);
        check("R04 x4 = auipc 1 at 0x0C = 0x100C",   `RF[4],  32'h0000100C);
        check("R05 x5 = andi x1,-1 = x1",            `RF[5],  32'h12345000);
        check("R06 x6 = andi x4,0xFF = 0x0C",        `RF[6],  32'h0000000C);
        check("R07 x7 = ori x0,-256 = 0xFFFFFF00",   `RF[7],  32'hFFFFFF00);
        check("R08 x8 = ori x6,0xF0 = 0xFC",         `RF[8],  32'h000000FC);
        check("R09 x9 = xori x8,-1 = 0xFFFFFF03",    `RF[9],  32'hFFFFFF03);
        check("R10 x10 = xori x9,0xFF = 0xFFFFFFFC", `RF[10], 32'hFFFFFFFC);
        check("R11 x11 = sltu(x1<x2) = 1",           `RF[11], 32'h00000001);
        check("R12 x12 = sltu(x2<x1) = 0",           `RF[12], 32'h00000000);
        check("R13 x13 = sltu(x7<x9) = 1",           `RF[13], 32'h00000001);
        check("R14 wrong path bltu = 0",             `RF[14], 32'h00000000);
        check("R15 wrong path bltu = 0",             `RF[15], 32'h00000000);
        check("R16 bltu target = 1",                 `RF[16], 32'h00000001);
        check("R17 wrong path bgeu = 0",             `RF[17], 32'h00000000);
        check("R18 wrong path bgeu = 0",             `RF[18], 32'h00000000);
        check("R19 bgeu target = 1",                 `RF[19], 32'h00000001);
        check("R20 bltu not-taken fall-through = 1", `RF[20], 32'h00000001);
        check("R21 bgeu not-taken fall-through = 1", `RF[21], 32'h00000001);
        check("R22 wrong path bgeu x7,x0 = 0",       `RF[22], 32'h00000000);
        check("R23 wrong path bgeu x7,x0 = 0",       `RF[23], 32'h00000000);
        check("R24 bgeu x7,x0 target = 1",           `RF[24], 32'h00000001);
        check("R25 wrong path bltu x0,x7 = 0",       `RF[25], 32'h00000000);
        check("R26 bltu x0,x7 target = 1",           `RF[26], 32'h00000001);
        check("R27 x27 = x16+x19 = 2",               `RF[27], 32'h00000002);
        check("R28 x28 = x27+x20 = 3",               `RF[28], 32'h00000003);
        check("R29 x29 = x28+x21 = 4",               `RF[29], 32'h00000004);
        check("R30 x30 = x29+x24 = 5",               `RF[30], 32'h00000005);
        check("R31 x31 = x30+x26 = 6 (final)",       `RF[31], 32'h00000006);
        check_zero("R32 x0 zero at every cycle",     x0_viol);

        //----------------------------------------------------------------------
        // Summary
        //----------------------------------------------------------------------
        $display("==============================================================");
        $display(" RISC-V CPU REMAINING INSTRUCTION TEST SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");
        if (failed_tests == 0)
            $display("RISCV CPU REMAINING VERIFICATION PASSED");
        else
            $display("RISCV CPU REMAINING VERIFICATION FAILED");
        $finish;
    end

endmodule