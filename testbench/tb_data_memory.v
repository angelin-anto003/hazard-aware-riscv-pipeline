`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_data_memory
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// DUT         : data_memory (rtl/data_memory.v)
// Description : Self-checking Verilog-2001 testbench.
//
// Timing (race-free):
//   - 10 ns clock; rising edges at 5, 15, 25 ... ns, falling edges at 10, 20 ...
//   - Inputs are driven at the FALLING edge, so they are stable well before
//     the rising edge.
//   - Synchronous results are checked 1 ns AFTER the rising edge.
//   - Combinational results are checked 1 ns after an input change.
//
// Independence of expected values:
//   - Most checks use literal addresses and literal expected data.
//   - A reference array model[0:255] is indexed by WORD NUMBER and is updated
//     only by tasks that perform a valid write to an explicit word number.
//     Byte addresses are produced arithmetically (word*4). The RTL's
//     address-bit slicing is never copied into the testbench.
//   - Ignored (invalid) writes never update the model, so any invalid write
//     that corrupts memory shows up in check_all.
//
// Run from the repository root (the VCD path is relative).
//==============================================================================

module tb_data_memory;

    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------
    reg         clk;
    reg         mem_read;
    reg         mem_write;
    reg  [31:0] address;
    reg  [31:0] write_data;
    wire [31:0] read_data;

    //--------------------------------------------------------------------------
    // Bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer fails_before;
    integer k;
    integer b;

    reg [31:0] model [0:255];     // expected memory contents, by word number
    reg [31:0] tmp_addr;
    reg [31:0] snap;

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    data_memory uut (
        .clk        (clk),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .address    (address),
        .write_data (write_data),
        .read_data  (read_data)
    );

    //--------------------------------------------------------------------------
    // 10 ns clock (starts low: rising edges at 5, 15, 25 ... ns)
    //--------------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    //--------------------------------------------------------------------------
    // Waveform generation
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("simulations/data_memory.vcd");
        $dumpvars(0, tb_data_memory);
    end

    //--------------------------------------------------------------------------
    // Watchdog timeout
    //--------------------------------------------------------------------------
    initial begin
        #5000000;
        $display("[FAIL] WATCHDOG TIMEOUT: simulation did not finish");
        $display("DATA MEMORY VERIFICATION FAILED");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Task: compare one 32-bit value (case inequality catches X/Z)
    //--------------------------------------------------------------------------
    task check_val;
        input [319:0] name;
        input [31:0]  addr;
        input [31:0]  actual;
        input [31:0]  expected;
        input         show_pass;
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
                    $display("[PASS] %0s | address=%h data=%h", name, addr, actual);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: combinational read check. Drives address and mem_read, waits 1 ns
    //       for settling, then compares read_data. mem_write must be 0.
    //--------------------------------------------------------------------------
    task rd_chk;
        input [319:0] name;
        input [31:0]  addr;
        input         rd_en;
        input [31:0]  expected;
        input         show_pass;
        begin
            mem_read = rd_en;
            address  = addr;
            #1;
            check_val(name, addr, read_data, expected, show_pass);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: one raw write cycle. Inputs change at the falling edge, the write
    //       is captured at the next rising edge, and mem_write is deasserted
    //       1 ns after that edge. mem_read is held low during the cycle.
    //--------------------------------------------------------------------------
    task wr_cycle;
        input [31:0] addr;
        input [31:0] data;
        input        we;
        begin
            @(negedge clk);
            address    = addr;
            write_data = data;
            mem_write  = we;
            mem_read   = 1'b0;
            @(posedge clk);
            #1;
            mem_write  = 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: valid write to an explicit WORD NUMBER; updates the model
    //--------------------------------------------------------------------------
    task wr_word;
        input integer widx;
        input [31:0]  data;
        begin
            wr_cycle(widx * 4, data, 1'b1);
            model[widx] = data;
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: write attempt that must be IGNORED (invalid address); no model
    //       update, so any corruption is detected by check_all.
    //--------------------------------------------------------------------------
    task wr_ignored;
        input [31:0] addr;
        input [31:0] data;
        begin
            wr_cycle(addr, data, 1'b1);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: write cycle with mem_write LOW (must not modify memory)
    //--------------------------------------------------------------------------
    task wr_disabled;
        input [31:0] addr;
        input [31:0] data;
        begin
            wr_cycle(addr, data, 1'b0);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: read all 256 words (mem_read = 1) and compare with the model.
    //       Counted as ONE test; mismatching words are listed.
    //--------------------------------------------------------------------------
    task check_all;
        input [319:0] name;
        integer q;
        integer errs;
        begin
            errs     = 0;
            mem_read = 1'b1;
            for (q = 0; q < 256; q = q + 1) begin
                address = q * 4;
                #1;
                if (read_data !== model[q]) begin
                    errs = errs + 1;
                    $display("       mismatch word %0d: actual=%h expected=%h",
                             q, read_data, model[q]);
                end
            end
            total_tests = total_tests + 1;
            if (errs == 0) begin
                passed_tests = passed_tests + 1;
                $display("[PASS] %0s | all 256 words match", name);
            end
            else begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] %0s | %0d word mismatches", name, errs);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: one summary line for a sweep that printed nothing per check
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
    //--------------------------------------------------------------------------
    initial begin
        total_tests  = 0;
        passed_tests = 0;
        failed_tests = 0;
        mem_read     = 1'b0;
        mem_write    = 1'b0;
        address      = 32'h00000000;
        write_data   = 32'h00000000;
        for (k = 0; k < 256; k = k + 1)
            model[k] = 32'h00000000;
        #1;

        $display("==============================================================");
        $display(" Data Memory Self-Checking Testbench Started");
        $display("==============================================================");

        //======================================================================
        // 1. Initial contents
        //======================================================================
        $display("--- 1. Initial zero contents ---");
        check_all("1.1 all words zero at start");
        rd_chk("1.2 first word zero", 32'h00000000, 1'b1, 32'h0, 1'b1);
        rd_chk("1.3 last word zero",  32'h000003FC, 1'b1, 32'h0, 1'b1);

        //======================================================================
        // 2. Store and load one word
        //======================================================================
        $display("--- 2. Store and load ---");
        wr_word(1, 32'h12345678);
        rd_chk("2.1 load back word 1",     32'h00000004, 1'b1, 32'h12345678, 1'b1);
        rd_chk("2.2 neighbour word 0 zero",32'h00000000, 1'b1, 32'h00000000, 1'b1);
        rd_chk("2.3 neighbour word 2 zero",32'h00000008, 1'b1, 32'h00000000, 1'b1);
        check_all("2.4 only word 1 changed");

        //======================================================================
        // 3. Multiple addresses
        //======================================================================
        $display("--- 3. Multiple addresses ---");
        wr_word(0,   32'hDEADBEEF);
        wr_word(2,   32'hCAFEBABE);
        wr_word(10,  32'h0000000A);
        wr_word(100, 32'hA5A5A5A5);
        wr_word(254, 32'h5A5A5A5A);
        rd_chk("3.1 word 0",   32'h00000000, 1'b1, 32'hDEADBEEF, 1'b1);
        rd_chk("3.2 word 1",   32'h00000004, 1'b1, 32'h12345678, 1'b1);
        rd_chk("3.3 word 2",   32'h00000008, 1'b1, 32'hCAFEBABE, 1'b1);
        rd_chk("3.4 word 10",  32'h00000028, 1'b1, 32'h0000000A, 1'b1);
        rd_chk("3.5 word 100", 32'h00000190, 1'b1, 32'hA5A5A5A5, 1'b1);
        rd_chk("3.6 word 254", 32'h000003F8, 1'b1, 32'h5A5A5A5A, 1'b1);
        check_all("3.7 model matches after 6 writes");

        //======================================================================
        // 4. Write disabled
        //======================================================================
        $display("--- 4. Write disabled ---");
        wr_disabled(32'h00000028, 32'hFFFFFFFF);
        rd_chk("4.1 word 10 unchanged",  32'h00000028, 1'b1, 32'h0000000A, 1'b1);
        wr_disabled(32'h00000190, 32'h00000000);
        rd_chk("4.2 word 100 unchanged", 32'h00000190, 1'b1, 32'hA5A5A5A5, 1'b1);
        wr_disabled(32'h00000300, 32'h13131313);   // word 192, was zero
        rd_chk("4.3 word 192 still zero",32'h00000300, 1'b1, 32'h00000000, 1'b1);
        check_all("4.4 nothing changed by disabled writes");

        //======================================================================
        // 5. Read disabled
        //======================================================================
        $display("--- 5. Read disabled ---");
        rd_chk("5.1 mem_read=0, word 10",  32'h00000028, 1'b0, 32'h00000000, 1'b1);
        rd_chk("5.2 mem_read=0, word 100", 32'h00000190, 1'b0, 32'h00000000, 1'b1);
        rd_chk("5.3 mem_read=0, word 1",   32'h00000004, 1'b0, 32'h00000000, 1'b1);
        rd_chk("5.4 mem_read=1, word 10 again", 32'h00000028, 1'b1, 32'h0000000A, 1'b1);
        rd_chk("5.5 mem_read=1, word 100 again",32'h00000190, 1'b1, 32'hA5A5A5A5, 1'b1);

        //======================================================================
        // 6. Repeated writes to the same address
        //======================================================================
        $display("--- 6. Repeated writes ---");
        wr_word(20, 32'h11111111);
        wr_word(20, 32'h11111111);
        wr_word(20, 32'h11111111);
        rd_chk("6.1 word 20 after 3 equal writes", 32'h00000050, 1'b1, 32'h11111111, 1'b1);

        //======================================================================
        // 7. Overwrite existing data
        //======================================================================
        $display("--- 7. Overwrite ---");
        wr_word(20, 32'h22222222);
        rd_chk("7.1 word 20 overwritten once",  32'h00000050, 1'b1, 32'h22222222, 1'b1);
        wr_word(20, 32'h33333333);
        rd_chk("7.2 word 20 overwritten twice", 32'h00000050, 1'b1, 32'h33333333, 1'b1);
        wr_word(1,  32'h87654321);
        rd_chk("7.3 word 1 overwritten",        32'h00000004, 1'b1, 32'h87654321, 1'b1);
        rd_chk("7.4 word 0 unaffected",         32'h00000000, 1'b1, 32'hDEADBEEF, 1'b1);
        rd_chk("7.5 word 2 unaffected",         32'h00000008, 1'b1, 32'hCAFEBABE, 1'b1);
        check_all("7.6 model matches after overwrites");

        //======================================================================
        // 8. First and last valid addresses
        //======================================================================
        $display("--- 8. First and last addresses ---");
        wr_word(0,   32'hFFFFFFFF);
        rd_chk("8.1 first word all ones",   32'h00000000, 1'b1, 32'hFFFFFFFF, 1'b1);
        wr_word(255, 32'h80000000);
        rd_chk("8.2 last word 0x80000000",  32'h000003FC, 1'b1, 32'h80000000, 1'b1);
        wr_word(255, 32'h7FFFFFFF);
        rd_chk("8.3 last word 0x7FFFFFFF",  32'h000003FC, 1'b1, 32'h7FFFFFFF, 1'b1);
        wr_word(255, 32'hAAAAAAAA);
        rd_chk("8.4 last word 0xAAAAAAAA",  32'h000003FC, 1'b1, 32'hAAAAAAAA, 1'b1);
        wr_word(255, 32'h55555555);
        rd_chk("8.5 last word 0x55555555",  32'h000003FC, 1'b1, 32'h55555555, 1'b1);
        rd_chk("8.6 word 254 unaffected",   32'h000003F8, 1'b1, 32'h5A5A5A5A, 1'b1);
        rd_chk("8.7 first word still ones", 32'h00000000, 1'b1, 32'hFFFFFFFF, 1'b1);
        check_all("8.8 model matches, first/last written");

        //======================================================================
        // 9. Misaligned read and write addresses
        //    (words 0, 1 and 255 hold non-zero data, so aliasing is visible)
        //======================================================================
        $display("--- 9. Misaligned addresses ---");
        rd_chk("9.1 read 0x00000001", 32'h00000001, 1'b1, 32'h0, 1'b1);
        rd_chk("9.2 read 0x00000002", 32'h00000002, 1'b1, 32'h0, 1'b1);
        rd_chk("9.3 read 0x00000003", 32'h00000003, 1'b1, 32'h0, 1'b1);
        rd_chk("9.4 read 0x00000005", 32'h00000005, 1'b1, 32'h0, 1'b1);
        rd_chk("9.5 read 0x00000006", 32'h00000006, 1'b1, 32'h0, 1'b1);
        rd_chk("9.6 read 0x00000007", 32'h00000007, 1'b1, 32'h0, 1'b1);
        rd_chk("9.7 read 0x000003FD", 32'h000003FD, 1'b1, 32'h0, 1'b1);
        rd_chk("9.8 read 0x000003FE", 32'h000003FE, 1'b1, 32'h0, 1'b1);
        rd_chk("9.9 read 0x000003FF", 32'h000003FF, 1'b1, 32'h0, 1'b1);

        wr_ignored(32'h00000001, 32'hBAD00001);
        wr_ignored(32'h00000002, 32'hBAD00002);
        wr_ignored(32'h00000003, 32'hBAD00003);
        wr_ignored(32'h00000005, 32'hBAD00005);
        wr_ignored(32'h00000006, 32'hBAD00006);
        wr_ignored(32'h00000007, 32'hBAD00007);
        wr_ignored(32'h000003FD, 32'hBAD003FD);
        wr_ignored(32'h000003FE, 32'hBAD003FE);
        wr_ignored(32'h000003FF, 32'hBAD003FF);
        check_all("9.10 misaligned writes ignored");

        // Misaligned sweep over every word (offsets 1..3), read side
        fails_before = failed_tests;
        for (k = 0; k < 256; k = k + 1) begin
            rd_chk("9.11 misaligned +1", k * 4 + 1, 1'b1, 32'h0, 1'b0);
            rd_chk("9.12 misaligned +2", k * 4 + 2, 1'b1, 32'h0, 1'b0);
            rd_chk("9.13 misaligned +3", k * 4 + 3, 1'b1, 32'h0, 1'b0);
        end
        sweep_end("9.11-13 misaligned read sweep", fails_before);

        //======================================================================
        // 10. Out-of-range read and write addresses
        //======================================================================
        $display("--- 10. Out-of-range addresses ---");
        rd_chk("10.1 read 0x00000400", 32'h00000400, 1'b1, 32'h0, 1'b1);
        rd_chk("10.2 read 0x00000404", 32'h00000404, 1'b1, 32'h0, 1'b1);
        rd_chk("10.3 read 0x00000800", 32'h00000800, 1'b1, 32'h0, 1'b1);
        rd_chk("10.4 read 0x00010000", 32'h00010000, 1'b1, 32'h0, 1'b1);

        wr_ignored(32'h00000400, 32'hBAD00400);
        wr_ignored(32'h00000404, 32'hBAD00404);
        wr_ignored(32'h00000800, 32'hBAD00800);
        wr_ignored(32'h00010000, 32'hBAD10000);
        check_all("10.5 out-of-range writes ignored");

        // Alias sweep: 0x400 + k*4 would alias onto word k if bit 10+ ignored
        fails_before = failed_tests;
        for (k = 0; k < 256; k = k + 1)
            wr_ignored(32'h00000400 + k * 4, 32'hBAD00000 + k);
        check_all("10.6 alias writes did not corrupt");
        for (k = 0; k < 256; k = k + 1)
            rd_chk("10.7 alias read", 32'h00000400 + k * 4, 1'b1, 32'h0, 1'b0);
        sweep_end("10.7 alias reads return zero", fails_before);

        //======================================================================
        // 11. High addresses
        //======================================================================
        $display("--- 11. High addresses ---");
        rd_chk("11.1 read 0x40000000", 32'h40000000, 1'b1, 32'h0, 1'b1);
        rd_chk("11.2 read 0x7FFFFFFC", 32'h7FFFFFFC, 1'b1, 32'h0, 1'b1);
        rd_chk("11.3 read 0x80000000", 32'h80000000, 1'b1, 32'h0, 1'b1);
        rd_chk("11.4 read 0x80000004", 32'h80000004, 1'b1, 32'h0, 1'b1);
        rd_chk("11.5 read 0x800003FC", 32'h800003FC, 1'b1, 32'h0, 1'b1);
        rd_chk("11.6 read 0xFFFFFFFC", 32'hFFFFFFFC, 1'b1, 32'h0, 1'b1);
        rd_chk("11.7 read 0xFFFFFFFF", 32'hFFFFFFFF, 1'b1, 32'h0, 1'b1);

        wr_ignored(32'h40000000, 32'hBAD40000);
        wr_ignored(32'h7FFFFFFC, 32'hBAD7FFFC);
        wr_ignored(32'h80000000, 32'hBAD80000);
        wr_ignored(32'h80000004, 32'hBAD80004);
        wr_ignored(32'h800003FC, 32'hBAD803FC);
        wr_ignored(32'hFFFFFFFC, 32'hBADFFFFC);
        wr_ignored(32'hFFFFFFFF, 32'hBADFFFFF);
        check_all("11.8 high-address writes ignored");

        // Every upper address bit (10..31) on its own and with 0x3FC
        fails_before = failed_tests;
        for (b = 10; b < 32; b = b + 1) begin
            tmp_addr = 32'd1 << b;
            wr_ignored(tmp_addr, 32'hC0DEC0DE);
            wr_ignored(tmp_addr | 32'h000003FC, 32'hC0DEC0DF);
            rd_chk("11.9 single upper bit",  tmp_addr,                   1'b1, 32'h0, 1'b0);
            rd_chk("11.10 upper bit + 0x3FC", tmp_addr | 32'h000003FC,   1'b1, 32'h0, 1'b0);
        end
        sweep_end("11.9-10 every upper bit rejected", fails_before);
        check_all("11.11 upper-bit writes ignored");

        //======================================================================
        // 12. Back-to-back writes on consecutive clock cycles
        //======================================================================
        $display("--- 12. Back-to-back writes ---");
        // Eight different words, one write per clock cycle, no idle cycles
        for (k = 0; k < 8; k = k + 1) begin
            @(negedge clk);
            address    = (30 + k) * 4;
            write_data = 32'hB2B20000 + k;
            mem_write  = 1'b1;
            mem_read   = 1'b0;
            model[30 + k] = 32'hB2B20000 + k;
        end
        @(posedge clk);
        #1;
        mem_write = 1'b0;
        rd_chk("12.1 word 30", 32'h00000078, 1'b1, 32'hB2B20000, 1'b1);
        rd_chk("12.2 word 33", 32'h00000084, 1'b1, 32'hB2B20003, 1'b1);
        rd_chk("12.3 word 37", 32'h00000094, 1'b1, 32'hB2B20007, 1'b1);
        check_all("12.4 all 8 back-to-back writes kept");

        // Three consecutive writes to the SAME word: last value must win
        for (k = 1; k <= 3; k = k + 1) begin
            @(negedge clk);
            address    = 32'h000000A0;           // word 40
            write_data = 32'h40404000 + k;
            mem_write  = 1'b1;
            mem_read   = 1'b0;
            model[40]  = 32'h40404000 + k;
        end
        @(posedge clk);
        #1;
        mem_write = 1'b0;
        rd_chk("12.5 same word, last write wins", 32'h000000A0, 1'b1, 32'h40404003, 1'b1);

        //======================================================================
        // 13. Asynchronous reads: address changes without a clock edge.
        //     All steps below finish ~6 ns after a rising edge, before the
        //     next one, and mem_write stays low.
        //======================================================================
        $display("--- 13. Asynchronous read behaviour ---");
        wr_word(50, 32'h0A0A0A0A);
        wr_word(51, 32'h0B0B0B0B);
        wr_word(52, 32'h0C0C0C0C);
        rd_chk("13.1 async read word 50",       32'h000000C8, 1'b1, 32'h0A0A0A0A, 1'b1);
        rd_chk("13.2 async read word 51",       32'h000000CC, 1'b1, 32'h0B0B0B0B, 1'b1);
        rd_chk("13.3 async read word 52",       32'h000000D0, 1'b1, 32'h0C0C0C0C, 1'b1);
        rd_chk("13.4 async invalid -> zero",    32'h00000400, 1'b1, 32'h00000000, 1'b1);
        rd_chk("13.5 async back to word 50",    32'h000000C8, 1'b1, 32'h0A0A0A0A, 1'b1);

        // mem_read toggled alone (address held): output follows immediately
        mem_read = 1'b0;
        #1;
        check_val("13.6 mem_read low -> zero", 32'h000000C8, read_data, 32'h0, 1'b1);
        mem_read = 1'b1;
        #1;
        check_val("13.7 mem_read high -> data", 32'h000000C8, read_data, 32'h0A0A0A0A, 1'b1);

        // Output stays stable while nothing changes (several clock edges pass)
        snap = read_data;
        #40;
        check_val("13.8 stable across clock edges", 32'h000000C8, read_data, snap, 1'b1);
        check_val("13.9 stable value is word 50",   32'h000000C8, read_data, 32'h0A0A0A0A, 1'b1);

        //======================================================================
        // 14. Read / write control combinations
        //======================================================================
        $display("--- 14. Read/write control combinations ---");
        wr_word(60, 32'h60606060);

        // (mem_read, mem_write) = (0, 0): nothing happens
        @(negedge clk);
        address = 32'h000000F0; write_data = 32'h99999999;
        mem_read = 1'b0; mem_write = 1'b0;
        @(posedge clk);
        #1;
        check_val("14.1 rd=0 wr=0: read_data zero", 32'h000000F0, read_data, 32'h0, 1'b1);
        rd_chk("14.2 rd=0 wr=0: no write",          32'h000000F0, 1'b1, 32'h60606060, 1'b1);

        // (0, 1): write only; read_data stays zero, memory is updated
        wr_cycle(32'h000000F0, 32'h61616161, 1'b1);
        model[60] = 32'h61616161;
        check_val("14.3 rd=0 wr=1: read_data zero", 32'h000000F0, read_data, 32'h0, 1'b1);
        rd_chk("14.4 rd=0 wr=1: memory updated",    32'h000000F0, 1'b1, 32'h61616161, 1'b1);

        // (1, 0): read only
        rd_chk("14.5 rd=1 wr=0: returns data",      32'h000000F0, 1'b1, 32'h61616161, 1'b1);

        // (1, 1) same valid address: old data before the edge, new after it
        @(negedge clk);
        address    = 32'h000000F0;
        write_data = 32'h62626262;
        mem_read   = 1'b1;
        mem_write  = 1'b1;
        #2;
        check_val("14.6 rd=1 wr=1 before edge: old", 32'h000000F0, read_data, 32'h61616161, 1'b1);
        @(posedge clk);
        #1;
        mem_write = 1'b0;
        model[60] = 32'h62626262;
        check_val("14.7 rd=1 wr=1 after edge: new",  32'h000000F0, read_data, 32'h62626262, 1'b1);

        // (1, 1) with INVALID addresses: read zero, write ignored
        @(negedge clk);
        address    = 32'h00000400;
        write_data = 32'hBAD0BAD0;
        mem_read   = 1'b1;
        mem_write  = 1'b1;
        #2;
        check_val("14.8 rd=1 wr=1 out of range: 0", 32'h00000400, read_data, 32'h0, 1'b1);
        @(posedge clk);
        #1;
        check_val("14.9 same after edge: still 0",  32'h00000400, read_data, 32'h0, 1'b1);
        mem_write = 1'b0;

        @(negedge clk);
        address    = 32'h000000F1;              // misaligned alias of word 60
        write_data = 32'hBAD1BAD1;
        mem_read   = 1'b1;
        mem_write  = 1'b1;
        #2;
        check_val("14.10 rd=1 wr=1 misaligned: 0",  32'h000000F1, read_data, 32'h0, 1'b1);
        @(posedge clk);
        #1;
        mem_write = 1'b0;
        rd_chk("14.11 word 60 not corrupted",       32'h000000F0, 1'b1, 32'h62626262, 1'b1);

        //======================================================================
        // 15/16. Invalid operations never corrupt valid memory
        //======================================================================
        $display("--- 15/16. Memory integrity after invalid operations ---");
        wr_ignored(32'h00000001, 32'hDEAD0001);
        wr_ignored(32'h000003FF, 32'hDEAD03FF);
        wr_ignored(32'h00000400, 32'hDEAD0400);
        wr_ignored(32'h80000000, 32'hDEAD8000);
        wr_ignored(32'hFFFFFFFF, 32'hDEADFFFF);
        wr_disabled(32'h000000F0, 32'hDEAD00F0);
        wr_disabled(32'h000003FC, 32'hDEAD03FC);
        check_all("15.1 model matches after invalid ops");
        rd_chk("15.2 word 0 intact",   32'h00000000, 1'b1, 32'hFFFFFFFF, 1'b1);
        rd_chk("15.3 word 255 intact", 32'h000003FC, 1'b1, 32'h55555555, 1'b1);
        rd_chk("15.4 word 60 intact",  32'h000000F0, 1'b1, 32'h62626262, 1'b1);

        //======================================================================
        // Final full-memory check
        //======================================================================
        $display("--- Final check ---");
        check_all("Z1 final full-memory comparison");

        //======================================================================
        // Final summary
        //======================================================================
        #10;
        $display("==============================================================");
        $display(" DATA MEMORY VERIFICATION SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");

        if (failed_tests == 0)
            $display("DATA MEMORY VERIFICATION PASSED");
        else
            $display("DATA MEMORY VERIFICATION FAILED");

        $finish;
    end

endmodule