`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_if_stage
// DUT         : if_stage (rtl/if_stage.v) with program_counter,
//               instruction_memory and if_id_register
// Description : Checks reset, normal PC increment, stall (hold), redirect
//               (PC load + IF/ID flush), redirect during a stall, and a
//               mid-run reset.
//
// Timing (race-free): 10 ns clock, rising edges at 5, 15, 25 ... ns.
// Controls change at the FALLING edge; results are checked 1 ns after the
// rising edge. Expected values are literals taken from the hex program.
//
// Run from the repository root.
//==============================================================================

module tb_if_stage;

    localparam [31:0] NOP = 32'h00000013;

    reg         clk;
    reg         reset;
    reg         pc_write;
    reg         if_id_write;
    reg         redirect;
    reg  [31:0] redirect_target;
    wire [31:0] pc;
    wire [31:0] id_pc;
    wire [31:0] id_pc_plus4;
    wire [31:0] id_instruction;
    wire        id_valid;

    integer total_tests;
    integer passed_tests;
    integer failed_tests;

    if_stage #(
        .INIT_FILE ("simulations/if_stage_test.hex")
    ) uut (
        .clk             (clk),
        .reset           (reset),
        .pc_write        (pc_write),
        .if_id_write     (if_id_write),
        .redirect        (redirect),
        .redirect_target (redirect_target),
        .pc              (pc),
        .id_pc           (id_pc),
        .id_pc_plus4     (id_pc_plus4),
        .id_instruction  (id_instruction),
        .id_valid        (id_valid)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("simulations/if_stage.vcd");
        $dumpvars(0, tb_if_stage);
    end

    // Watchdog
    initial begin
        #10000;
        $display("[FAIL] WATCHDOG TIMEOUT");
        $display("IF STAGE VERIFICATION FAILED");
        $finish;
    end

    // One clock cycle: drive at the falling edge, return 1 ns after the rising edge
    task step;
        input        rst;
        input        pcw;
        input        idw;
        input        redir;
        input [31:0] target;
        begin
            @(negedge clk);
            reset           = rst;
            pc_write        = pcw;
            if_id_write     = idw;
            redirect        = redir;
            redirect_target = target;
            @(posedge clk);
            #1;
        end
    endtask

    // Compare PC and all IF/ID outputs (case inequality catches X/Z)
    task chk;
        input [319:0] name;
        input [31:0]  e_pc;
        input [31:0]  e_idpc;
        input [31:0]  e_idpc4;
        input [31:0]  e_instr;
        input         e_valid;
        begin
            total_tests = total_tests + 1;
            if ((pc !== e_pc) || (id_pc !== e_idpc) || (id_pc_plus4 !== e_idpc4) ||
                (id_instruction !== e_instr) || (id_valid !== e_valid)) begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s", total_tests, name);
                $display("       pc          actual=%h expected=%h", pc, e_pc);
                $display("       id_pc       actual=%h expected=%h", id_pc, e_idpc);
                $display("       id_pc_plus4 actual=%h expected=%h", id_pc_plus4, e_idpc4);
                $display("       id_instr    actual=%h expected=%h", id_instruction, e_instr);
                $display("       id_valid    actual=%b expected=%b", id_valid, e_valid);
            end
            else begin
                passed_tests = passed_tests + 1;
                $display("[PASS] #%0d %0s | pc=%h id_pc=%h instr=%h valid=%b",
                         total_tests, name, pc, id_pc, id_instruction, id_valid);
            end
        end
    endtask

    initial begin
        total_tests     = 0;
        passed_tests    = 0;
        failed_tests    = 0;
        reset           = 1'b0;
        pc_write        = 1'b1;
        if_id_write     = 1'b1;
        redirect        = 1'b0;
        redirect_target = 32'h0;

        $display("==============================================================");
        $display(" IF Stage Self-Checking Testbench Started");
        $display("==============================================================");

        // 1. Reset (outputs are unknown until this edge)
        step(1'b1, 1'b1, 1'b1, 1'b0, 32'h0);
        chk("1 reset: PC=0, IF/ID bubble", 32'h00, 32'h00, 32'h00, NOP, 1'b0);

        // 2-4. Normal increment: IF/ID follows PC one cycle behind
        step(1'b0, 1'b1, 1'b1, 1'b0, 32'h0);
        chk("2 normal: fetch word 0",  32'h04, 32'h00, 32'h04, 32'h00100093, 1'b1);
        step(1'b0, 1'b1, 1'b1, 1'b0, 32'h0);
        chk("3 normal: fetch word 1",  32'h08, 32'h04, 32'h08, 32'h00200113, 1'b1);
        step(1'b0, 1'b1, 1'b1, 1'b0, 32'h0);
        chk("4 normal: fetch word 2",  32'h0C, 32'h08, 32'h0C, 32'h00300193, 1'b1);

        // 5-6. Stall: PC and IF/ID both hold
        step(1'b0, 1'b0, 1'b0, 1'b0, 32'h0);
        chk("5 stall cycle 1: hold",   32'h0C, 32'h08, 32'h0C, 32'h00300193, 1'b1);
        step(1'b0, 1'b0, 1'b0, 1'b0, 32'h0);
        chk("6 stall cycle 2: hold",   32'h0C, 32'h08, 32'h0C, 32'h00300193, 1'b1);

        // 7-8. Stall released: nothing was skipped
        step(1'b0, 1'b1, 1'b1, 1'b0, 32'h0);
        chk("7 stall end: word 3",     32'h10, 32'h0C, 32'h10, 32'h00400213, 1'b1);
        step(1'b0, 1'b1, 1'b1, 1'b0, 32'h0);
        chk("8 normal: word 4",        32'h14, 32'h10, 32'h14, 32'h00500293, 1'b1);

        // 9. Redirect to 0x20: PC loads target, IF/ID flushed (word 5 dropped)
        step(1'b0, 1'b1, 1'b1, 1'b1, 32'h20);
        chk("9 redirect: PC=0x20, flush", 32'h20, 32'h00, 32'h00, NOP, 1'b0);

        // 10-11. Fetch resumes at the target
        step(1'b0, 1'b1, 1'b1, 1'b0, 32'h0);
        chk("10 after redirect: word 8", 32'h24, 32'h20, 32'h24, 32'h00900493, 1'b1);
        step(1'b0, 1'b1, 1'b1, 1'b0, 32'h0);
        chk("11 after redirect: word 9", 32'h28, 32'h24, 32'h28, 32'h00A00513, 1'b1);

        // 12. Redirect while pc_write = 0 and if_id_write = 0: redirect wins
        step(1'b0, 1'b0, 1'b0, 1'b1, 32'h04);
        chk("12 redirect during stall",  32'h04, 32'h00, 32'h00, NOP, 1'b0);

        // 13. Recover and fetch from the new target
        step(1'b0, 1'b1, 1'b1, 1'b0, 32'h0);
        chk("13 recover: word 1",        32'h08, 32'h04, 32'h08, 32'h00200113, 1'b1);

        // 14-15. Reset in the middle of a run
        step(1'b1, 1'b1, 1'b1, 1'b0, 32'h0);
        chk("14 mid-run reset",          32'h00, 32'h00, 32'h00, NOP, 1'b0);
        step(1'b0, 1'b1, 1'b1, 1'b0, 32'h0);
        chk("15 restart: word 0",        32'h04, 32'h00, 32'h04, 32'h00100093, 1'b1);

        #10;
        $display("==============================================================");
        $display(" IF STAGE VERIFICATION SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");
        if (failed_tests == 0)
            $display("IF STAGE VERIFICATION PASSED");
        else
            $display("IF STAGE VERIFICATION FAILED");
        $finish;
    end

endmodule