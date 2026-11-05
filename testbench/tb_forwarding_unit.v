`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_forwarding_unit
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// DUT         : forwarding_unit (rtl/forwarding_unit.v)
// Description : Self-checking Verilog-2001 testbench. No clock: the DUT is
//               purely combinational, so every check waits 1 ns.
//
// Test structure:
//   1-10 Directed tests with hand-worked literal expected values
//   11   Reduced exhaustive sweep: addresses {x0,x1,x2,x31} for all four
//        address inputs x all 32 combinations of the five control bits
//        (4^4 * 32 = 8192 tests), checked against model_fwd()
//   12   20000 pseudo-random vectors (fixed seed, deterministic) against
//        model_fwd()
//
// model_fwd() is a separately written reference. The directed tests carry
// literal expectations so they do not depend on it.
//
// Run from the repository root (the VCD path is relative).
//==============================================================================

module tb_forwarding_unit;

    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------
    reg  [4:0] id_ex_rs1_addr;
    reg  [4:0] id_ex_rs2_addr;
    reg  [4:0] ex_mem_rd_addr;
    reg        ex_mem_reg_write;
    reg        ex_mem_mem_read;
    reg        ex_mem_valid;
    reg  [4:0] mem_wb_rd_addr;
    reg        mem_wb_reg_write;
    reg        mem_wb_valid;
    wire [1:0] forward_a;
    wire [1:0] forward_b;

    //--------------------------------------------------------------------------
    // Bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer fails_before;
    integer ia, ib, ic, id, f, k, seed, rnd;
    reg     verbose;
    reg [4:0] addrs [0:3];

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    forwarding_unit uut (
        .id_ex_rs1_addr   (id_ex_rs1_addr),
        .id_ex_rs2_addr   (id_ex_rs2_addr),
        .ex_mem_rd_addr   (ex_mem_rd_addr),
        .ex_mem_reg_write (ex_mem_reg_write),
        .ex_mem_mem_read  (ex_mem_mem_read),
        .ex_mem_valid     (ex_mem_valid),
        .mem_wb_rd_addr   (mem_wb_rd_addr),
        .mem_wb_reg_write (mem_wb_reg_write),
        .mem_wb_valid     (mem_wb_valid),
        .forward_a        (forward_a),
        .forward_b        (forward_b)
    );

    //--------------------------------------------------------------------------
    // Waveform
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("simulations/forwarding_unit.vcd");
        $dumpvars(0, tb_forwarding_unit);
    end

    //--------------------------------------------------------------------------
    // Watchdog
    //--------------------------------------------------------------------------
    initial begin
        #1000000;
        $display("[FAIL] WATCHDOG TIMEOUT: simulation did not finish");
        $display("FORWARDING UNIT VERIFICATION FAILED");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Reference model for ONE source register (returns the 2-bit select)
    //--------------------------------------------------------------------------
    function [1:0] model_fwd;
        input [4:0] rs;
        input [4:0] exrd;
        input       exrw;
        input       exmr;
        input       exv;
        input [4:0] wbrd;
        input       wbrw;
        input       wbv;
        reg         ex_hit;
        reg         wb_hit;
        begin
            ex_hit = 1'b0;
            wb_hit = 1'b0;
            if (exv == 1'b1 && exrw == 1'b1 && exmr == 1'b0 &&
                exrd != 5'd0 && exrd == rs)
                ex_hit = 1'b1;
            if (wbv == 1'b1 && wbrw == 1'b1 &&
                wbrd != 5'd0 && wbrd == rs)
                wb_hit = 1'b1;
            if (ex_hit)
                model_fwd = 2'b10;
            else if (wb_hit)
                model_fwd = 2'b01;
            else
                model_fwd = 2'b00;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Task: apply inputs, wait 1 ns, compare both outputs (!== catches X/Z)
    //--------------------------------------------------------------------------
    task chk;
        input [319:0] name;
        input [4:0]   rs1;
        input [4:0]   rs2;
        input [4:0]   exrd;
        input         exrw;
        input         exmr;
        input         exv;
        input [4:0]   wbrd;
        input         wbrw;
        input         wbv;
        input [1:0]   ea;
        input [1:0]   eb;
        begin
            id_ex_rs1_addr   = rs1;
            id_ex_rs2_addr   = rs2;
            ex_mem_rd_addr   = exrd;
            ex_mem_reg_write = exrw;
            ex_mem_mem_read  = exmr;
            ex_mem_valid     = exv;
            mem_wb_rd_addr   = wbrd;
            mem_wb_reg_write = wbrw;
            mem_wb_valid     = wbv;
            #1;
            total_tests = total_tests + 1;
            if ((forward_a !== ea) || (forward_b !== eb)) begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s", total_tests, name);
                $display("       rs1=%0d rs2=%0d | EX/MEM rd=%0d rw=%b mr=%b v=%b | MEM/WB rd=%0d rw=%b v=%b",
                         rs1, rs2, exrd, exrw, exmr, exv, wbrd, wbrw, wbv);
                if (forward_a !== ea)
                    $display("       forward_a actual=%b expected=%b", forward_a, ea);
                if (forward_b !== eb)
                    $display("       forward_b actual=%b expected=%b", forward_b, eb);
            end
            else begin
                passed_tests = passed_tests + 1;
                if (verbose)
                    $display("[PASS] #%0d %0s | A=%b B=%b", total_tests, name,
                             forward_a, forward_b);
            end
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
    //   chk(name, rs1, rs2, exrd, exrw, exmr, exv, wbrd, wbrw, wbv, ea, eb)
    //--------------------------------------------------------------------------
    initial begin
        total_tests  = 0;
        passed_tests = 0;
        failed_tests = 0;
        verbose      = 1'b1;
        seed         = 32'h1234ABCD;
        addrs[0] = 5'd0;
        addrs[1] = 5'd1;
        addrs[2] = 5'd2;
        addrs[3] = 5'd31;

        id_ex_rs1_addr = 5'd0;  id_ex_rs2_addr   = 5'd0;
        ex_mem_rd_addr = 5'd0;  ex_mem_reg_write = 1'b0;
        ex_mem_mem_read = 1'b0; ex_mem_valid     = 1'b0;
        mem_wb_rd_addr = 5'd0;  mem_wb_reg_write = 1'b0;
        mem_wb_valid   = 1'b0;
        #1;

        $display("==============================================================");
        $display(" Forwarding Unit Self-Checking Testbench Started");
        $display("==============================================================");

        //======================================================================
        // 1. No forwarding
        //======================================================================
        $display("--- 1. No forwarding ---");
        chk("1.1 no match, all enabled",      5'd1,  5'd2,  5'd3,  1,0,1, 5'd4,  1,1, 2'b00, 2'b00);
        chk("1.2 same sources, other dests",  5'd10, 5'd10, 5'd11, 1,0,1, 5'd12, 1,1, 2'b00, 2'b00);
        chk("1.3 idle bubble inputs",         5'd0,  5'd0,  5'd0,  0,0,0, 5'd0,  0,0, 2'b00, 2'b00);

        //======================================================================
        // 2. EX/MEM forwarding
        //======================================================================
        $display("--- 2. EX/MEM forwarding ---");
        chk("2.1 EX/MEM matches rs1 only",    5'd5,  5'd6,  5'd5,  1,0,1, 5'd9,  1,1, 2'b10, 2'b00);
        chk("2.2 EX/MEM matches rs2 only",    5'd5,  5'd6,  5'd6,  1,0,1, 5'd9,  1,1, 2'b00, 2'b10);
        chk("2.3 EX/MEM matches both (same)", 5'd7,  5'd7,  5'd7,  1,0,1, 5'd9,  1,1, 2'b10, 2'b10);

        //======================================================================
        // 3. MEM/WB forwarding
        //======================================================================
        $display("--- 3. MEM/WB forwarding ---");
        chk("3.1 MEM/WB matches rs1 only",    5'd5,  5'd6,  5'd9,  1,0,1, 5'd5,  1,1, 2'b01, 2'b00);
        chk("3.2 MEM/WB matches rs2 only",    5'd5,  5'd6,  5'd9,  1,0,1, 5'd6,  1,1, 2'b00, 2'b01);
        chk("3.3 MEM/WB matches both (same)", 5'd7,  5'd7,  5'd9,  1,0,1, 5'd7,  1,1, 2'b01, 2'b01);

        //======================================================================
        // 4. Priority: EX/MEM over MEM/WB
        //======================================================================
        $display("--- 4. Priority ---");
        chk("4.1 both match rs1: EX/MEM wins", 5'd5, 5'd6,  5'd5,  1,0,1, 5'd5,  1,1, 2'b10, 2'b00);
        chk("4.2 both match rs2: EX/MEM wins", 5'd5, 5'd6,  5'd6,  1,0,1, 5'd6,  1,1, 2'b00, 2'b10);
        chk("4.3 A from EX/MEM, B from MEM/WB",5'd5, 5'd6,  5'd5,  1,0,1, 5'd6,  1,1, 2'b10, 2'b01);
        chk("4.4 A from MEM/WB, B from EX/MEM",5'd5, 5'd6,  5'd6,  1,0,1, 5'd5,  1,1, 2'b01, 2'b10);
        chk("4.5 all three same register",     5'd8, 5'd8,  5'd8,  1,0,1, 5'd8,  1,1, 2'b10, 2'b10);

        //======================================================================
        // 5. x0 exclusion
        //======================================================================
        $display("--- 5. x0 exclusion ---");
        chk("5.1 rs1=x0, EX/MEM rd=x0",       5'd0,  5'd3,  5'd0,  1,0,1, 5'd9,  1,1, 2'b00, 2'b00);
        chk("5.2 rs2=x0, EX/MEM rd=x0",       5'd3,  5'd0,  5'd0,  1,0,1, 5'd9,  1,1, 2'b00, 2'b00);
        chk("5.3 both x0, all rd=x0",         5'd0,  5'd0,  5'd0,  1,0,1, 5'd0,  1,1, 2'b00, 2'b00);
        chk("5.4 rs1=x0, MEM/WB rd=x0",       5'd0,  5'd3,  5'd4,  1,0,1, 5'd0,  1,1, 2'b00, 2'b00);
        chk("5.5 EX/MEM x0 does not block WB",5'd5,  5'd6,  5'd0,  1,0,1, 5'd5,  1,1, 2'b01, 2'b00);
        chk("5.6 rs=x0, rd nonzero elsewhere",5'd0,  5'd0,  5'd5,  1,0,1, 5'd6,  1,1, 2'b00, 2'b00);

        //======================================================================
        // 6. Invalid instructions
        //======================================================================
        $display("--- 6. Invalid instructions ---");
        chk("6.1 EX/MEM invalid, match rs1",  5'd5,  5'd6,  5'd5,  1,0,0, 5'd9,  1,1, 2'b00, 2'b00);
        chk("6.2 MEM/WB invalid, match rs1",  5'd5,  5'd6,  5'd9,  1,0,1, 5'd5,  1,0, 2'b00, 2'b00);
        chk("6.3 EX invalid, WB valid match", 5'd5,  5'd6,  5'd5,  1,0,0, 5'd5,  1,1, 2'b01, 2'b00);
        chk("6.4 EX valid, WB invalid match", 5'd5,  5'd6,  5'd5,  1,0,1, 5'd5,  1,0, 2'b10, 2'b00);
        chk("6.5 both invalid, both match",   5'd7,  5'd7,  5'd7,  1,0,0, 5'd7,  1,0, 2'b00, 2'b00);
        chk("6.6 EX invalid, WB valid rs2",   5'd5,  5'd6,  5'd6,  1,0,0, 5'd6,  1,1, 2'b00, 2'b01);

        //======================================================================
        // 7. reg_write = 0
        //======================================================================
        $display("--- 7. reg_write = 0 ---");
        chk("7.1 EX/MEM rw=0, match rs1",     5'd5,  5'd6,  5'd5,  0,0,1, 5'd9,  1,1, 2'b00, 2'b00);
        chk("7.2 MEM/WB rw=0, match rs1",     5'd5,  5'd6,  5'd9,  1,0,1, 5'd5,  0,1, 2'b00, 2'b00);
        chk("7.3 EX rw=0, WB rw=1, both match",5'd5, 5'd6,  5'd5,  0,0,1, 5'd5,  1,1, 2'b01, 2'b00);
        chk("7.4 EX rw=1, WB rw=0, both match",5'd5, 5'd6,  5'd5,  1,0,1, 5'd5,  0,1, 2'b10, 2'b00);
        chk("7.5 both rw=0, all match",       5'd7,  5'd7,  5'd7,  0,0,1, 5'd7,  0,1, 2'b00, 2'b00);

        //======================================================================
        // 8. Load exclusion from EX/MEM
        //======================================================================
        $display("--- 8. Load exclusion ---");
        chk("8.1 EX/MEM load matches rs1",    5'd5,  5'd6,  5'd5,  1,1,1, 5'd9,  1,1, 2'b00, 2'b00);
        chk("8.2 EX/MEM load matches rs2",    5'd5,  5'd6,  5'd6,  1,1,1, 5'd9,  1,1, 2'b00, 2'b00);
        chk("8.3 load match + WB match (spec)",5'd5, 5'd6,  5'd5,  1,1,1, 5'd5,  1,1, 2'b01, 2'b00);
        chk("8.4 EX/MEM load matches both",   5'd7,  5'd7,  5'd7,  1,1,1, 5'd9,  1,1, 2'b00, 2'b00);
        chk("8.5 load no match, WB match rs2",5'd5,  5'd6,  5'd9,  1,1,1, 5'd6,  1,1, 2'b00, 2'b01);

        //======================================================================
        // 9. A and B independence, near-miss addresses
        //======================================================================
        $display("--- 9. A/B independence ---");
        chk("9.1 A from EX/MEM, B from WB",   5'd1,  5'd2,  5'd1,  1,0,1, 5'd2,  1,1, 2'b10, 2'b01);
        chk("9.2 A from WB, B from EX/MEM",   5'd2,  5'd1,  5'd1,  1,0,1, 5'd2,  1,1, 2'b01, 2'b10);
        chk("9.3 A from WB, B from EX/MEM",   5'd3,  5'd4,  5'd4,  1,0,1, 5'd3,  1,1, 2'b01, 2'b10);
        chk("9.4 A from EX/MEM, B none",      5'd3,  5'd4,  5'd3,  1,0,1, 5'd3,  1,1, 2'b10, 2'b00);
        for (k = 0; k < 5; k = k + 1) begin
            // Destination differs from the source in exactly one bit
            chk("9.5 one-bit address mismatch",
                5'd21, 5'd21, (5'd21 ^ (5'd1 << k)), 1,0,1,
                (5'd21 ^ (5'd1 << k)), 1,1, 2'b00, 2'b00);
        end

        //======================================================================
        // 10. Boundary registers
        //======================================================================
        $display("--- 10. Boundary registers ---");
        chk("10.1 x31 via EX/MEM on rs1",     5'd31, 5'd1,  5'd31, 1,0,1, 5'd9,  1,1, 2'b10, 2'b00);
        chk("10.2 x31 via MEM/WB on rs2",     5'd1,  5'd31, 5'd30, 1,0,1, 5'd31, 1,1, 2'b00, 2'b01);
        chk("10.3 x31 everywhere",            5'd31, 5'd31, 5'd31, 1,0,1, 5'd31, 1,1, 2'b10, 2'b10);
        chk("10.4 x1 via EX/MEM on rs1",      5'd1,  5'd31, 5'd1,  1,0,1, 5'd9,  1,1, 2'b10, 2'b00);
        chk("10.5 x31 sources, x0 dests",     5'd31, 5'd31, 5'd0,  1,0,1, 5'd0,  1,1, 2'b00, 2'b00);

        //======================================================================
        // 11. Reduced exhaustive sweep (8192 tests)
        //     flags f: [0]=exrw [1]=exmr [2]=exv [3]=wbrw [4]=wbv
        //======================================================================
        $display("--- 11. Reduced exhaustive sweep ---");
        verbose      = 1'b0;
        fails_before = failed_tests;
        for (ia = 0; ia < 4; ia = ia + 1)
          for (ib = 0; ib < 4; ib = ib + 1)
            for (ic = 0; ic < 4; ic = ic + 1)
              for (id = 0; id < 4; id = id + 1)
                for (f = 0; f < 32; f = f + 1)
                    chk("11 sweep",
                        addrs[ia], addrs[ib], addrs[ic], f[0], f[1], f[2],
                        addrs[id], f[3], f[4],
                        model_fwd(addrs[ia], addrs[ic], f[0], f[1], f[2], addrs[id], f[3], f[4]),
                        model_fwd(addrs[ib], addrs[ic], f[0], f[1], f[2], addrs[id], f[3], f[4]));
        sweep_end("11 exhaustive sweep (8192 tests)", fails_before);

        //======================================================================
        // 12. Pseudo-random vectors (20000 tests, fixed seed)
        //======================================================================
        $display("--- 12. Pseudo-random vectors ---");
        fails_before = failed_tests;
        for (k = 0; k < 20000; k = k + 1) begin
            rnd = $random(seed);
            chk("12 random",
                {2'b00, rnd[2:0]},  {2'b00, rnd[5:3]},
                {2'b00, rnd[8:6]},  rnd[12], rnd[13], rnd[14],
                {2'b00, rnd[11:9]}, rnd[15], rnd[16],
                model_fwd({2'b00, rnd[2:0]}, {2'b00, rnd[8:6]}, rnd[12], rnd[13], rnd[14],
                          {2'b00, rnd[11:9]}, rnd[15], rnd[16]),
                model_fwd({2'b00, rnd[5:3]}, {2'b00, rnd[8:6]}, rnd[12], rnd[13], rnd[14],
                          {2'b00, rnd[11:9]}, rnd[15], rnd[16]));
        end
        sweep_end("12 random vectors (20000 tests)", fails_before);
        verbose = 1'b1;

        //======================================================================
        // Summary
        //======================================================================
        #5;
        $display("==============================================================");
        $display(" FORWARDING UNIT VERIFICATION SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");

        if (failed_tests == 0)
            $display("FORWARDING UNIT VERIFICATION PASSED");
        else
            $display("FORWARDING UNIT VERIFICATION FAILED");

        $finish;
    end

endmodule