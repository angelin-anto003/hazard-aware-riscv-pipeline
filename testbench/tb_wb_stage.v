`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_wb_stage
// DUT         : wb_stage (combinational) driving a separately instantiated
//               register_file in the testbench
// Description : Self-checking Verilog-2001 testbench with a reference model.
//
// Reference model: model[0:31] holds the expected register contents. It is
// updated only when a write is expected (reg_write & valid & rd != 0), with
// the value selected by a separately written case statement. Writes during
// reset clear the model.
//
// Timing (race-free): 10 ns clock, rising edges at 5, 15, 25 ... ns.
//   - Inputs change at the FALLING edge.
//   - Pre-edge checks run 2 ns later (3 ns BEFORE the rising edge): they
//     prove a write is not visible before the clock edge.
//   - Post-edge checks run 1 ns AFTER the rising edge.
//   - wb_cycle deasserts reg_write/valid 1 ns after the edge, so every write
//     lasts exactly ONE clock edge. (Leaving them asserted caused a stray
//     write at the next edge that the reference model did not know about.)
//
// Run from the repository root.
//==============================================================================

module tb_wb_stage;

    reg         clk;
    reg         reset;
    reg  [31:0] wb_alu_result;
    reg  [31:0] wb_mem_read_data;
    reg  [31:0] wb_pc_plus4;
    reg  [31:0] wb_immediate;
    reg  [4:0]  wb_rd_addr;
    reg         wb_reg_write;
    reg  [1:0]  wb_sel;
    reg         wb_valid;
    reg  [4:0]  read_addr1;
    reg  [4:0]  read_addr2;

    wire [31:0] wb_data;
    wire        wb_write_enable;
    wire [4:0]  wb_write_addr;
    wire [31:0] read_data1;
    wire [31:0] read_data2;

    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer fails_before;
    integer k;
    integer seed;
    integer r1, r2, r3, r4, r5;
    reg     verbose;
    reg [31:0] model [0:31];

    //--------------------------------------------------------------------------
    // DUT: write-back stage (mux and write enable)
    //--------------------------------------------------------------------------
    wb_stage uut (
        .wb_alu_result    (wb_alu_result),
        .wb_mem_read_data (wb_mem_read_data),
        .wb_pc_plus4      (wb_pc_plus4),
        .wb_immediate     (wb_immediate),
        .wb_rd_addr       (wb_rd_addr),
        .wb_reg_write     (wb_reg_write),
        .wb_sel           (wb_sel),
        .wb_valid         (wb_valid),
        .wb_data          (wb_data),
        .wb_write_enable  (wb_write_enable),
        .wb_write_addr    (wb_write_addr)
    );

    //--------------------------------------------------------------------------
    // Existing register file, instantiated separately (as id_stage does in
    // the processor). Its write port is driven by the wb_stage outputs.
    //--------------------------------------------------------------------------
    register_file u_regfile (
        .clk          (clk),
        .reset        (reset),
        .read_addr1   (read_addr1),
        .read_addr2   (read_addr2),
        .read_data1   (read_data1),
        .read_data2   (read_data2),
        .write_enable (wb_write_enable),
        .write_addr   (wb_write_addr),
        .write_data   (wb_data)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("simulations/wb_stage.vcd");
        $dumpvars(0, tb_wb_stage);
    end

    // Watchdog
    initial begin
        #1000000;
        $display("[FAIL] WATCHDOG TIMEOUT");
        $display("WB STAGE VERIFICATION FAILED");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Task: one write-back cycle with full checking.
    //   Pre-edge : wb_data, wb_write_enable, wb_write_addr correct; target
    //              register NOT yet changed (both read ports still show the
    //              old model).
    //   Post-edge: both read ports match the updated model.
    //   Each comparison has its own flag so a failure names the exact check.
    //   The write inputs are deasserted 1 ns after the edge (one-edge write).
    //--------------------------------------------------------------------------
    task wb_cycle;
        input [319:0] name;
        input [4:0]   rd;
        input         rw;
        input         v;
        input [1:0]   sel;
        input [31:0]  alu;
        input [31:0]  mem;
        input [31:0]  pc4;
        input [31:0]  imm;
        reg [31:0] e_data;
        reg        e_en;
        reg [4:0]  ra2;
        reg        f_data;      // wb_data mismatch
        reg        f_en;        // wb_write_enable mismatch
        reg        f_addr;      // wb_write_addr mismatch
        reg        f_pre1;      // pre-edge read port 1 mismatch
        reg        f_pre2;      // pre-edge read port 2 mismatch
        reg        f_post1;     // post-edge read port 1 mismatch
        reg        f_post2;     // post-edge read port 2 mismatch
        reg [31:0] pre_d1;      // captured pre-edge read data
        reg [31:0] pre_d2;
        reg [31:0] pre_e1;      // captured pre-edge expectations
        reg [31:0] pre_e2;
        reg        bad;
        begin
            case (sel)
                2'd0:    e_data = alu;
                2'd1:    e_data = mem;
                2'd2:    e_data = pc4;
                default: e_data = imm;
            endcase
            e_en = rw & v & (rd != 5'd0);
            ra2  = ~rd;

            @(negedge clk);
            wb_rd_addr       = rd;
            wb_reg_write     = rw;
            wb_valid         = v;
            wb_sel           = sel;
            wb_alu_result    = alu;
            wb_mem_read_data = mem;
            wb_pc_plus4      = pc4;
            wb_immediate     = imm;
            read_addr1       = rd;
            read_addr2       = ra2;
            #2;

            // ---- pre-edge checks (the write must NOT be visible yet) ----
            pre_d1 = read_data1;
            pre_d2 = read_data2;
            pre_e1 = model[rd];
            pre_e2 = model[ra2];
            f_data = (wb_data         !== e_data);
            f_en   = (wb_write_enable !== e_en);
            f_addr = (wb_write_addr   !== rd);
            f_pre1 = (pre_d1 !== pre_e1);
            f_pre2 = (pre_d2 !== pre_e2);

            @(posedge clk);
            #1;
            if (e_en)
                model[rd] = e_data;

            // ---- post-edge checks ----
            f_post1 = (read_data1 !== model[rd]);
            f_post2 = (read_data2 !== model[ra2]);

            // One-edge write: release the write inputs right after the edge
            wb_reg_write = 1'b0;
            wb_valid     = 1'b0;

            bad = f_data | f_en | f_addr | f_pre1 | f_pre2 | f_post1 | f_post2;

            total_tests = total_tests + 1;
            if (bad) begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s | rd=%0d rw=%b v=%b sel=%b",
                         total_tests, name, rd, rw, v, sel);
                if (f_data)
                    $display("       -> wb_data mismatch: actual=%h expected=%h", wb_data, e_data);
                if (f_en)
                    $display("       -> wb_write_enable mismatch: actual=%b expected=%b", wb_write_enable, e_en);
                if (f_addr)
                    $display("       -> wb_write_addr mismatch: actual=%0d expected=%0d", wb_write_addr, rd);
                if (f_pre1)
                    $display("       -> PRE-edge port1 x%0d: actual=%h expected=%h (register changed before the edge, or model out of sync)",
                             rd, pre_d1, pre_e1);
                if (f_pre2)
                    $display("       -> PRE-edge port2 x%0d: actual=%h expected=%h (register changed before the edge, or model out of sync)",
                             ra2, pre_d2, pre_e2);
                if (f_post1)
                    $display("       -> POST-edge port1 x%0d: actual=%h expected=%h", rd, read_data1, model[rd]);
                if (f_post2)
                    $display("       -> POST-edge port2 x%0d: actual=%h expected=%h", ra2, read_data2, model[ra2]);
            end
            else begin
                passed_tests = passed_tests + 1;
                if (verbose)
                    $display("[PASS] #%0d %0s | rd=%0d en=%b data=%h x%0d=%h",
                             total_tests, name, rd, e_en, e_data, rd, read_data1);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: all 32 registers on both read ports against the model (ONE test).
    // Port 1 ascends, port 2 descends.
    //--------------------------------------------------------------------------
    task check_all;
        input [319:0] name;
        integer q;
        integer errs;
        reg [4:0] a1;
        reg [4:0] a2;
        begin
            errs = 0;
            for (q = 0; q < 32; q = q + 1) begin
                a1 = q;
                a2 = 5'd31 - a1;
                read_addr1 = a1;
                read_addr2 = a2;
                #1;
                if (read_data1 !== model[a1]) begin
                    errs = errs + 1;
                    $display("       mismatch port1 x%0d actual=%h expected=%h", a1, read_data1, model[a1]);
                end
                if (read_data2 !== model[a2]) begin
                    errs = errs + 1;
                    $display("       mismatch port2 x%0d actual=%h expected=%h", a2, read_data2, model[a2]);
                end
            end
            total_tests = total_tests + 1;
            if (errs == 0) begin
                passed_tests = passed_tests + 1;
                $display("[PASS] #%0d %0s | all 32 registers, both ports", total_tests, name);
            end
            else begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s | %0d mismatches", total_tests, name, errs);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: asynchronous read check (no clock edge involved)
    //--------------------------------------------------------------------------
    task async_rd;
        input [319:0] name;
        input [4:0]   a1;
        input [4:0]   a2;
        begin
            read_addr1 = a1;
            read_addr2 = a2;
            #1;
            total_tests = total_tests + 1;
            if ((read_data1 !== model[a1]) || (read_data2 !== model[a2])) begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s | p1 x%0d=%h (exp %h) p2 x%0d=%h (exp %h)",
                         total_tests, name, a1, read_data1, model[a1],
                         a2, read_data2, model[a2]);
            end
            else begin
                passed_tests = passed_tests + 1;
                if (verbose)
                    $display("[PASS] #%0d %0s | x%0d=%h x%0d=%h",
                             total_tests, name, a1, read_data1, a2, read_data2);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: reset cycle, with an active write attempt in the same cycle.
    // The model is cleared; reset has priority over the write.
    //--------------------------------------------------------------------------
    task reset_cycle;
        input [4:0]  rd;
        input [31:0] data;
        integer m;
        begin
            @(negedge clk);
            reset            = 1'b1;
            wb_rd_addr       = rd;
            wb_reg_write     = 1'b1;
            wb_valid         = 1'b1;
            wb_sel           = 2'b00;
            wb_alu_result    = data;
            @(posedge clk);
            #1;
            reset            = 1'b0;
            wb_reg_write     = 1'b0;
            wb_valid         = 1'b0;
            for (m = 0; m < 32; m = m + 1)
                model[m] = 32'h00000000;
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
    //   wb_cycle(name, rd, reg_write, valid, sel, alu, mem, pc4, imm)
    //--------------------------------------------------------------------------
    initial begin
        total_tests      = 0;
        passed_tests     = 0;
        failed_tests     = 0;
        verbose          = 1'b1;
        seed             = 32'h5EED1234;
        reset            = 1'b1;
        wb_alu_result    = 32'h0;
        wb_mem_read_data = 32'h0;
        wb_pc_plus4      = 32'h0;
        wb_immediate     = 32'h0;
        wb_rd_addr       = 5'd0;
        wb_reg_write     = 1'b0;
        wb_sel           = 2'b00;
        wb_valid         = 1'b0;
        read_addr1       = 5'd0;
        read_addr2       = 5'd0;
        for (k = 0; k < 32; k = k + 1)
            model[k] = 32'h00000000;

        $display("==============================================================");
        $display(" WB Stage Self-Checking Testbench Started");
        $display("==============================================================");

        // Initial reset, held through the first rising edge (5 ns)
        @(posedge clk);
        #1;
        reset = 1'b0;

        //======================================================================
        // 1. Reset
        //======================================================================
        $display("--- 1. Reset ---");
        check_all("1.1 register file zero after reset");

        //======================================================================
        // 2. All four write-back selections (four distinct source values)
        //======================================================================
        $display("--- 2. Write-back mux ---");
        wb_cycle("2.1 sel 00: ALU result -> x1",     5'd1, 1'b1, 1'b1, 2'b00, 32'hA1A1A1A1, 32'hB2B2B2B2, 32'hC3C3C3C3, 32'hD4D4D4D4);
        wb_cycle("2.2 sel 01: memory data -> x2",    5'd2, 1'b1, 1'b1, 2'b01, 32'hA1A1A1A1, 32'hB2B2B2B2, 32'hC3C3C3C3, 32'hD4D4D4D4);
        wb_cycle("2.3 sel 10: PC+4 -> x3",           5'd3, 1'b1, 1'b1, 2'b10, 32'hA1A1A1A1, 32'hB2B2B2B2, 32'hC3C3C3C3, 32'hD4D4D4D4);
        wb_cycle("2.4 sel 11: immediate -> x4",      5'd4, 1'b1, 1'b1, 2'b11, 32'hA1A1A1A1, 32'hB2B2B2B2, 32'hC3C3C3C3, 32'hD4D4D4D4);
        check_all("2.5 x1..x4 hold the selected values");
        wb_cycle("2.6 sel 00 -> x31",                5'd31, 1'b1, 1'b1, 2'b00, 32'hFFFFFFFF, 32'h0, 32'h0, 32'h0);
        wb_cycle("2.7 sel 01 -> x30",                5'd30, 1'b1, 1'b1, 2'b01, 32'h0, 32'h80000000, 32'h0, 32'h0);
        wb_cycle("2.8 sel 10 -> x29",                5'd29, 1'b1, 1'b1, 2'b10, 32'h0, 32'h0, 32'h7FFFFFFF, 32'h0);
        wb_cycle("2.9 sel 11 -> x28",                5'd28, 1'b1, 1'b1, 2'b11, 32'h0, 32'h0, 32'h0, 32'h12345000);
        check_all("2.10 boundary registers and values");

        //======================================================================
        // 3. Write gating: reg_write and valid
        //======================================================================
        $display("--- 3. Write gating ---");
        wb_cycle("3.1 valid=0, reg_write=1: no write", 5'd5, 1'b1, 1'b0, 2'b00, 32'hBAD00001, 32'h0, 32'h0, 32'h0);
        wb_cycle("3.2 valid=1, reg_write=0: no write", 5'd5, 1'b0, 1'b1, 2'b00, 32'hBAD00002, 32'h0, 32'h0, 32'h0);
        wb_cycle("3.3 valid=0, reg_write=0: no write", 5'd5, 1'b0, 1'b0, 2'b00, 32'hBAD00003, 32'h0, 32'h0, 32'h0);
        wb_cycle("3.4 bubble over written reg x1",     5'd1, 1'b1, 1'b0, 2'b11, 32'h0, 32'h0, 32'h0, 32'hBAD00004);
        wb_cycle("3.5 load bubble (sel 01), valid=0",  5'd2, 1'b1, 1'b0, 2'b01, 32'h0, 32'hBAD00005, 32'h0, 32'h0);
        check_all("3.6 invalid entries changed nothing");
        wb_cycle("3.7 valid=1, reg_write=1: writes",   5'd5, 1'b1, 1'b1, 2'b00, 32'h55555555, 32'h0, 32'h0, 32'h0);
        check_all("3.8 x5 written only by the valid one");

        //======================================================================
        // 4. x0 cannot be modified
        //======================================================================
        $display("--- 4. x0 protection ---");
        wb_cycle("4.1 write x0, sel 00",  5'd0, 1'b1, 1'b1, 2'b00, 32'hFFFFFFFF, 32'h1, 32'h2, 32'h3);
        wb_cycle("4.2 write x0, sel 01",  5'd0, 1'b1, 1'b1, 2'b01, 32'h1, 32'hFFFFFFFF, 32'h2, 32'h3);
        wb_cycle("4.3 write x0, sel 10",  5'd0, 1'b1, 1'b1, 2'b10, 32'h1, 32'h2, 32'hFFFFFFFF, 32'h3);
        wb_cycle("4.4 write x0, sel 11",  5'd0, 1'b1, 1'b1, 2'b11, 32'h1, 32'h2, 32'h3, 32'hFFFFFFFF);
        async_rd("4.5 x0 reads zero on both ports", 5'd0, 5'd0);
        check_all("4.6 x0 attempts disturbed nothing");

        //======================================================================
        // 5. Consecutive writes to different registers (no idle cycles)
        //======================================================================
        $display("--- 5. Consecutive writes ---");
        wb_cycle("5.1 x6",  5'd6,  1'b1, 1'b1, 2'b00, 32'h60606060, 32'h0, 32'h0, 32'h0);
        wb_cycle("5.2 x7",  5'd7,  1'b1, 1'b1, 2'b01, 32'h0, 32'h70707070, 32'h0, 32'h0);
        wb_cycle("5.3 x8",  5'd8,  1'b1, 1'b1, 2'b10, 32'h0, 32'h0, 32'h80808080, 32'h0);
        wb_cycle("5.4 x9",  5'd9,  1'b1, 1'b1, 2'b11, 32'h0, 32'h0, 32'h0, 32'h90909090);
        wb_cycle("5.5 x10", 5'd10, 1'b1, 1'b1, 2'b00, 32'hA0A0A0A0, 32'h0, 32'h0, 32'h0);
        check_all("5.6 five back-to-back writes kept");
        wb_cycle("5.7 overwrite x6", 5'd6, 1'b1, 1'b1, 2'b01, 32'h0, 32'h61616161, 32'h0, 32'h0);
        wb_cycle("5.8 overwrite x6 again", 5'd6, 1'b1, 1'b1, 2'b10, 32'h0, 32'h0, 32'h62626262, 32'h0);
        check_all("5.9 last write to x6 wins");

        //======================================================================
        // 6. Asynchronous read ports (addresses change, no clock edge)
        //    Run just after a rising edge: all steps finish well before the
        //    next one (write inputs are idle, so no write can occur).
        //======================================================================
        $display("--- 6. Asynchronous reads ---");
        @(negedge clk);
        wb_reg_write = 1'b0;
        wb_valid     = 1'b0;
        @(posedge clk);
        #1;
        async_rd("6.1 x6 and x7",             5'd6,  5'd7);
        async_rd("6.2 x8 and x9",             5'd8,  5'd9);
        async_rd("6.3 x31 and x1",            5'd31, 5'd1);
        async_rd("6.4 same register on both", 5'd10, 5'd10);
        async_rd("6.5 x0 and x28",            5'd0,  5'd28);
        async_rd("6.6 x29 and x0",            5'd29, 5'd0);
        read_addr1 = 5'd6;
        #1;
        total_tests = total_tests + 1;
        if (read_data1 !== model[6]) begin
            failed_tests = failed_tests + 1;
            $display("[FAIL] #%0d 6.7 port1 follows its address alone", total_tests);
        end
        else begin
            passed_tests = passed_tests + 1;
            $display("[PASS] #%0d 6.7 port1 follows its address alone | x6=%h", total_tests, read_data1);
        end

        //======================================================================
        // 7. Synchronous write timing
        //    (every wb_cycle already checks "not visible before the edge")
        //======================================================================
        $display("--- 7. Synchronous timing ---");
        // Enable pulse that is gone before the rising edge: no write
        @(negedge clk);
        wb_rd_addr    = 5'd11;
        wb_sel        = 2'b00;
        wb_alu_result = 32'hBAD0BAD0;
        wb_reg_write  = 1'b1;
        wb_valid      = 1'b1;
        read_addr1    = 5'd11;
        #2;
        total_tests = total_tests + 1;
        if (wb_write_enable !== 1'b1 || read_data1 !== model[11]) begin
            failed_tests = failed_tests + 1;
            $display("[FAIL] #%0d 7.1 enable high, no edge: old value", total_tests);
        end
        else begin
            passed_tests = passed_tests + 1;
            $display("[PASS] #%0d 7.1 enable high, no edge: old value | x11=%h", total_tests, read_data1);
        end
        wb_valid = 1'b0;                              // removed before the edge
        @(posedge clk);
        #1;
        total_tests = total_tests + 1;
        if (read_data1 !== model[11]) begin
            failed_tests = failed_tests + 1;
            $display("[FAIL] #%0d 7.2 enable glitch never written | x11=%h", total_tests, read_data1);
        end
        else begin
            passed_tests = passed_tests + 1;
            $display("[PASS] #%0d 7.2 enable glitch never written | x11=%h", total_tests, read_data1);
        end
        wb_reg_write = 1'b0;

        //======================================================================
        // 8. Reset clears the register file; reset beats a write
        //======================================================================
        $display("--- 8. Reset ---");
        reset_cycle(5'd7, 32'hBAD0BAD7);              // write to x7 during reset
        check_all("8.1 reset cleared all, write lost");
        wb_cycle("8.2 write resumes after reset", 5'd7, 1'b1, 1'b1, 2'b00, 32'h77777777, 32'h0, 32'h0, 32'h0);
        wb_cycle("8.3 x12 after reset",           5'd12, 1'b1, 1'b1, 2'b11, 32'h0, 32'h0, 32'h0, 32'hCCCC0012);
        check_all("8.4 registers after resumed writes");

        // Reset asserted mid-cycle must not clear before the edge.
        // (wb_cycle released the write inputs, so no write is pending here.)
        @(negedge clk);
        reset      = 1'b1;
        read_addr1 = 5'd7;
        #2;
        total_tests = total_tests + 1;
        if (read_data1 !== model[7]) begin
            failed_tests = failed_tests + 1;
            $display("[FAIL] #%0d 8.5 reset high, no edge: x7 intact | x7=%h", total_tests, read_data1);
        end
        else begin
            passed_tests = passed_tests + 1;
            $display("[PASS] #%0d 8.5 reset high, no edge: x7 intact | x7=%h", total_tests, read_data1);
        end
        @(posedge clk);
        #1;
        reset = 1'b0;
        for (k = 0; k < 32; k = k + 1)
            model[k] = 32'h00000000;
        check_all("8.6 reset took effect at the edge");

        //======================================================================
        // 9. Write all of x1..x31, then read back
        //======================================================================
        $display("--- 9. Full register sweep ---");
        verbose      = 1'b0;
        fails_before = failed_tests;
        for (k = 1; k < 32; k = k + 1)
            wb_cycle("9.1 write x1..x31", k[4:0], 1'b1, 1'b1, k[1:0],
                     32'hAAAA0000 + k, 32'hBBBB0000 + k,
                     32'hCCCC0000 + k, 32'hDDDD0000 + k);
        sweep_end("9.1 31 consecutive writes", fails_before);
        check_all("9.2 all registers match the model");

        //======================================================================
        // 10. Random cycles against the reference model (800, fixed seed)
        //======================================================================
        $display("--- 10. Random cycles ---");
        fails_before = failed_tests;
        for (k = 0; k < 800; k = k + 1) begin
            r1 = $random(seed);
            r2 = $random(seed);
            r3 = $random(seed);
            r4 = $random(seed);
            r5 = $random(seed);
            wb_cycle("10.1 random write-back cycle",
                     r1[4:0],                 // rd (x0 included)
                     r1[7],                   // reg_write
                     (r1[8] | r1[9]),         // valid (75% set)
                     r1[6:5],                 // sel
                     r2, r3, r4, r5);
        end
        sweep_end("10.1 800 random cycles", fails_before);
        check_all("10.2 registers match after random run");
        verbose = 1'b1;

        //======================================================================
        // Summary
        //======================================================================
        #10;
        $display("==============================================================");
        $display(" WB STAGE VERIFICATION SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");
        if (failed_tests == 0)
            $display("WB STAGE VERIFICATION PASSED");
        else
            $display("WB STAGE VERIFICATION FAILED");
        $finish;
    end

endmodule