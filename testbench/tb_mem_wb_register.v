`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_mem_wb_register
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// DUT         : mem_wb_register (rtl/mem_wb_register.v)
// Description : Self-checking Verilog-2001 testbench.
//
// Vector layout (108 bits, MSB -> LSB), used for the inputs and for the
// concatenated outputs:
//   [107:76] alu_result   [75:44] mem_read_data   [43:12] pc_plus4
//   [11:7]   ... see below for exact slices:
//   [107:76] alu_result
//   [75:44]  mem_read_data
//   [43:12]  pc_plus4
//   [11:...] immediate is 32 bits, so the real layout is:
//
//   [139:108] is NOT used. Final layout (139 bits would be wrong), exact:
//     alu_result  32 + mem_read_data 32 + pc_plus4 32 + immediate 32
//     + rd_addr 5 + reg_write 1 + wb_sel 2 + valid 1 = 137 bits
//
//   [136:105] alu_result      [104:73] mem_read_data
//   [72:41]   pc_plus4        [40:9]   immediate
//   [8:4]     rd_addr         [3]      reg_write
//   [2:1]     wb_sel          [0]      valid
//
// Timing (race-free):
//   - 10 ns clock, rising edges at 5, 15, 25 ... ns; falling edges at 10, 20 ...
//   - Stimulus changes only at the FALLING edge.
//   - Results are checked 1 ns AFTER a rising edge.
//   - "Before the edge" checks sample 2-3 ns after a falling edge.
//
// Expected values: an accepted capture must equal the vector that was
// presented; reset/flush must give all zeros; hold must equal the previously
// captured vector. The DUT's priority logic is not modelled here.
//
// Run from the repository root (the VCD path is relative).
//==============================================================================

module tb_mem_wb_register;

    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------
    reg          clk;
    reg          reset;
    reg          enable;
    reg          flush;
    reg  [136:0] in_vec;

    wire [31:0]  alu_result_out;
    wire [31:0]  mem_read_data_out;
    wire [31:0]  pc_plus4_out;
    wire [31:0]  immediate_out;
    wire [4:0]   rd_addr_out;
    wire         reg_write_out;
    wire [1:0]   wb_sel_out;
    wire         valid_out;

    // All outputs packed in the same order as the input vector
    wire [136:0] out_vec = {alu_result_out, mem_read_data_out, pc_plus4_out,
                            immediate_out, rd_addr_out, reg_write_out,
                            wb_sel_out, valid_out};

    //--------------------------------------------------------------------------
    // Bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer fails_before;
    integer i;
    integer vv;
    reg     verbose;

    reg [136:0] v;
    reg [136:0] ZERO;
    reg [136:0] ONES;
    reg [136:0] XV;
    reg [136:0] one;
    reg [31:0]  pats [0:5];
    reg [4:0]   t5;
    reg [1:0]   t2;

    //--------------------------------------------------------------------------
    // DUT instantiation (inputs are slices of in_vec)
    //--------------------------------------------------------------------------
    mem_wb_register uut (
        .clk               (clk),
        .reset             (reset),
        .enable            (enable),
        .flush             (flush),

        .alu_result_in     (in_vec[136:105]),
        .mem_read_data_in  (in_vec[104:73]),
        .pc_plus4_in       (in_vec[72:41]),
        .immediate_in      (in_vec[40:9]),

        .rd_addr_in        (in_vec[8:4]),

        .reg_write_in      (in_vec[3]),
        .wb_sel_in         (in_vec[2:1]),

        .valid_in          (in_vec[0]),

        .alu_result_out    (alu_result_out),
        .mem_read_data_out (mem_read_data_out),
        .pc_plus4_out      (pc_plus4_out),
        .immediate_out     (immediate_out),

        .rd_addr_out       (rd_addr_out),

        .reg_write_out     (reg_write_out),
        .wb_sel_out        (wb_sel_out),

        .valid_out         (valid_out)
    );

    //--------------------------------------------------------------------------
    // 10 ns clock (starts low)
    //--------------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    //--------------------------------------------------------------------------
    // Waveform
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("simulations/mem_wb_register.vcd");
        $dumpvars(0, tb_mem_wb_register);
    end

    //--------------------------------------------------------------------------
    // Watchdog
    //--------------------------------------------------------------------------
    initial begin
        #1000000;
        $display("[FAIL] WATCHDOG TIMEOUT: simulation did not finish");
        $display("MEM/WB REGISTER VERIFICATION FAILED");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Function: build a vector from individual fields (layout above)
    //--------------------------------------------------------------------------
    function [136:0] build;
        input [31:0] d_alu;
        input [31:0] d_mem;
        input [31:0] d_pc4;
        input [31:0] d_imm;
        input [4:0]  a_rd;
        input        rw;
        input [1:0]  wbs;
        input        val;
        begin
            build = {d_alu, d_mem, d_pc4, d_imm, a_rd, rw, wbs, val};
        end
    endfunction

    //--------------------------------------------------------------------------
    // Function: fill the whole vector with a 32-bit pattern; the last 9 bits
    // (rd_addr, reg_write, wb_sel) take pattern bits, bit 0 (valid) is set
    // separately.
    //--------------------------------------------------------------------------
    function [136:0] pat;
        input [31:0] p;
        input        val;
        begin
            pat = {{4{p}}, p[8:1], val};
        end
    endfunction

    //--------------------------------------------------------------------------
    // Task: report one field on mismatch (case inequality catches X/Z)
    //--------------------------------------------------------------------------
    task fld;
        input [95:0] n;
        input [31:0] a;
        input [31:0] e;
        begin
            if (a !== e)
                $display("       %0s actual=%h expected=%h", n, a, e);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: compare all 8 outputs against an expected vector
    //--------------------------------------------------------------------------
    task check_out;
        input [319:0] name;
        input [136:0] e;
        begin
            total_tests = total_tests + 1;
            if (out_vec !== e) begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s", total_tests, name);
                fld("alu_result",    out_vec[136:105], e[136:105]);
                fld("mem_read_data", out_vec[104:73],  e[104:73]);
                fld("pc_plus4",      out_vec[72:41],   e[72:41]);
                fld("immediate",     out_vec[40:9],    e[40:9]);
                fld("rd_addr",       out_vec[8:4],     e[8:4]);
                fld("reg_write",     out_vec[3],       e[3]);
                fld("wb_sel",        out_vec[2:1],     e[2:1]);
                fld("valid",         out_vec[0],       e[0]);
            end
            else begin
                passed_tests = passed_tests + 1;
                if (verbose)
                    $display("[PASS] #%0d %0s | alu=%h mem=%h rd=%0d valid=%b",
                             total_tests, name, alu_result_out,
                             mem_read_data_out, rd_addr_out, valid_out);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: one full clock cycle. Inputs are driven at the falling edge,
    // sampled by the DUT at the rising edge; returns 1 ns after that edge.
    //--------------------------------------------------------------------------
    task cycle;
        input         rst;
        input         fl;
        input         en;
        input [136:0] vec;
        begin
            @(negedge clk);
            reset  = rst;
            flush  = fl;
            enable = en;
            in_vec = vec;
            @(posedge clk);
            #1;
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: summary line for sweeps that print no per-test PASS lines
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
        verbose      = 1'b1;
        ZERO         = 137'd0;
        ONES         = {137{1'b1}};
        XV           = {137{1'bx}};
        one          = 137'd1;
        reset        = 1'b0;
        enable       = 1'b0;
        flush        = 1'b0;
        in_vec       = pat(32'hCCCCCCCC, 1'b1);

        pats[0] = 32'h00000000;
        pats[1] = 32'hFFFFFFFF;
        pats[2] = 32'hAAAAAAAA;
        pats[3] = 32'h55555555;
        pats[4] = 32'h80000000;
        pats[5] = 32'h7FFFFFFF;
        #1;

        $display("==============================================================");
        $display(" MEM/WB Register Self-Checking Testbench Started");
        $display("==============================================================");

        //======================================================================
        // 1. Unknown state before reset
        //======================================================================
        $display("--- 1. Unknown state before reset ---");
        check_out("1.1 all outputs unknown at time 0", XV);
        @(posedge clk);
        #1;
        check_out("1.2 hold (en=0) keeps unknown", XV);

        //======================================================================
        // 2. Synchronous reset
        //======================================================================
        $display("--- 2. Synchronous reset ---");
        cycle(1'b1, 1'b0, 1'b0, pat(32'hAAAAAAAA, 1'b1));
        check_out("2.1 reset clears all 8 outputs", ZERO);
        cycle(1'b0, 1'b0, 1'b0, pat(32'h55555555, 1'b1));
        check_out("2.2 hold after reset stays zero", ZERO);

        //======================================================================
        // 3. Capture: one field at a time, then all distinct
        //======================================================================
        $display("--- 3. Data capture ---");
        v = build(32'h11111111, 32'h0, 32'h0, 32'h0, 5'd0, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.1 alu_result only", v);

        v = build(32'h0, 32'h22222222, 32'h0, 32'h0, 5'd0, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.2 mem_read_data only", v);

        v = build(32'h0, 32'h0, 32'h33333333, 32'h0, 5'd0, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.3 pc_plus4 only", v);

        v = build(32'h0, 32'h0, 32'h0, 32'h44444444, 5'd0, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.4 immediate only", v);

        v = build(32'h0, 32'h0, 32'h0, 32'h0, 5'd21, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.5 rd_addr only", v);

        v = build(32'h0, 32'h0, 32'h0, 32'h0, 5'd0, 1'b1, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.6 reg_write only", v);

        v = build(32'h0, 32'h0, 32'h0, 32'h0, 5'd0, 1'b0, 2'b11, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.7 wb_sel only", v);

        v = build(32'h0, 32'h0, 32'h0, 32'h0, 5'd0, 1'b0, 2'd0, 1'b0);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.8 all zero, valid=0", v);

        v = build(32'h0, 32'h0, 32'h0, 32'h0, 5'd0, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.9 valid only", v);

        // Every field distinct, to expose crossed connections
        v = build(32'h11111111, 32'h22222222, 32'h33333333, 32'h44444444,
                  5'd21, 1'b1, 2'b10, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.10 all fields distinct", v);

        v = build(32'hA1A2A3A4, 32'hB1B2B3B4, 32'hC1C2C3C4, 32'hD1D2D3D4,
                  5'd13, 1'b0, 2'b01, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.11 all fields distinct, set 2", v);

        // lw x5: loaded data written back
        v = build(32'h00001008, 32'hCAFEF00D, 32'h00000044, 32'h00000008,
                  5'd5, 1'b1, 2'b01, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.12 representative LW", v);

        // add x7: ALU result written back
        v = build(32'h0000000F, 32'h00000000, 32'h0000004C, 32'h00000000,
                  5'd7, 1'b1, 2'b00, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.13 representative ADD", v);

        // jal x1: PC+4 written back
        v = build(32'h0000005C, 32'h00000000, 32'h00000054, 32'h00000008,
                  5'd1, 1'b1, 2'b10, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.14 representative JAL", v);

        // lui x9: immediate written back
        v = build(32'h12345000, 32'h00000000, 32'h00000058, 32'h12345000,
                  5'd9, 1'b1, 2'b11, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.15 representative LUI", v);

        // sw: no register write
        v = build(32'h00001004, 32'h00000000, 32'h0000005C, 32'h00000004,
                  5'd0, 1'b0, 2'b00, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.16 representative SW (no write)", v);

        //======================================================================
        // 4. Validity: valid_in=0 still captures every other field
        //======================================================================
        $display("--- 4. Validity ---");
        cycle(1'b0, 1'b0, 1'b1, pat(32'h12345678, 1'b1));
        check_out("4.1 valid_in=1 -> valid_out=1", pat(32'h12345678, 1'b1));
        cycle(1'b0, 1'b0, 1'b1, pat(32'h9ABCDEF0, 1'b0));
        check_out("4.2 valid_in=0: bubble, fields kept", pat(32'h9ABCDEF0, 1'b0));
        cycle(1'b0, 1'b0, 1'b1, pat(32'h0F0F0F0F, 1'b1));
        check_out("4.3 valid_in=1 again", pat(32'h0F0F0F0F, 1'b1));
        cycle(1'b0, 1'b0, 1'b1, pat(32'h0F0F0F0F, 1'b0));
        check_out("4.4 only valid_in toggled to 0", pat(32'h0F0F0F0F, 1'b0));
        cycle(1'b0, 1'b0, 1'b1, pat(32'h0F0F0F0F, 1'b1));
        check_out("4.5 only valid_in toggled to 1", pat(32'h0F0F0F0F, 1'b1));
        cycle(1'b0, 1'b0, 1'b1, pat(32'h0F0F0F0F, 1'b0));
        check_out("4.6 only valid_in toggled to 0", pat(32'h0F0F0F0F, 1'b0));

        // Active reg_write and every wb_sel value with valid_in=0
        for (i = 0; i < 4; i = i + 1) begin
            t2 = i;
            v = build(32'h00002000, 32'h5A5A5A5A, 32'h00000100, 32'h00000010,
                      5'd9, 1'b1, t2, 1'b0);
            cycle(1'b0, 1'b0, 1'b1, v);
            check_out("4.7 bubble keeps reg_write/wb_sel", v);
        end

        //======================================================================
        // 5. Hold
        //======================================================================
        $display("--- 5. Hold ---");
        cycle(1'b0, 1'b0, 1'b1, pat(32'hA5A5A5A5, 1'b1));
        check_out("5.1 capture valid instruction", pat(32'hA5A5A5A5, 1'b1));
        cycle(1'b0, 1'b0, 1'b0, pat(32'h5A5A5A5A, 1'b0));
        check_out("5.2 hold, every input changed", pat(32'hA5A5A5A5, 1'b1));
        cycle(1'b0, 1'b0, 1'b0, ONES);
        check_out("5.3 hold, inputs all ones", pat(32'hA5A5A5A5, 1'b1));
        cycle(1'b0, 1'b0, 1'b0, ZERO);
        check_out("5.4 hold, inputs all zero", pat(32'hA5A5A5A5, 1'b1));
        cycle(1'b0, 1'b0, 1'b1, pat(32'h3C3C3C3C, 1'b0));
        check_out("5.5 capture a bubble (valid=0)", pat(32'h3C3C3C3C, 1'b0));
        cycle(1'b0, 1'b0, 1'b0, pat(32'hC3C3C3C3, 1'b1));
        check_out("5.6 hold after bubble, valid_in=1", pat(32'h3C3C3C3C, 1'b0));
        cycle(1'b0, 1'b0, 1'b0, pat(32'hFFFFFFFF, 1'b1));
        check_out("5.7 hold after bubble, again", pat(32'h3C3C3C3C, 1'b0));

        //======================================================================
        // 6. Flush
        //======================================================================
        $display("--- 6. Flush ---");
        cycle(1'b0, 1'b0, 1'b1, pat(32'hDEADBEEF, 1'b1));
        check_out("6.1 capture before flush", pat(32'hDEADBEEF, 1'b1));
        cycle(1'b0, 1'b1, 1'b0, pat(32'h12121212, 1'b1));
        check_out("6.2 flush clears all fields", ZERO);
        cycle(1'b0, 1'b0, 1'b1, pat(32'hCAFEBABE, 1'b1));
        check_out("6.3 capture before flush+enable", pat(32'hCAFEBABE, 1'b1));
        cycle(1'b0, 1'b1, 1'b1, pat(32'h34343434, 1'b1));
        check_out("6.4 flush+enable: flush wins", ZERO);
        cycle(1'b0, 1'b1, 1'b1, ONES);
        check_out("6.5 repeated flush, inputs ones", ZERO);
        cycle(1'b0, 1'b1, 1'b1, pat(32'hAAAAAAAA, 1'b1));
        check_out("6.6 repeated flush again", ZERO);
        cycle(1'b0, 1'b0, 1'b0, pat(32'h55555555, 1'b1));
        check_out("6.7 hold after flush keeps zeros", ZERO);
        cycle(1'b0, 1'b0, 1'b1, pat(32'h87654321, 1'b1));
        check_out("6.8 enable after flush captures", pat(32'h87654321, 1'b1));

        //======================================================================
        // 7. Reset priority and repeated reset
        //======================================================================
        $display("--- 7. Reset priority ---");
        cycle(1'b0, 1'b0, 1'b1, pat(32'h11111111, 1'b1));
        check_out("7.1 capture before reset+enable", pat(32'h11111111, 1'b1));
        cycle(1'b1, 1'b0, 1'b1, pat(32'h22222222, 1'b1));
        check_out("7.2 reset+enable: reset wins", ZERO);
        cycle(1'b0, 1'b0, 1'b1, pat(32'h33333333, 1'b1));
        check_out("7.3 capture before reset+flush", pat(32'h33333333, 1'b1));
        cycle(1'b1, 1'b1, 1'b0, pat(32'h44444444, 1'b1));
        check_out("7.4 reset+flush: cleared", ZERO);
        cycle(1'b0, 1'b0, 1'b1, pat(32'h55555555, 1'b1));
        check_out("7.5 capture before reset+flush+en", pat(32'h55555555, 1'b1));
        cycle(1'b1, 1'b1, 1'b1, pat(32'h66666666, 1'b1));
        check_out("7.6 reset+flush+enable: cleared", ZERO);
        cycle(1'b1, 1'b0, 1'b0, pat(32'h77777777, 1'b1));
        check_out("7.7 repeated reset 1", ZERO);
        cycle(1'b1, 1'b0, 1'b1, pat(32'h88888888, 1'b1));
        check_out("7.8 repeated reset 2 (enable high)", ZERO);
        cycle(1'b1, 1'b1, 1'b1, pat(32'h99999999, 1'b1));
        check_out("7.9 repeated reset 3 (all high)", ZERO);
        cycle(1'b0, 1'b0, 1'b0, pat(32'h77777777, 1'b1));
        check_out("7.10 hold after reset stays zero", ZERO);
        cycle(1'b0, 1'b0, 1'b1, pat(32'h88888888, 1'b1));
        check_out("7.11 capture after reset", pat(32'h88888888, 1'b1));

        //======================================================================
        // 8. Reset and flush after extreme nonzero values
        //======================================================================
        $display("--- 8. Reset/flush after nonzero values ---");
        cycle(1'b0, 1'b0, 1'b1, ONES);
        check_out("8.1 capture all ones", ONES);
        cycle(1'b1, 1'b0, 1'b0, ZERO);
        check_out("8.2 reset clears all ones", ZERO);
        cycle(1'b0, 1'b0, 1'b1, ONES);
        check_out("8.3 capture all ones again", ONES);
        cycle(1'b0, 1'b1, 1'b0, ZERO);
        check_out("8.4 flush clears all ones", ZERO);

        //======================================================================
        // 9. Synchronous behaviour
        //======================================================================
        $display("--- 9. Synchronous behaviour ---");
        v = pat(32'h00000800, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("9.1 baseline capture", v);

        // Inputs change mid-cycle: outputs must not move before the edge
        @(negedge clk);
        enable = 1'b1;
        in_vec = pat(32'h11111111, 1'b1);
        #2;
        check_out("9.2 inputs changed, no edge: old", v);
        in_vec = pat(32'h22222222, 1'b0);
        #1;
        check_out("9.3 inputs changed again: old", v);
        @(posedge clk);
        #1;
        v = pat(32'h22222222, 1'b0);
        check_out("9.4 after the edge: new values", v);

        // Reset pulse that never overlaps a rising edge
        @(negedge clk);
        reset  = 1'b1;
        enable = 1'b0;
        flush  = 1'b0;
        in_vec = pat(32'hF0F0F0F0, 1'b1);
        #2;
        check_out("9.5 reset mid-cycle: no effect", v);
        reset = 1'b0;
        @(posedge clk);
        #1;
        check_out("9.6 reset glitch never seen", v);

        // Reset held through a rising edge
        @(negedge clk);
        reset = 1'b1;
        #2;
        check_out("9.7 reset high before edge: old", v);
        @(posedge clk);
        #1;
        check_out("9.8 reset takes effect at edge", ZERO);
        reset = 1'b0;

        // Flush held through a rising edge
        v = pat(32'h55555555, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("9.9 recapture before flush test", v);
        @(negedge clk);
        flush  = 1'b1;
        enable = 1'b0;
        #2;
        check_out("9.10 flush high before edge: old", v);
        @(posedge clk);
        #1;
        check_out("9.11 flush takes effect at edge", ZERO);
        flush = 1'b0;

        // Flush pulse that never overlaps a rising edge
        v = pat(32'hAAAAAAAA, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("9.12 recapture before flush glitch", v);
        @(negedge clk);
        flush  = 1'b1;
        enable = 1'b0;
        in_vec = pat(32'h77777777, 1'b1);
        #2;
        flush = 1'b0;
        @(posedge clk);
        #1;
        check_out("9.13 flush glitch never seen", v);

        // Enable pulse that never overlaps a rising edge
        @(negedge clk);
        enable = 1'b1;
        in_vec = pat(32'h99999999, 1'b1);
        #2;
        enable = 1'b0;
        @(posedge clk);
        #1;
        check_out("9.14 enable glitch never captured", v);

        //======================================================================
        // 10. Boundary patterns
        //======================================================================
        $display("--- 10. Boundary patterns ---");
        for (i = 0; i < 6; i = i + 1) begin
            for (vv = 0; vv < 2; vv = vv + 1) begin
                cycle(1'b0, 1'b0, 1'b1, pat(pats[i], vv[0]));
                check_out("10.1 pattern capture", pat(pats[i], vv[0]));
            end
        end

        cycle(1'b0, 1'b0, 1'b1, ZERO);
        check_out("10.2 all-zero vector captured", ZERO);
        cycle(1'b0, 1'b0, 1'b1, ONES);
        check_out("10.3 all-one vector captured", ONES);

        v = build(32'hAAAAAAAA, 32'h55555555, 32'hAAAAAAAA, 32'h55555555,
                  5'b10101, 1'b1, 2'b10, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("10.4 alternating bits, set A", v);
        v = build(32'h55555555, 32'hAAAAAAAA, 32'h55555555, 32'hAAAAAAAA,
                  5'b01010, 1'b0, 2'b01, 1'b0);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("10.5 alternating bits, set B", v);

        v = build(32'h80000000, 32'h80000000, 32'h80000000, 32'h80000000,
                  5'd0, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("10.6 MSB set, all data fields", v);
        v = build(32'h7FFFFFFF, 32'h7FFFFFFF, 32'h7FFFFFFF, 32'h7FFFFFFF,
                  5'd0, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("10.7 MSB clear, all data fields", v);

        //======================================================================
        // 11. Destination register addresses 0 and 31
        //======================================================================
        $display("--- 11. rd_addr 0 and 31 ---");
        v = build(32'h0, 32'h0, 32'h0, 32'h0, 5'd0, 1'b1, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("11.1 rd_addr = 0", v);
        v = build(32'h0, 32'h0, 32'h0, 32'h0, 5'd31, 1'b1, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("11.2 rd_addr = 31", v);
        v = build(32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF,
                  5'd31, 1'b1, 2'b11, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("11.3 rd_addr = 31, data all ones", v);
        v = build(32'h0, 32'h0, 32'h0, 32'h0, 5'd0, 1'b0, 2'd0, 1'b0);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("11.4 rd_addr = 0, all zero", v);

        //======================================================================
        // 12. Multi-bit field sweeps: rd_addr (32 values), wb_sel (4 values)
        //======================================================================
        $display("--- 12. Field value sweeps ---");
        verbose      = 1'b0;
        fails_before = failed_tests;
        for (i = 0; i < 32; i = i + 1) begin
            t5 = i;
            v = build(32'h0, 32'h0, 32'h0, 32'h0, t5, 1'b0, 2'd0, 1'b1);
            cycle(1'b0, 1'b0, 1'b1, v);
            check_out("12.1 rd_addr all values", v);
        end
        for (i = 0; i < 4; i = i + 1) begin
            t2 = i;
            v = build(32'h0, 32'h0, 32'h0, 32'h0, 5'd0, 1'b0, t2, 1'b1);
            cycle(1'b0, 1'b0, 1'b1, v);
            check_out("12.2 wb_sel all values", v);
        end
        sweep_end("12.1-2 rd_addr/wb_sel sweeps (36)", fails_before);

        //======================================================================
        // 13. Walking one and walking zero across the whole 137-bit vector
        //======================================================================
        $display("--- 13. Walking one / walking zero ---");
        fails_before = failed_tests;
        for (i = 0; i < 137; i = i + 1) begin
            cycle(1'b0, 1'b0, 1'b1, (one << i));
            check_out("13.1 walking one", (one << i));
        end
        for (i = 0; i < 137; i = i + 1) begin
            cycle(1'b0, 1'b0, 1'b1, ~(one << i));
            check_out("13.2 walking zero", ~(one << i));
        end
        sweep_end("13.1-2 walking one/zero (274)", fails_before);
        verbose = 1'b1;

        //======================================================================
        // Summary
        //======================================================================
        #10;
        $display("==============================================================");
        $display(" MEM/WB REGISTER VERIFICATION SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");

        if (failed_tests == 0)
            $display("MEM/WB REGISTER VERIFICATION PASSED");
        else
            $display("MEM/WB REGISTER VERIFICATION FAILED");

        $finish;
    end

endmodule