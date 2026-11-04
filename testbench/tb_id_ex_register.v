`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_id_ex_register
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// DUT         : id_ex_register (rtl/id_ex_register.v)
// Description : Self-checking Verilog-2001 testbench.
//
// Vector layout (197 bits, MSB -> LSB), used for both the inputs and the
// concatenated outputs:
//   [196:165] pc            [164:133] pc_plus4      [132:101] rs1_data
//   [100:69]  rs2_data      [68:37]   immediate     [36:32]   rs1_addr
//   [31:27]   rs2_addr      [26:22]   rd_addr       [21:20]   alu_src_a
//   [19]      alu_src_b     [18:15]   alu_control    [14:12]  imm_sel
//   [11]      branch        [10:8]    branch_type    [7]      jump
//   [6]       jump_reg      [5]       mem_read       [4]      mem_write
//   [3]       reg_write     [2:1]     wb_sel         [0]      valid
//
// Timing (race-free):
//   - 10 ns clock, rising edges at 5, 15, 25 ... ns, falling edges at 10, 20 ...
//   - Stimulus changes only at the FALLING edge.
//   - Results are checked 1 ns AFTER a rising edge.
//   - "Before the edge" checks sample 2-3 ns after a falling edge.
//
// Expected values: an accepted capture is expected to equal the vector that
// was presented; reset/flush are expected to give all zeros; hold is expected
// to equal the previously captured vector. The DUT's priority logic is not
// modelled in the testbench.
//
// Run from the repository root (the VCD path is relative).
//==============================================================================

module tb_id_ex_register;

    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------
    reg          clk;
    reg          reset;
    reg          enable;
    reg          flush;
    reg  [196:0] in_vec;

    wire [31:0]  pc_out;
    wire [31:0]  pc_plus4_out;
    wire [31:0]  rs1_data_out;
    wire [31:0]  rs2_data_out;
    wire [31:0]  immediate_out;
    wire [4:0]   rs1_addr_out;
    wire [4:0]   rs2_addr_out;
    wire [4:0]   rd_addr_out;
    wire [1:0]   alu_src_a_out;
    wire         alu_src_b_out;
    wire [3:0]   alu_control_out;
    wire [2:0]   imm_sel_out;
    wire         branch_out;
    wire [2:0]   branch_type_out;
    wire         jump_out;
    wire         jump_reg_out;
    wire         mem_read_out;
    wire         mem_write_out;
    wire         reg_write_out;
    wire [1:0]   wb_sel_out;
    wire         valid_out;

    // All outputs packed in the same order as the input vector
    wire [196:0] out_vec = {pc_out, pc_plus4_out, rs1_data_out, rs2_data_out,
                            immediate_out, rs1_addr_out, rs2_addr_out,
                            rd_addr_out, alu_src_a_out, alu_src_b_out,
                            alu_control_out, imm_sel_out, branch_out,
                            branch_type_out, jump_out, jump_reg_out,
                            mem_read_out, mem_write_out, reg_write_out,
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

    reg [196:0] v;
    reg [196:0] v2;
    reg [196:0] ZERO;
    reg [196:0] ONES;
    reg [196:0] XV;
    reg [196:0] one;
    reg [31:0]  pats [0:5];
    reg [3:0]   t4;

    //--------------------------------------------------------------------------
    // DUT instantiation (inputs are slices of in_vec)
    //--------------------------------------------------------------------------
    id_ex_register uut (
        .clk             (clk),
        .reset           (reset),
        .enable          (enable),
        .flush           (flush),

        .pc_in           (in_vec[196:165]),
        .pc_plus4_in     (in_vec[164:133]),
        .rs1_data_in     (in_vec[132:101]),
        .rs2_data_in     (in_vec[100:69]),
        .immediate_in    (in_vec[68:37]),

        .rs1_addr_in     (in_vec[36:32]),
        .rs2_addr_in     (in_vec[31:27]),
        .rd_addr_in      (in_vec[26:22]),

        .alu_src_a_in    (in_vec[21:20]),
        .alu_src_b_in    (in_vec[19]),
        .alu_control_in  (in_vec[18:15]),

        .imm_sel_in      (in_vec[14:12]),

        .branch_in       (in_vec[11]),
        .branch_type_in  (in_vec[10:8]),
        .jump_in         (in_vec[7]),
        .jump_reg_in     (in_vec[6]),

        .mem_read_in     (in_vec[5]),
        .mem_write_in    (in_vec[4]),

        .reg_write_in    (in_vec[3]),
        .wb_sel_in       (in_vec[2:1]),

        .valid_in        (in_vec[0]),

        .pc_out          (pc_out),
        .pc_plus4_out    (pc_plus4_out),
        .rs1_data_out    (rs1_data_out),
        .rs2_data_out    (rs2_data_out),
        .immediate_out   (immediate_out),

        .rs1_addr_out    (rs1_addr_out),
        .rs2_addr_out    (rs2_addr_out),
        .rd_addr_out     (rd_addr_out),

        .alu_src_a_out   (alu_src_a_out),
        .alu_src_b_out   (alu_src_b_out),
        .alu_control_out (alu_control_out),

        .imm_sel_out     (imm_sel_out),

        .branch_out      (branch_out),
        .branch_type_out (branch_type_out),
        .jump_out        (jump_out),
        .jump_reg_out    (jump_reg_out),

        .mem_read_out    (mem_read_out),
        .mem_write_out   (mem_write_out),

        .reg_write_out   (reg_write_out),
        .wb_sel_out      (wb_sel_out),

        .valid_out       (valid_out)
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
        $dumpfile("simulations/id_ex_register.vcd");
        $dumpvars(0, tb_id_ex_register);
    end

    //--------------------------------------------------------------------------
    // Watchdog
    //--------------------------------------------------------------------------
    initial begin
        #1000000;
        $display("[FAIL] WATCHDOG TIMEOUT: simulation did not finish");
        $display("ID/EX REGISTER VERIFICATION FAILED");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Function: build a vector from individual fields (layout above)
    //--------------------------------------------------------------------------
    function [196:0] build;
        input [31:0] d_pc;
        input [31:0] d_pc4;
        input [31:0] d_rs1;
        input [31:0] d_rs2;
        input [31:0] d_imm;
        input [4:0]  a_rs1;
        input [4:0]  a_rs2;
        input [4:0]  a_rd;
        input [1:0]  asa;
        input        asb;
        input [3:0]  actl;
        input [2:0]  imms;
        input        br;
        input [2:0]  brt;
        input        jmp;
        input        jr;
        input        mr;
        input        mw;
        input        rw;
        input [1:0]  wbs;
        input        val;
        begin
            build = {d_pc, d_pc4, d_rs1, d_rs2, d_imm, a_rs1, a_rs2, a_rd,
                     asa, asb, actl, imms, br, brt, jmp, jr, mr, mw, rw,
                     wbs, val};
        end
    endfunction

    //--------------------------------------------------------------------------
    // Function: fill the whole vector with a 32-bit pattern; bit 0 (valid)
    // is set separately.
    //--------------------------------------------------------------------------
    function [196:0] pat;
        input [31:0] p;
        input        val;
        begin
            pat = {{6{p}}, p[4:1], val};
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
    // Task: compare all 21 outputs against an expected vector
    //--------------------------------------------------------------------------
    task check_out;
        input [319:0] name;
        input [196:0] e;
        begin
            total_tests = total_tests + 1;
            if (out_vec !== e) begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s", total_tests, name);
                fld("pc",          out_vec[196:165], e[196:165]);
                fld("pc_plus4",    out_vec[164:133], e[164:133]);
                fld("rs1_data",    out_vec[132:101], e[132:101]);
                fld("rs2_data",    out_vec[100:69],  e[100:69]);
                fld("immediate",   out_vec[68:37],   e[68:37]);
                fld("rs1_addr",    out_vec[36:32],   e[36:32]);
                fld("rs2_addr",    out_vec[31:27],   e[31:27]);
                fld("rd_addr",     out_vec[26:22],   e[26:22]);
                fld("alu_src_a",   out_vec[21:20],   e[21:20]);
                fld("alu_src_b",   out_vec[19],      e[19]);
                fld("alu_control", out_vec[18:15],   e[18:15]);
                fld("imm_sel",     out_vec[14:12],   e[14:12]);
                fld("branch",      out_vec[11],      e[11]);
                fld("branch_type", out_vec[10:8],    e[10:8]);
                fld("jump",        out_vec[7],       e[7]);
                fld("jump_reg",    out_vec[6],       e[6]);
                fld("mem_read",    out_vec[5],       e[5]);
                fld("mem_write",   out_vec[4],       e[4]);
                fld("reg_write",   out_vec[3],       e[3]);
                fld("wb_sel",      out_vec[2:1],     e[2:1]);
                fld("valid",       out_vec[0],       e[0]);
            end
            else begin
                passed_tests = passed_tests + 1;
                if (verbose)
                    $display("[PASS] #%0d %0s | pc=%h rs1=%h imm=%h valid=%b",
                             total_tests, name, pc_out, rs1_data_out,
                             immediate_out, valid_out);
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
        input [196:0] vec;
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
        ZERO         = 197'd0;
        ONES         = {197{1'b1}};
        XV           = {197{1'bx}};
        one          = 197'd1;
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
        $display(" ID/EX Register Self-Checking Testbench Started");
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
        check_out("2.1 reset clears all 21 outputs", ZERO);
        cycle(1'b0, 1'b0, 1'b0, pat(32'h55555555, 1'b1));
        check_out("2.2 hold after reset stays zero", ZERO);

        //======================================================================
        // 3. Capture: field groups, one group at a time
        //======================================================================
        $display("--- 3. Data capture ---");
        v = build(32'h00000100, 32'h00000104, 32'h11111111, 32'h22222222, 32'h33333333,
                  5'd0, 5'd0, 5'd0, 2'd0, 1'b0, 4'd0, 3'd0,
                  1'b0, 3'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.1 data: pc,pc4,rs1,rs2,imm", v);

        v = build(32'h0, 32'h0, 32'h0, 32'h0, 32'h0,
                  5'd17, 5'd9, 5'd30, 2'd0, 1'b0, 4'd0, 3'd0,
                  1'b0, 3'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.2 register addresses", v);

        v = build(32'h0, 32'h0, 32'h0, 32'h0, 32'h0,
                  5'd0, 5'd0, 5'd0, 2'b10, 1'b1, 4'b1001, 3'd0,
                  1'b0, 3'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.3 ALU controls", v);

        v = build(32'h0, 32'h0, 32'h0, 32'h0, 32'h0,
                  5'd0, 5'd0, 5'd0, 2'd0, 1'b0, 4'd0, 3'b100,
                  1'b0, 3'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.4 immediate select", v);

        v = build(32'h0, 32'h0, 32'h0, 32'h0, 32'h0,
                  5'd0, 5'd0, 5'd0, 2'd0, 1'b0, 4'd0, 3'd0,
                  1'b1, 3'b101, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.5 branch and jump controls", v);

        v = build(32'h0, 32'h0, 32'h0, 32'h0, 32'h0,
                  5'd0, 5'd0, 5'd0, 2'd0, 1'b0, 4'd0, 3'd0,
                  1'b0, 3'd0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.6 memory controls", v);

        v = build(32'h0, 32'h0, 32'h0, 32'h0, 32'h0,
                  5'd0, 5'd0, 5'd0, 2'd0, 1'b0, 4'd0, 3'd0,
                  1'b0, 3'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b11, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.7 write-back controls", v);

        // addi x5, x2, 8 as it would leave the decode stage
        v = build(32'h00000040, 32'h00000044, 32'h00000010, 32'h00000000, 32'h00000008,
                  5'd2, 5'd8, 5'd5, 2'b00, 1'b1, 4'b0000, 3'b000,
                  1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.8 representative ADDI", v);

        // bne x1, x2, -8
        v = build(32'h00000080, 32'h00000084, 32'h00000005, 32'h00000006, 32'hFFFFFFF8,
                  5'd1, 5'd2, 5'd0, 2'b01, 1'b1, 4'b0000, 3'b010,
                  1'b1, 3'b001, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("3.9 representative BNE", v);

        //======================================================================
        // 4. Validity behaviour
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
        // 8. Reset after extreme nonzero values
        //======================================================================
        $display("--- 8. Reset after nonzero values ---");
        cycle(1'b0, 1'b0, 1'b1, ONES);
        check_out("8.1 capture all ones", ONES);
        cycle(1'b1, 1'b0, 1'b0, ZERO);
        check_out("8.2 reset clears all ones", ZERO);

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
        // 10. Boundary patterns and control-field sweeps
        //======================================================================
        $display("--- 10. Boundary patterns ---");
        for (i = 0; i < 6; i = i + 1) begin
            for (vv = 0; vv < 2; vv = vv + 1) begin
                cycle(1'b0, 1'b0, 1'b1, pat(pats[i], vv[0]));
                check_out("10.1 pattern capture", pat(pats[i], vv[0]));
            end
        end

        v = build(32'h0, 32'h0, 32'h0, 32'h0, 32'h0,
                  5'd0, 5'd31, 5'd0, 2'd0, 1'b0, 4'd0, 3'd0,
                  1'b0, 3'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("10.2 addresses rs1=0 rs2=31 rd=0", v);
        v = build(32'h0, 32'h0, 32'h0, 32'h0, 32'h0,
                  5'd31, 5'd0, 5'd31, 2'd0, 1'b0, 4'd0, 3'd0,
                  1'b0, 3'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'd0, 1'b1);
        cycle(1'b0, 1'b0, 1'b1, v);
        check_out("10.3 addresses rs1=31 rs2=0 rd=31", v);

        // Every value of each multi-bit control field (others zero)
        verbose      = 1'b0;
        fails_before = failed_tests;
        for (i = 0; i < 4; i = i + 1) begin
            t4 = i;
            v = build(32'h0, 32'h0, 32'h0, 32'h0, 32'h0, 5'd0, 5'd0, 5'd0,
                      t4[1:0], 1'b0, 4'd0, 3'd0,
                      1'b0, 3'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'd0, 1'b1);
            cycle(1'b0, 1'b0, 1'b1, v);
            check_out("10.4 alu_src_a all values", v);
        end
        for (i = 0; i < 16; i = i + 1) begin
            t4 = i;
            v = build(32'h0, 32'h0, 32'h0, 32'h0, 32'h0, 5'd0, 5'd0, 5'd0,
                      2'd0, 1'b0, t4, 3'd0,
                      1'b0, 3'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'd0, 1'b1);
            cycle(1'b0, 1'b0, 1'b1, v);
            check_out("10.5 alu_control all values", v);
        end
        for (i = 0; i < 8; i = i + 1) begin
            t4 = i;
            v = build(32'h0, 32'h0, 32'h0, 32'h0, 32'h0, 5'd0, 5'd0, 5'd0,
                      2'd0, 1'b0, 4'd0, t4[2:0],
                      1'b0, 3'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'd0, 1'b1);
            cycle(1'b0, 1'b0, 1'b1, v);
            check_out("10.6 imm_sel all values", v);
        end
        for (i = 0; i < 8; i = i + 1) begin
            t4 = i;
            v = build(32'h0, 32'h0, 32'h0, 32'h0, 32'h0, 5'd0, 5'd0, 5'd0,
                      2'd0, 1'b0, 4'd0, 3'd0,
                      1'b0, t4[2:0], 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'd0, 1'b1);
            cycle(1'b0, 1'b0, 1'b1, v);
            check_out("10.7 branch_type all values", v);
        end
        for (i = 0; i < 4; i = i + 1) begin
            t4 = i;
            v = build(32'h0, 32'h0, 32'h0, 32'h0, 32'h0, 5'd0, 5'd0, 5'd0,
                      2'd0, 1'b0, 4'd0, 3'd0,
                      1'b0, 3'd0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, t4[1:0], 1'b1);
            cycle(1'b0, 1'b0, 1'b1, v);
            check_out("10.8 wb_sel all values", v);
        end
        sweep_end("10.4-8 control-field value sweeps (40)", fails_before);

        // Walking one and walking zero across every bit of every field
        fails_before = failed_tests;
        for (i = 0; i < 197; i = i + 1) begin
            cycle(1'b0, 1'b0, 1'b1, (one << i));
            check_out("10.9 walking one", (one << i));
        end
        for (i = 0; i < 197; i = i + 1) begin
            cycle(1'b0, 1'b0, 1'b1, ~(one << i));
            check_out("10.10 walking zero", ~(one << i));
        end
        sweep_end("10.9-10 walking one/zero (394)", fails_before);
        verbose = 1'b1;

        //======================================================================
        // Summary
        //======================================================================
        #10;
        $display("==============================================================");
        $display(" ID/EX REGISTER VERIFICATION SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");

        if (failed_tests == 0)
            $display("ID/EX REGISTER VERIFICATION PASSED");
        else
            $display("ID/EX REGISTER VERIFICATION FAILED");

        $finish;
    end

endmodule