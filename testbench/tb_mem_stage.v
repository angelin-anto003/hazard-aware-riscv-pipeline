`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_mem_stage
// DUT         : mem_stage (with data_memory and mem_wb_register)
// Description : Self-checking Verilog-2001 testbench.
//
// Timing (race-free): 10 ns clock, rising edges at 5, 15, 25 ... ns.
//   - Each operation is applied at a FALLING edge.
//   - The data-memory write and the MEM/WB capture both happen at the next
//     rising edge. Results are checked 1 ns AFTER it.
//   - A load shows its data in wb_mem_read_data (the memory read is
//     combinational and is captured at the same edge).
//
// Expected values: literals, plus model[] (expected memory contents by WORD
// NUMBER, updated only by valid SW to valid addresses). The memory array is
// compared with the model through a hierarchical reference
// (uut.u_dmem.mem[...]), so corruption by an ignored write is detected even
// if no load ever reads that word.
//
// Run from the repository root.
//==============================================================================

module tb_mem_stage;

    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------
    reg         clk;
    reg         reset;
    reg  [31:0] mem_pc_plus4;
    reg  [31:0] mem_alu_result;
    reg  [31:0] mem_store_data;
    reg  [31:0] mem_immediate;
    reg  [4:0]  mem_rd_addr;
    reg         mem_mem_read;
    reg         mem_mem_write;
    reg         mem_reg_write;
    reg  [1:0]  mem_wb_sel;
    reg         mem_valid;

    wire [31:0] wb_alu_result;
    wire [31:0] wb_mem_read_data;
    wire [31:0] wb_pc_plus4;
    wire [31:0] wb_immediate;
    wire [4:0]  wb_rd_addr;
    wire        wb_reg_write;
    wire [1:0]  wb_sel;
    wire        wb_valid;

    //--------------------------------------------------------------------------
    // Bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer fails_before;
    integer k;
    reg     verbose;
    reg [31:0] model [0:255];

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    mem_stage uut (
        .clk              (clk),
        .reset            (reset),
        .mem_pc_plus4     (mem_pc_plus4),
        .mem_alu_result   (mem_alu_result),
        .mem_store_data   (mem_store_data),
        .mem_immediate    (mem_immediate),
        .mem_rd_addr      (mem_rd_addr),
        .mem_mem_read     (mem_mem_read),
        .mem_mem_write    (mem_mem_write),
        .mem_reg_write    (mem_reg_write),
        .mem_wb_sel       (mem_wb_sel),
        .mem_valid        (mem_valid),
        .wb_alu_result    (wb_alu_result),
        .wb_mem_read_data (wb_mem_read_data),
        .wb_pc_plus4      (wb_pc_plus4),
        .wb_immediate     (wb_immediate),
        .wb_rd_addr       (wb_rd_addr),
        .wb_reg_write     (wb_reg_write),
        .wb_sel           (wb_sel),
        .wb_valid         (wb_valid)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("simulations/mem_stage.vcd");
        $dumpvars(0, tb_mem_stage);
    end

    // Watchdog
    initial begin
        #1000000;
        $display("[FAIL] WATCHDOG TIMEOUT");
        $display("MEM STAGE VERIFICATION FAILED");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Task: apply one EX/MEM entry for one clock cycle. Inputs change at the
    // falling edge; returns 1 ns after the rising edge that captures them.
    //--------------------------------------------------------------------------
    task mem_op;
        input [31:0] pc4;
        input [31:0] alu;
        input [31:0] st;
        input [31:0] imm;
        input [4:0]  rd;
        input        mr;
        input        mw;
        input        rw;
        input [1:0]  wbs;
        input        val;
        begin
            @(negedge clk);
            mem_pc_plus4   = pc4;
            mem_alu_result = alu;
            mem_store_data = st;
            mem_immediate  = imm;
            mem_rd_addr    = rd;
            mem_mem_read   = mr;
            mem_mem_write  = mw;
            mem_reg_write  = rw;
            mem_wb_sel     = wbs;
            mem_valid      = val;
            @(posedge clk);
            #1;
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: compare all 8 MEM/WB outputs (!== catches X/Z)
    //--------------------------------------------------------------------------
    task chk_wb;
        input [319:0] name;
        input [31:0]  e_alu;
        input [31:0]  e_rdata;
        input [31:0]  e_pc4;
        input [31:0]  e_imm;
        input [4:0]   e_rd;
        input         e_rw;
        input [1:0]   e_wbs;
        input         e_val;
        reg bad;
        begin
            total_tests = total_tests + 1;
            bad = 1'b0;
            if (wb_alu_result    !== e_alu)   bad = 1'b1;
            if (wb_mem_read_data !== e_rdata) bad = 1'b1;
            if (wb_pc_plus4      !== e_pc4)   bad = 1'b1;
            if (wb_immediate     !== e_imm)   bad = 1'b1;
            if (wb_rd_addr       !== e_rd)    bad = 1'b1;
            if (wb_reg_write     !== e_rw)    bad = 1'b1;
            if (wb_sel           !== e_wbs)   bad = 1'b1;
            if (wb_valid         !== e_val)   bad = 1'b1;
            if (bad) begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s", total_tests, name);
                if (wb_alu_result    !== e_alu)   $display("       alu_result    actual=%h expected=%h", wb_alu_result, e_alu);
                if (wb_mem_read_data !== e_rdata) $display("       mem_read_data actual=%h expected=%h", wb_mem_read_data, e_rdata);
                if (wb_pc_plus4      !== e_pc4)   $display("       pc_plus4      actual=%h expected=%h", wb_pc_plus4, e_pc4);
                if (wb_immediate     !== e_imm)   $display("       immediate     actual=%h expected=%h", wb_immediate, e_imm);
                if (wb_rd_addr       !== e_rd)    $display("       rd_addr       actual=%0d expected=%0d", wb_rd_addr, e_rd);
                if (wb_reg_write     !== e_rw)    $display("       reg_write     actual=%b expected=%b", wb_reg_write, e_rw);
                if (wb_sel           !== e_wbs)   $display("       wb_sel        actual=%b expected=%b", wb_sel, e_wbs);
                if (wb_valid         !== e_val)   $display("       valid         actual=%b expected=%b", wb_valid, e_val);
            end
            else begin
                passed_tests = passed_tests + 1;
                if (verbose)
                    $display("[PASS] #%0d %0s | alu=%h rdata=%h rd=%0d valid=%b",
                             total_tests, name, wb_alu_result,
                             wb_mem_read_data, wb_rd_addr, wb_valid);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: SW (valid or not). Checks the MEM/WB capture; a store reads
    // nothing, so wb_mem_read_data must be 0. Updates the model only when
    // 'upd' is set (valid SW to a valid address).
    //--------------------------------------------------------------------------
    task do_sw;
        input [319:0] name;
        input [31:0]  addr;
        input [31:0]  data;
        input         val;
        input         upd;
        input integer widx;
        begin
            mem_op(32'h44, addr, data, 32'h8, 5'd0,
                   1'b0, 1'b1, 1'b0, 2'b00, val);
            chk_wb(name, addr, 32'h0, 32'h44, 32'h8, 5'd0, 1'b0, 2'b00, val);
            if (upd)
                model[widx] = data;
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: LW (valid or not). Expected read data is given explicitly.
    //--------------------------------------------------------------------------
    task do_lw;
        input [319:0] name;
        input [31:0]  addr;
        input [4:0]   rd;
        input [31:0]  exp_data;
        input         val;
        begin
            mem_op(32'h48, addr, 32'hBAD0BAD0, 32'h8, rd,
                   1'b1, 1'b0, 1'b1, 2'b01, val);
            chk_wb(name, addr, exp_data, 32'h48, 32'h8, rd, 1'b1, 2'b01, val);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: one stored word against a literal
    //--------------------------------------------------------------------------
    task chk_mem;
        input [319:0] name;
        input integer widx;
        input [31:0]  expected;
        begin
            total_tests = total_tests + 1;
            if (uut.u_dmem.mem[widx] !== expected) begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s | word %0d actual=%h expected=%h",
                         total_tests, name, widx, uut.u_dmem.mem[widx], expected);
            end
            else begin
                passed_tests = passed_tests + 1;
                if (verbose)
                    $display("[PASS] #%0d %0s | word %0d = %h",
                             total_tests, name, widx, expected);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: all 256 stored words against the model (counted as ONE test)
    //--------------------------------------------------------------------------
    task check_all;
        input [319:0] name;
        integer q;
        integer errs;
        begin
            errs = 0;
            for (q = 0; q < 256; q = q + 1) begin
                if (uut.u_dmem.mem[q] !== model[q]) begin
                    errs = errs + 1;
                    $display("       mismatch word %0d: actual=%h expected=%h",
                             q, uut.u_dmem.mem[q], model[q]);
                end
            end
            total_tests = total_tests + 1;
            if (errs == 0) begin
                passed_tests = passed_tests + 1;
                $display("[PASS] #%0d %0s | all 256 words match", total_tests, name);
            end
            else begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s | %0d word mismatches",
                         total_tests, name, errs);
            end
        end
    endtask

   task sweep_end;
    input [319:0] name;
    input integer prior_fail_count;
    begin
        if (failed_tests == prior_fail_count)
            $display("[PASS] %0s | sweep completed, no mismatches", name);
        else
            $display("[FAIL] %0s | sweep had %0d mismatches",
                     name, failed_tests - prior_fail_count);
    end
endtask

    //--------------------------------------------------------------------------
    // Main stimulus
    //--------------------------------------------------------------------------
    initial begin
        total_tests    = 0;
        passed_tests   = 0;
        failed_tests   = 0;
        verbose        = 1'b1;
        reset          = 1'b1;
        mem_pc_plus4   = 32'h0;
        mem_alu_result = 32'h0;
        mem_store_data = 32'h0;
        mem_immediate  = 32'h0;
        mem_rd_addr    = 5'd0;
        mem_mem_read   = 1'b0;
        mem_mem_write  = 1'b0;
        mem_reg_write  = 1'b0;
        mem_wb_sel     = 2'b00;
        mem_valid      = 1'b0;
        for (k = 0; k < 256; k = k + 1)
            model[k] = 32'h00000000;

        $display("==============================================================");
        $display(" MEM Stage Self-Checking Testbench Started");
        $display("==============================================================");

        // Reset held through the first rising edge (5 ns)
        @(posedge clk);
        #1;
        reset = 1'b0;

        //======================================================================
        // 1. Reset
        //======================================================================
        $display("--- 1. Reset ---");
        chk_wb("1.1 reset clears MEM/WB", 32'h0, 32'h0, 32'h0, 32'h0,
               5'd0, 1'b0, 2'b00, 1'b0);
        check_all("1.2 data memory initially zero");

        //======================================================================
        // 2. SW
        //======================================================================
        $display("--- 2. SW ---");
        do_sw("2.1 SW 0x10", 32'h10, 32'hDEADBEEF, 1'b1, 1'b1, 4);
        chk_mem("2.2 word 4 holds the data", 4, 32'hDEADBEEF);
        check_all("2.3 only word 4 changed");
        do_sw("2.4 SW 0x00", 32'h00, 32'h11111111, 1'b1, 1'b1, 0);
        chk_mem("2.5 word 0 holds the data", 0, 32'h11111111);
        do_sw("2.6 SW 0x3FC (last word)", 32'h3FC, 32'h22222222, 1'b1, 1'b1, 255);
        chk_mem("2.7 word 255 holds the data", 255, 32'h22222222);
        do_sw("2.8 SW 0x3F8", 32'h3F8, 32'h33333333, 1'b1, 1'b1, 254);
        chk_mem("2.9 word 254 holds the data", 254, 32'h33333333);
        do_sw("2.10 SW 0x04", 32'h04, 32'h44444444, 1'b1, 1'b1, 1);
        check_all("2.11 four distinct words written");
        do_sw("2.12 SW 0x10 overwrite", 32'h10, 32'h55555555, 1'b1, 1'b1, 4);
        chk_mem("2.13 word 4 overwritten", 4, 32'h55555555);
        check_all("2.14 overwrite touched only word 4");

        //======================================================================
        // 3. LW
        //======================================================================
        $display("--- 3. LW ---");
        do_lw("3.1 LW 0x10 -> x5",  32'h10,  5'd5,  32'h55555555, 1'b1);
        do_lw("3.2 LW 0x00 -> x1",  32'h00,  5'd1,  32'h11111111, 1'b1);
        do_lw("3.3 LW 0x04 -> x2",  32'h04,  5'd2,  32'h44444444, 1'b1);
        do_lw("3.4 LW 0x3F8 -> x31",32'h3F8, 5'd31, 32'h33333333, 1'b1);
        do_lw("3.5 LW 0x3FC -> x30",32'h3FC, 5'd30, 32'h22222222, 1'b1);
        do_lw("3.6 LW unwritten word 2", 32'h08, 5'd6, 32'h00000000, 1'b1);
        do_lw("3.7 LW with rd = x0 (captured)", 32'h10, 5'd0, 32'h55555555, 1'b1);
        check_all("3.8 loads changed no memory");

        //======================================================================
        // 4. Back-to-back operations (no idle cycle between them)
        //======================================================================
        $display("--- 4. Back-to-back ---");
        do_sw("4.1 SW 0x40", 32'h40, 32'hAAAA0001, 1'b1, 1'b1, 16);
        do_sw("4.2 SW 0x44 right after", 32'h44, 32'hBBBB0002, 1'b1, 1'b1, 17);
        do_lw("4.3 LW 0x40 right after", 32'h40, 5'd7, 32'hAAAA0001, 1'b1);
        do_lw("4.4 LW 0x44 right after", 32'h44, 5'd8, 32'hBBBB0002, 1'b1);
        do_sw("4.5 SW 0x48", 32'h48, 32'hCCCC0003, 1'b1, 1'b1, 18);
        do_lw("4.6 LW same word next cycle", 32'h48, 5'd9, 32'hCCCC0003, 1'b1);
        do_lw("4.7 LW 0x48 again", 32'h48, 5'd9, 32'hCCCC0003, 1'b1);
        do_sw("4.8 SW same word, new data", 32'h48, 32'hDDDD0004, 1'b1, 1'b1, 18);
        do_lw("4.9 LW sees the new data", 32'h48, 5'd9, 32'hDDDD0004, 1'b1);
        check_all("4.10 memory matches model");

        //======================================================================
        // 5. Invalid pipeline entries (valid = 0): no side effects
        //======================================================================
        $display("--- 5. Invalid entries ---");
        do_sw("5.1 SW valid=0 to written word", 32'h10, 32'hBAD00001, 1'b0, 1'b0, 4);
        chk_mem("5.2 word 4 unchanged", 4, 32'h55555555);
        do_sw("5.3 SW valid=0 to empty word", 32'h20, 32'hBAD00002, 1'b0, 1'b0, 8);
        chk_mem("5.4 word 8 still zero", 8, 32'h00000000);
        do_lw("5.5 LW valid=0: read gated to 0", 32'h10, 5'd5, 32'h00000000, 1'b0);
        do_lw("5.6 LW valid=0 at 0x00: 0", 32'h00, 5'd1, 32'h00000000, 1'b0);
        mem_op(32'h4C, 32'h10, 32'hBAD00003, 32'h8, 5'd5,
               1'b1, 1'b1, 1'b1, 2'b01, 1'b0);
        chk_wb("5.7 rd+wr, valid=0: no effect", 32'h10, 32'h0, 32'h4C, 32'h8,
               5'd5, 1'b1, 2'b01, 1'b0);
        chk_mem("5.8 word 4 unchanged by rd+wr", 4, 32'h55555555);
        check_all("5.9 invalid entries changed nothing");
        do_lw("5.10 valid LW right after invalid", 32'h10, 5'd5, 32'h55555555, 1'b1);

        //======================================================================
        // 6. Invalid addresses (valid = 1): reads give 0, writes ignored
        //    (words 0, 1, 4 and 255 hold non-zero data, so aliases would show)
        //======================================================================
        $display("--- 6. Invalid addresses ---");
        do_lw("6.1 LW 0x400 out of range",   32'h400,      5'd5, 32'h0, 1'b1);
        do_lw("6.2 LW 0x404 out of range",   32'h404,      5'd5, 32'h0, 1'b1);
        do_lw("6.3 LW 0x11 misaligned",      32'h11,       5'd5, 32'h0, 1'b1);
        do_lw("6.4 LW 0x12 misaligned",      32'h12,       5'd5, 32'h0, 1'b1);
        do_lw("6.5 LW 0x13 misaligned",      32'h13,       5'd5, 32'h0, 1'b1);
        do_lw("6.6 LW 0x80000010 high",      32'h80000010, 5'd5, 32'h0, 1'b1);
        do_lw("6.7 LW 0xFFFFFFFF high",      32'hFFFFFFFF, 5'd5, 32'h0, 1'b1);
        do_lw("6.8 LW 0x410 (alias of word 4)", 32'h410,   5'd5, 32'h0, 1'b1);
        do_sw("6.9 SW 0x400 ignored",        32'h400,      32'hBAD10001, 1'b1, 1'b0, 0);
        do_sw("6.10 SW 0x11 ignored",        32'h11,       32'hBAD10002, 1'b1, 1'b0, 0);
        do_sw("6.11 SW 0x12 ignored",        32'h12,       32'hBAD10003, 1'b1, 1'b0, 0);
        do_sw("6.12 SW 0x410 (alias) ignored",32'h410,     32'hBAD10004, 1'b1, 1'b0, 0);
        do_sw("6.13 SW 0x80000010 ignored",  32'h80000010, 32'hBAD10005, 1'b1, 1'b0, 0);
        do_sw("6.14 SW 0xFFFFFFFF ignored",  32'hFFFFFFFF, 32'hBAD10006, 1'b1, 1'b0, 0);
        do_sw("6.15 SW 0x3FD ignored",       32'h3FD,      32'hBAD10007, 1'b1, 1'b0, 0);
        check_all("6.16 invalid writes corrupted nothing");

        //======================================================================
        // 7. Non-memory instructions pass through (mem_read = mem_write = 0)
        //======================================================================
        $display("--- 7. Non-memory pass-through ---");
        // ADD-like. ALU result 0x10 points at a non-zero word: the read must
        // still be gated off (rdata 0) and the store data must not be written.
        mem_op(32'h54, 32'h10, 32'hBAD20001, 32'h0, 5'd3,
               1'b0, 1'b0, 1'b1, 2'b00, 1'b1);
        chk_wb("7.1 ADD-like: fields pass, rdata 0", 32'h10, 32'h0, 32'h54,
               32'h0, 5'd3, 1'b1, 2'b00, 1'b1);
        check_all("7.2 ADD-like wrote nothing");
        mem_op(32'h104, 32'h120, 32'h0, 32'h20, 5'd1,
               1'b0, 1'b0, 1'b1, 2'b10, 1'b1);
        chk_wb("7.3 JAL-like: wb_sel=10", 32'h120, 32'h0, 32'h104, 32'h20,
               5'd1, 1'b1, 2'b10, 1'b1);
        mem_op(32'h304, 32'h12345000, 32'h0, 32'h12345000, 5'd9,
               1'b0, 1'b0, 1'b1, 2'b11, 1'b1);
        chk_wb("7.4 LUI-like: wb_sel=11", 32'h12345000, 32'h0, 32'h304,
               32'h12345000, 5'd9, 1'b1, 2'b11, 1'b1);
        mem_op(32'h104, 32'h120, 32'h5, 32'h20, 5'd0,
               1'b0, 1'b0, 1'b0, 2'b00, 1'b1);
        chk_wb("7.5 branch-like: reg_write=0", 32'h120, 32'h0, 32'h104, 32'h20,
               5'd0, 1'b0, 2'b00, 1'b1);
        mem_op(32'h60, 32'h10, 32'h7, 32'h9, 5'd4,
               1'b0, 1'b0, 1'b1, 2'b11, 1'b0);
        chk_wb("7.6 bubble: fields kept, valid=0", 32'h10, 32'h0, 32'h60, 32'h9,
               5'd4, 1'b1, 2'b11, 1'b0);
        mem_op(32'hFFFFFFFC, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF, 5'd31,
               1'b0, 1'b0, 1'b1, 2'b11, 1'b1);
        chk_wb("7.7 all-ones fields captured", 32'hFFFFFFFF, 32'h0,
               32'hFFFFFFFC, 32'hFFFFFFFF, 5'd31, 1'b1, 2'b11, 1'b1);
        check_all("7.8 pass-through wrote nothing");

        //======================================================================
        // 8. Reset behaviour
        //======================================================================
        $display("--- 8. Reset ---");
        do_lw("8.1 LW before reset", 32'h10, 5'd5, 32'h55555555, 1'b1);
        reset = 1'b1;
        mem_op(32'h48, 32'h10, 32'hBAD0BAD0, 32'h8, 5'd5,
               1'b1, 1'b0, 1'b1, 2'b01, 1'b1);
        reset = 1'b0;
        chk_wb("8.2 reset clears MEM/WB", 32'h0, 32'h0, 32'h0, 32'h0,
               5'd0, 1'b0, 2'b00, 1'b0);
        do_lw("8.3 memory kept across reset", 32'h10, 5'd5, 32'h55555555, 1'b1);
        do_lw("8.4 LW 0x00 before sync test", 32'h00, 5'd1, 32'h11111111, 1'b1);
        @(negedge clk);
        reset = 1'b1;
        #2;
        chk_wb("8.5 reset high, before edge: old", 32'h00, 32'h11111111,
               32'h48, 32'h8, 5'd1, 1'b1, 2'b01, 1'b1);
        @(posedge clk);
        #1;
        reset = 1'b0;
        chk_wb("8.6 reset takes effect at edge", 32'h0, 32'h0, 32'h0, 32'h0,
               5'd0, 1'b0, 2'b00, 1'b0);
        do_lw("8.7 capture resumes after reset", 32'h04, 5'd2, 32'h44444444, 1'b1);
        check_all("8.8 memory intact after reset");

        //----------------------------------------------------------------------
        // 8b. Data memory writes are blocked during reset.
        //     Requires mem_stage.v to gate the memory controls with ~reset:
        //       dm_read  = mem_mem_read  & mem_valid & ~reset
        //       dm_write = mem_mem_write & mem_valid & ~reset
        //     Word 4 (address 0x10) holds 0x55555555 at this point (model[4]).
        //     The model is NOT updated for the write attempted during reset.
        //----------------------------------------------------------------------
        chk_mem("8.9 word 4 holds known data", 4, 32'h55555555);
        reset = 1'b1;
        mem_op(32'h44, 32'h10, 32'hBAD0BAD1, 32'h8, 5'd0,
               1'b0, 1'b1, 1'b0, 2'b00, 1'b1);       // valid SW during reset
        reset = 1'b0;
        chk_wb("8.10 reset+SW: MEM/WB all zero", 32'h0, 32'h0, 32'h0, 32'h0,
               5'd0, 1'b0, 2'b00, 1'b0);
        chk_mem("8.11 word 4 unchanged by reset SW", 4, 32'h55555555);
        check_all("8.12 reset-time SW changed nothing");
        // Normal operation resumes once reset is released
        do_sw("8.13 SW after reset released", 32'h10, 32'h66666666,
              1'b1, 1'b1, 4);
        chk_mem("8.14 word 4 holds the new data", 4, 32'h66666666);
        do_lw("8.15 LW returns the new data", 32'h10, 5'd5, 32'h66666666, 1'b1);
        check_all("8.16 memory matches updated model");

        //======================================================================
        // 9. Full address sweep: 256 SW, memory compare, 256 LW back-to-back
        //======================================================================
        $display("--- 9. Full address sweep ---");
        verbose      = 1'b0;
        fails_before = failed_tests;
        for (k = 0; k < 256; k = k + 1)
            do_sw("9.1 SW sweep", k * 4, (k * 32'h01010101) ^ 32'hA5A5A5A5,
                  1'b1, 1'b1, k);
        sweep_end("9.1 256 consecutive SW", fails_before);
        check_all("9.2 all 256 words match the model");
        fails_before = failed_tests;
        for (k = 0; k < 256; k = k + 1)
            do_lw("9.3 LW sweep", k * 4, k[4:0], model[k], 1'b1);
        sweep_end("9.3 256 consecutive LW", fails_before);
        verbose = 1'b1;

        //======================================================================
        // Summary
        //======================================================================
        #10;
        $display("==============================================================");
        $display(" MEM STAGE VERIFICATION SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");
        if (failed_tests == 0)
            $display("MEM STAGE VERIFICATION PASSED");
        else
            $display("MEM STAGE VERIFICATION FAILED");
        $finish;
    end

endmodule