`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_riscv_cpu_load_store  (integration test 2)
// DUT         : riscv_cpu with simulations/cpu_load_store_test.hex
// Description : Runs a 15-instruction program with SW, LW and two deliberate
//               load-use hazards (at 0x18 and 0x30), then checks:
//                 - architectural registers (uut.u_id.u_regfile.registers)
//                 - data memory words      (uut.u_mem.u_dmem.mem)
//                 - the hazard behaviour, sampled every cycle at the falling
//                   edge: pc_write / if_id_write low and id_ex_flush high
//                   during a stall, PC and IF/ID held, ID/EX bubble next cycle
//
// Timing (race-free): 10 ns clock, rising edges at 5, 15, 25 ... ns.
//   reset is high for 3 rising edges and released at a FALLING edge (30 ns).
//   The monitor samples at falling edges; final checks run 1 ns after a
//   rising edge, long after the program has drained.
//
// Run from the repository root.
//==============================================================================

`define RF uut.u_id.u_regfile.registers
`define DM uut.u_mem.u_dmem.mem

module tb_riscv_cpu_load_store;

    reg clk;
    reg reset;

    integer total_tests;
    integer passed_tests;
    integer failed_tests;

    // Monitor state
    reg        monitor_on;
    reg        hz_prev;
    reg [31:0] prev_pc;
    reg [31:0] prev_instr;
    integer    hz_count;
    integer    cons_viol;
    integer    pc_hold_viol;
    integer    instr_hold_viol;
    integer    bubble_viol;
    integer    x0_viol;
    reg [31:0] stall_pc    [0:7];
    reg [31:0] stall_instr [0:7];

    riscv_cpu #(
        .INIT_FILE ("simulations/cpu_load_store_test.hex")
    ) uut (
        .clk   (clk),
        .reset (reset)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("simulations/tb_riscv_cpu_load_store.vcd");
        $dumpvars(0, tb_riscv_cpu_load_store);
    end

    // Watchdog
    initial begin
        #20000;
        $display("[FAIL] WATCHDOG TIMEOUT");
        $display("RISCV CPU LOAD/STORE VERIFICATION FAILED");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Hazard monitor: sampled at every falling edge once enabled.
    //   Stall cycle (id_ex_flush = 1): pc_write = 0 and if_id_write = 0.
    //   Other cycles: id_ex_flush = 0, pc_write = 1, if_id_write = 1.
    //   After a stall cycle (next sample): PC and the ID instruction are
    //   unchanged, and ID/EX holds a bubble (ex_valid = 0).
    //--------------------------------------------------------------------------
    always @(negedge clk) begin
        if (monitor_on) begin
            if (hz_prev) begin
                if (uut.u_if.pc !== prev_pc)             pc_hold_viol    = pc_hold_viol + 1;
                if (uut.id_instruction !== prev_instr)   instr_hold_viol = instr_hold_viol + 1;
                if (uut.ex_valid !== 1'b0)               bubble_viol     = bubble_viol + 1;
            end
            if (uut.id_ex_flush === 1'b1) begin
                if ((uut.pc_write !== 1'b0) || (uut.if_id_write !== 1'b0))
                    cons_viol = cons_viol + 1;
                if (hz_count < 8) begin
                    stall_pc[hz_count]    = uut.id_pc;
                    stall_instr[hz_count] = uut.id_instruction;
                end
                hz_count   = hz_count + 1;
                hz_prev    = 1'b1;
                prev_pc    = uut.u_if.pc;
                prev_instr = uut.id_instruction;
            end
            else begin
                if ((uut.id_ex_flush !== 1'b0) || (uut.pc_write !== 1'b1) ||
                    (uut.if_id_write !== 1'b1))
                    cons_viol = cons_viol + 1;
                hz_prev = 1'b0;
            end
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
        total_tests     = 0;
        passed_tests    = 0;
        failed_tests    = 0;
        monitor_on      = 1'b0;
        hz_prev         = 1'b0;
        prev_pc         = 32'h0;
        prev_instr      = 32'h0;
        hz_count        = 0;
        cons_viol       = 0;
        pc_hold_viol    = 0;
        instr_hold_viol = 0;
        bubble_viol     = 0;
        x0_viol         = 0;
        reset           = 1'b1;

        $display("==============================================================");
        $display(" RISC-V CPU Integration Test 2 (LW / SW / Load-use) Started");
        $display("==============================================================");

        // Hold reset through 3 rising edges (5, 15, 25 ns); release at 30 ns
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        @(posedge clk);
        monitor_on = 1'b1;               // monitor starts at the next falling edge

        // Program is 15 instructions + 2 stalls + 4 pipeline stages (~21 edges)
        repeat (40) @(posedge clk);
        #1;

        //----------------------------------------------------------------------
        // Hazard behaviour
        //----------------------------------------------------------------------
        $display("--- Load-use hazards ---");
        check("H1 stall cycles observed (expect 2)",   hz_count, 32'd2);
        check("H2 stall 1: ID holds pc 0x18",          stall_pc[0],    32'h00000018);
        check("H3 stall 1: ID holds add x5,x4,x4",     stall_instr[0], 32'h004202B3);
        check("H4 stall 2: ID holds pc 0x30",          stall_pc[1],    32'h00000030);
        check("H5 stall 2: ID holds addi x10,x9,1",    stall_instr[1], 32'h00148513);
        check_zero("H6 hazard outputs consistent",     cons_viol);
        check_zero("H7 PC held during stalls",         pc_hold_viol);
        check_zero("H8 IF/ID held during stalls",      instr_hold_viol);
        check_zero("H9 ID/EX bubble after each stall", bubble_viol);

        //----------------------------------------------------------------------
        // Architectural registers
        //----------------------------------------------------------------------
        $display("--- Registers ---");
        check("x0 = 0",                       `RF[0],  32'h00000000);
        check("x1 = 100 (base address)",      `RF[1],  32'h00000064);
        check("x2 = 291",                     `RF[2],  32'h00000123);
        check("x3 = 77",                      `RF[3],  32'h0000004D);
        check("x4 = lw MEM[100] = 0x123",     `RF[4],  32'h00000123);
        check("x5 = x4+x4 (after stall)",     `RF[5],  32'h00000246);
        check("x6 = lw MEM[104] = 0x4D",      `RF[6],  32'h0000004D);
        check("x7 = x6+x5 (MEM/WB forward)",  `RF[7],  32'h00000293);
        check("x8 = 5 (gap instruction)",     `RF[8],  32'h00000005);
        check("x9 = lw MEM[108] = 0x293",     `RF[9],  32'h00000293);
        check("x10 = x9+1 (after stall)",     `RF[10], 32'h00000294);
        check("x11 = x10+x5 final result",    `RF[11], 32'h000004DA);
        check("x12 untouched",                `RF[12], 32'h00000000);
        check_zero("x0 zero at every cycle",  x0_viol);

        //----------------------------------------------------------------------
        // Data memory (word index = byte address / 4)
        //----------------------------------------------------------------------
        $display("--- Data memory ---");
        check("MEM word 24 (0x60) untouched", `DM[24], 32'h00000000);
        check("MEM word 25 (0x64) = 0x123",   `DM[25], 32'h00000123);
        check("MEM word 26 (0x68) = 0x4D",    `DM[26], 32'h0000004D);
        check("MEM word 27 (0x6C) = 0x293",   `DM[27], 32'h00000293);
        check("MEM word 28 (0x70) = 0x294",   `DM[28], 32'h00000294);
        check("MEM word 29 (0x74) untouched", `DM[29], 32'h00000000);
        check("MEM word 0 untouched",         `DM[0],  32'h00000000);

        $display("==============================================================");
        $display(" RISC-V CPU LOAD/STORE TEST SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");
        if (failed_tests == 0)
            $display("RISCV CPU LOAD/STORE VERIFICATION PASSED");
        else
            $display("RISCV CPU LOAD/STORE VERIFICATION FAILED");
        $finish;
    end

endmodule