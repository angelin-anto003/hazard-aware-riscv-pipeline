`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_riscv_cpu_jump  (integration test 4: JAL / JALR)
// DUT         : riscv_cpu with simulations/cpu_jump_test.hex
// Description : Runs an 18-instruction program with three redirects (two JAL,
//               one JALR), then checks redirect PCs, targets, link values,
//               wrong-path suppression, flush/bubble behaviour, older
//               instructions completing, and the final register state.
//
// Timing (race-free): 10 ns clock, rising edges at 5, 15, 25 ... ns.
//   reset is high for 3 rising edges and released at a FALLING edge (30 ns).
//   The monitor samples at falling edges, where redirect and the stage
//   outputs are settled. Register checks run long after the program drains.
//
// Run from the repository root.
//==============================================================================

`define RF uut.u_id.u_regfile.registers

module tb_riscv_cpu_jump;

    reg clk;
    reg reset;

    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer i;
    integer nz;

    // Monitor state
    reg        monitor_on;
    reg        rd_prev;
    reg [31:0] prev_target;
    integer    rd_count;
    reg [31:0] rd_pc     [0:7];
    reg [31:0] rd_target [0:7];
    reg        rd_isjalr [0:7];
    integer    older_viol;
    integer    pc_viol;
    integer    bubble_viol;
    integer    flush_viol;
    integer    wrong_viol;
    integer    stall_count;
    integer    x0_viol;

    riscv_cpu #(
        .INIT_FILE ("simulations/cpu_jump_test.hex")
    ) uut (
        .clk   (clk),
        .reset (reset)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("simulations/tb_riscv_cpu_jump.vcd");
        $dumpvars(0, tb_riscv_cpu_jump);
    end

    // Watchdog
    initial begin
        #20000;
        $display("[FAIL] WATCHDOG TIMEOUT");
        $display("RISCV CPU JUMP VERIFICATION FAILED");
        $finish;
    end

    // PCs of wrong-path instructions (must never be valid in EX)
    function is_wrong;
        input [31:0] pc;
        begin
            is_wrong = (pc == 32'h08) || (pc == 32'h0C) || (pc == 32'h18) ||
                       (pc == 32'h1C) || (pc == 32'h20) || (pc == 32'h24) ||
                       (pc == 32'h30);
        end
    endfunction

    //--------------------------------------------------------------------------
    // Monitor: sampled at every falling edge once enabled
    //--------------------------------------------------------------------------
    always @(negedge clk) begin
        if (monitor_on) begin
            // Cycle after a redirect
            if (rd_prev) begin
                // PC must hold the redirect target
                if (uut.u_if.pc !== prev_target)
                    pc_viol = pc_viol + 1;
                // ID and EX must hold bubbles
                if ((uut.id_valid !== 1'b0) || (uut.ex_valid !== 1'b0))
                    bubble_viol = bubble_viol + 1;
            end

            if (uut.redirect === 1'b1) begin
                if (rd_count < 8) begin
                    rd_pc[rd_count]     = uut.ex_pc;
                    rd_target[rd_count] = uut.redirect_target;
                    rd_isjalr[rd_count] = uut.ex_jump_reg;
                end
                rd_count = rd_count + 1;

                // Older instruction in MEM must be valid (not discarded)
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

            // Wrong-path instruction reached EX as valid
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
        older_viol   = 0;
        pc_viol      = 0;
        bubble_viol  = 0;
        flush_viol   = 0;
        wrong_viol   = 0;
        stall_count  = 0;
        x0_viol      = 0;
        for (i = 0; i < 8; i = i + 1) begin
            rd_pc[i]     = 32'hxxxxxxxx;
            rd_target[i] = 32'hxxxxxxxx;
            rd_isjalr[i] = 1'bx;
        end
        reset = 1'b1;

        $display("==============================================================");
        $display(" RISC-V CPU Integration Test 4 (JAL / JALR) Started");
        $display("==============================================================");

        // Reset through 3 rising edges (5, 15, 25 ns); release at 30 ns
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        @(posedge clk);
        monitor_on = 1'b1;

        // 18 instructions + 3 redirects x 2 bubbles + pipeline drain
        repeat (60) @(posedge clk);
        #1;

        //----------------------------------------------------------------------
        // Redirect behaviour
        //----------------------------------------------------------------------
        $display("--- Jump redirects ---");
        check("J1 redirects observed (expect 3)",    rd_count, 32'd3);
        check("J2 redirect 1 PC = 0x04 (jal)",       rd_pc[0], 32'h00000004);
        check("J3 redirect 1 target = 0x10",         rd_target[0], 32'h00000010);
        check("J4 redirect 1 is JAL (jalr flag 0)",  {31'b0, rd_isjalr[0]}, 32'd0);
        check("J5 redirect 2 PC = 0x14 (jalr)",      rd_pc[1], 32'h00000014);
        check("J6 redirect 2 target = 0x28 (bit0 clr)", rd_target[1], 32'h00000028);
        check("J7 redirect 2 is JALR (flag 1)",      {31'b0, rd_isjalr[1]}, 32'd1);
        check("J8 redirect 3 PC = 0x2C (jal)",       rd_pc[2], 32'h0000002C);
        check("J9 redirect 3 target = 0x34",         rd_target[2], 32'h00000034);
        check("J10 redirect 3 is JAL (flag 0)",      {31'b0, rd_isjalr[2]}, 32'd0);
        check_zero("J11 PC loads target after redirect", pc_viol);
        check_zero("J12 ID/EX bubble after redirect",    bubble_viol);
        check_zero("J13 IF/ID+ID/EX flush asserted",     flush_viol);
        check_zero("J14 older instr valid in MEM",       older_viol);
        check_zero("J15 wrong path never valid in EX",   wrong_viol);
        check_zero("J16 no load-use stalls",             stall_count);

        //----------------------------------------------------------------------
        // Architectural registers
        //----------------------------------------------------------------------
        $display("--- Registers ---");
        check("R1 x0 = 0",                           `RF[0],  32'h00000000);
        check("R2 x1 = 36 (JALR base)",              `RF[1],  32'h00000024);
        check("R3 x2 = 8 (JAL link, PC+4)",          `RF[2],  32'h00000008);
        check("R4 x3 = 3 (older, completed)",        `RF[3],  32'h00000003);
        check("R5 x4 = 24 (JALR link, PC+4)",        `RF[4],  32'h00000018);
        check("R6 x5 = 5 (older, completed)",        `RF[5],  32'h00000005);
        check("R7 x6 = 48 (JAL link, PC+4)",         `RF[6],  32'h00000030);
        check("R8 x7 = 7 (JAL target)",              `RF[7],  32'h00000007);
        check("R9 x8 = 32 (x2+x4)",                  `RF[8],  32'h00000020);
        check("R10 x9 = 39 (x8+x7)",                 `RF[9],  32'h00000027);
        check("R11 x30 = 53 (x6+x5)",                `RF[30], 32'h00000035);
        check("R12 x31 = 42 (x9+x3, final)",         `RF[31], 32'h0000002A);

        nz = 0;
        for (i = 10; i <= 16; i = i + 1)
            if (`RF[i] !== 32'h00000000) nz = nz + 1;
        check_zero("R13 wrong-path x10..x16 zero", nz);

        nz = 0;
        for (i = 17; i <= 29; i = i + 1)
            if (`RF[i] !== 32'h00000000) nz = nz + 1;
        check_zero("R14 untouched x17..x29 zero",  nz);

        check_zero("R15 x0 zero at every cycle",   x0_viol);

        //----------------------------------------------------------------------
        // Summary
        //----------------------------------------------------------------------
        $display("==============================================================");
        $display(" RISC-V CPU JUMP TEST SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");
        if (failed_tests == 0)
            $display("RISCV CPU JUMP VERIFICATION PASSED");
        else
            $display("RISCV CPU JUMP VERIFICATION FAILED");
        $finish;
    end

endmodule