`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_ex_stage
// DUT         : ex_stage (with alu, forwarding_unit, branch_comparator,
//               ex_mem_register)
// Description : Self-checking Verilog-2001 testbench.
//
// Timing (race-free): 10 ns clock, rising edges at 5, 15, 25 ... ns.
//   - Each instruction is applied at a FALLING edge.
//   - Combinational results (redirect, redirect_target) are sampled 2 ns
//     later, 3 ns BEFORE the capturing rising edge.
//   - EX/MEM outputs are checked 1 ns AFTER the rising edge.
//
// How forwarding is observed: the EX/MEM state is created by running a
// "producer" instruction first. A "consumer" ADD then shows its forwarded
// operands in mem_alu_result (= fwd_rs1 + fwd_rs2) and mem_store_data
// (= fwd_rs2). Stale register-file values are S1 / S2, so the sums identify
// exactly which source was selected. All expected values are literals.
//
// Run from the repository root.
//==============================================================================

module tb_ex_stage;

    localparam [3:0] ADD  = 4'b0000;
    localparam [3:0] SUB  = 4'b0001;
    localparam [3:0] AND_ = 4'b0010;
    localparam [3:0] OR_  = 4'b0011;
    localparam [3:0] XOR_ = 4'b0100;
    localparam [3:0] SLT  = 4'b0101;
    localparam [3:0] SLTU = 4'b0110;
    localparam [3:0] SLL  = 4'b0111;

    localparam [2:0] BEQ  = 3'b000;
    localparam [2:0] BNE  = 3'b001;
    localparam [2:0] BLT  = 3'b010;
    localparam [2:0] BGE  = 3'b011;
    localparam [2:0] BLTU = 3'b100;
    localparam [2:0] BGEU = 3'b101;

    localparam [31:0] S1 = 32'h11111111;   // stale register-file value, rs1
    localparam [31:0] S2 = 32'h22222222;   // stale register-file value, rs2

    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------
    reg         clk;
    reg         reset;
    reg  [31:0] id_ex_pc;
    reg  [31:0] id_ex_pc_plus4;
    reg  [31:0] id_ex_rs1_data;
    reg  [31:0] id_ex_rs2_data;
    reg  [31:0] id_ex_immediate;
    reg  [4:0]  id_ex_rs1_addr;
    reg  [4:0]  id_ex_rs2_addr;
    reg  [4:0]  id_ex_rd_addr;
    reg  [1:0]  id_ex_alu_src_a;
    reg         id_ex_alu_src_b;
    reg  [3:0]  id_ex_alu_control;
    reg         id_ex_branch;
    reg  [2:0]  id_ex_branch_type;
    reg         id_ex_jump;
    reg         id_ex_jump_reg;
    reg         id_ex_mem_read;
    reg         id_ex_mem_write;
    reg         id_ex_reg_write;
    reg  [1:0]  id_ex_wb_sel;
    reg         id_ex_valid;
    reg  [4:0]  wb_rd_addr;
    reg         wb_reg_write;
    reg         wb_valid;
    reg  [31:0] wb_data;

    wire        redirect;
    wire [31:0] redirect_target;
    wire [31:0] mem_pc_plus4;
    wire [31:0] mem_alu_result;
    wire [31:0] mem_store_data;
    wire [31:0] mem_immediate;
    wire [4:0]  mem_rd_addr;
    wire        mem_mem_read;
    wire        mem_mem_write;
    wire        mem_reg_write;
    wire [1:0]  mem_wb_sel;
    wire        mem_valid;

    //--------------------------------------------------------------------------
    // Bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    reg         cr;          // redirect sampled before the clock edge
    reg  [31:0] ct;          // redirect_target sampled before the clock edge

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    ex_stage uut (
        .clk               (clk),
        .reset             (reset),
        .id_ex_pc          (id_ex_pc),
        .id_ex_pc_plus4    (id_ex_pc_plus4),
        .id_ex_rs1_data    (id_ex_rs1_data),
        .id_ex_rs2_data    (id_ex_rs2_data),
        .id_ex_immediate   (id_ex_immediate),
        .id_ex_rs1_addr    (id_ex_rs1_addr),
        .id_ex_rs2_addr    (id_ex_rs2_addr),
        .id_ex_rd_addr     (id_ex_rd_addr),
        .id_ex_alu_src_a   (id_ex_alu_src_a),
        .id_ex_alu_src_b   (id_ex_alu_src_b),
        .id_ex_alu_control (id_ex_alu_control),
        .id_ex_branch      (id_ex_branch),
        .id_ex_branch_type (id_ex_branch_type),
        .id_ex_jump        (id_ex_jump),
        .id_ex_jump_reg    (id_ex_jump_reg),
        .id_ex_mem_read    (id_ex_mem_read),
        .id_ex_mem_write   (id_ex_mem_write),
        .id_ex_reg_write   (id_ex_reg_write),
        .id_ex_wb_sel      (id_ex_wb_sel),
        .id_ex_valid       (id_ex_valid),
        .wb_rd_addr        (wb_rd_addr),
        .wb_reg_write      (wb_reg_write),
        .wb_valid          (wb_valid),
        .wb_data           (wb_data),
        .redirect          (redirect),
        .redirect_target   (redirect_target),
        .mem_pc_plus4      (mem_pc_plus4),
        .mem_alu_result    (mem_alu_result),
        .mem_store_data    (mem_store_data),
        .mem_immediate     (mem_immediate),
        .mem_rd_addr       (mem_rd_addr),
        .mem_mem_read      (mem_mem_read),
        .mem_mem_write     (mem_mem_write),
        .mem_reg_write     (mem_reg_write),
        .mem_wb_sel        (mem_wb_sel),
        .mem_valid         (mem_valid)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("simulations/ex_stage.vcd");
        $dumpvars(0, tb_ex_stage);
    end

    // Watchdog
    initial begin
        #200000;
        $display("[FAIL] WATCHDOG TIMEOUT");
        $display("EX STAGE VERIFICATION FAILED");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Core task: apply one ID/EX instruction for one clock cycle.
    //   - inputs change at the falling edge
    //   - redirect / target are sampled 2 ns later (before the rising edge)
    //   - returns 1 ns after the rising edge, EX/MEM has captured
    //--------------------------------------------------------------------------
    task ex_op;
        input [31:0] pc;
        input [31:0] pc4;
        input [31:0] rs1d;
        input [31:0] rs2d;
        input [31:0] imm;
        input [4:0]  rs1a;
        input [4:0]  rs2a;
        input [4:0]  rd;
        input [1:0]  asa;
        input        asb;
        input [3:0]  ctl;
        input        br;
        input [2:0]  bt;
        input        jmp;
        input        jr;
        input        mr;
        input        mw;
        input        rw;
        input [1:0]  wbs;
        input        val;
        begin
            @(negedge clk);
            id_ex_pc          = pc;
            id_ex_pc_plus4    = pc4;
            id_ex_rs1_data    = rs1d;
            id_ex_rs2_data    = rs2d;
            id_ex_immediate   = imm;
            id_ex_rs1_addr    = rs1a;
            id_ex_rs2_addr    = rs2a;
            id_ex_rd_addr     = rd;
            id_ex_alu_src_a   = asa;
            id_ex_alu_src_b   = asb;
            id_ex_alu_control = ctl;
            id_ex_branch      = br;
            id_ex_branch_type = bt;
            id_ex_jump        = jmp;
            id_ex_jump_reg    = jr;
            id_ex_mem_read    = mr;
            id_ex_mem_write   = mw;
            id_ex_reg_write   = rw;
            id_ex_wb_sel      = wbs;
            id_ex_valid       = val;
            #2;
            cr = redirect;
            ct = redirect_target;
            @(posedge clk);
            #1;
        end
    endtask

    // Set the WB forwarding inputs (called at posedge + 1 ns, always safe)
    task set_wb;
        input [4:0]  rd;
        input        rw;
        input        v;
        input [31:0] data;
        begin
            wb_rd_addr   = rd;
            wb_reg_write = rw;
            wb_valid     = v;
            wb_data      = data;
        end
    endtask

    // Idle: invalid bubble, all zero (EX/MEM gets rd=0, valid=0)
    task idle;
        begin
            ex_op(32'h0, 32'h4, 32'h0, 32'h0, 32'h0, 5'd0, 5'd0, 5'd0,
                  2'b00, 1'b0, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
                  1'b0, 1'b0, 1'b0, 2'b00, 1'b0);
        end
    endtask

    // ALU instruction with rs1/rs2 = x1/x2, rd = x3, PC = 0x80
    task alu_op;
        input [31:0] rs1d;
        input [31:0] rs2d;
        input [31:0] imm;
        input [1:0]  asa;
        input        asb;
        input [3:0]  ctl;
        begin
            ex_op(32'h80, 32'h84, rs1d, rs2d, imm, 5'd1, 5'd2, 5'd3,
                  asa, asb, ctl, 1'b0, 3'b000, 1'b0, 1'b0,
                  1'b0, 1'b0, 1'b1, 2'b00, 1'b1);
        end
    endtask

    // Producer: result = value written to rd (ADD value + 0), wb_sel = 00
    task producer_v;
        input [4:0]  rd;
        input [31:0] value;
        input        rw;
        input        v;
        begin
            ex_op(32'h40, 32'h44, value, 32'h0, 32'h0, 5'd0, 5'd0, rd,
                  2'b00, 1'b1, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
                  1'b0, 1'b0, rw, 2'b00, v);
        end
    endtask

    // Load producer: LW rd, 8(0x1000) -> memory read, wb_sel = 01
    task load_prod;
        input [4:0] rd;
        begin
            ex_op(32'h500, 32'h504, 32'h1000, 32'h0, 32'h8, 5'd0, 5'd0, rd,
                  2'b00, 1'b1, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
                  1'b1, 1'b0, 1'b1, 2'b01, 1'b1);
        end
    endtask

    // Consumer: rd = rs1 + rs2 (rd = x9). alu = fwd_rs1 + fwd_rs2, store = fwd_rs2
    task consumer_add;
        input [4:0]  a1;
        input [4:0]  a2;
        input [31:0] d1;
        input [31:0] d2;
        begin
            ex_op(32'h60, 32'h64, d1, d2, 32'h0, a1, a2, 5'd9,
                  2'b00, 1'b0, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
                  1'b0, 1'b0, 1'b1, 2'b00, 1'b1);
        end
    endtask

    // Consumer: rd = rs1 + imm (rd = x9). alu = fwd_rs1 + imm, store = fwd_rs2
    task consumer_addi;
        input [4:0]  a1;
        input [4:0]  a2;
        input [31:0] d1;
        input [31:0] d2;
        input [31:0] imm;
        begin
            ex_op(32'h60, 32'h64, d1, d2, imm, a1, a2, 5'd9,
                  2'b00, 1'b1, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
                  1'b0, 1'b0, 1'b1, 2'b00, 1'b1);
        end
    endtask

    // Store: MEM[rs1 + imm] = rs2. alu = fwd_rs1 + imm, store = fwd_rs2
    task store_op;
        input [4:0]  a1;
        input [4:0]  a2;
        input [31:0] d1;
        input [31:0] d2;
        input [31:0] imm;
        begin
            ex_op(32'h70, 32'h74, d1, d2, imm, a1, a2, 5'd0,
                  2'b00, 1'b1, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
                  1'b0, 1'b1, 1'b0, 2'b00, 1'b1);
        end
    endtask

    // Branch at PC 0x100, offset 0x20 (target 0x120)
    task branch;
        input [2:0]  bt;
        input [4:0]  a1;
        input [4:0]  a2;
        input [31:0] d1;
        input [31:0] d2;
        input        v;
        begin
            ex_op(32'h100, 32'h104, d1, d2, 32'h20, a1, a2, 5'd0,
                  2'b01, 1'b1, ADD, 1'b1, bt, 1'b0, 1'b0,
                  1'b0, 1'b0, 1'b0, 2'b00, v);
        end
    endtask

    // JAL (jr=0: A = PC) or JALR (jr=1: A = rs1). rd = x1, wb_sel = 10.
    task jump;
        input        jr;
        input [4:0]  a1;
        input [31:0] d1;
        input [31:0] imm;
        input [31:0] pc;
        input        v;
        begin
            ex_op(pc, pc + 32'd4, d1, 32'h0, imm, a1, 5'd0, 5'd1,
                  (jr ? 2'b00 : 2'b01), 1'b1, ADD, 1'b0, 3'b000, 1'b1, jr,
                  1'b0, 1'b0, 1'b1, 2'b10, v);
        end
    endtask

    //--------------------------------------------------------------------------
    // Check: redirect, target (only when redirect is expected), ALU result
    // and store data. Call right after the instruction task.
    //--------------------------------------------------------------------------
    task chk;
        input [319:0] name;
        input         e_red;
        input [31:0]  e_tgt;
        input [31:0]  e_alu;
        input [31:0]  e_st;
        reg bad;
        begin
            total_tests = total_tests + 1;
            bad = 1'b0;
            if (cr !== e_red)                bad = 1'b1;
            if (e_red && (ct !== e_tgt))     bad = 1'b1;
            if (mem_alu_result !== e_alu)    bad = 1'b1;
            if (mem_store_data !== e_st)     bad = 1'b1;
            if (bad) begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s", total_tests, name);
                $display("       redirect actual=%b expected=%b", cr, e_red);
                if (e_red)
                    $display("       target   actual=%h expected=%h", ct, e_tgt);
                $display("       alu      actual=%h expected=%h", mem_alu_result, e_alu);
                $display("       store    actual=%h expected=%h", mem_store_data, e_st);
            end
            else begin
                passed_tests = passed_tests + 1;
                $display("[PASS] #%0d %0s | red=%b tgt=%h alu=%h st=%h",
                         total_tests, name, cr, ct, mem_alu_result, mem_store_data);
            end
        end
    endtask

    // Check mem_valid only
    task chk_valid;
        input [319:0] name;
        input         e_val;
        begin
            total_tests = total_tests + 1;
            if (mem_valid !== e_val) begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s | mem_valid actual=%b expected=%b",
                         total_tests, name, mem_valid, e_val);
            end
            else begin
                passed_tests = passed_tests + 1;
                $display("[PASS] #%0d %0s | mem_valid=%b", total_tests, name, mem_valid);
            end
        end
    endtask

    // Check all 10 EX/MEM outputs
    task chk_full;
        input [319:0] name;
        input [31:0]  e_pc4;
        input [31:0]  e_alu;
        input [31:0]  e_st;
        input [31:0]  e_imm;
        input [4:0]   e_rd;
        input         e_mr;
        input         e_mw;
        input         e_rw;
        input [1:0]   e_wbs;
        input         e_val;
        reg bad;
        begin
            total_tests = total_tests + 1;
            bad = 1'b0;
            if (mem_pc_plus4   !== e_pc4) bad = 1'b1;
            if (mem_alu_result !== e_alu) bad = 1'b1;
            if (mem_store_data !== e_st)  bad = 1'b1;
            if (mem_immediate  !== e_imm) bad = 1'b1;
            if (mem_rd_addr    !== e_rd)  bad = 1'b1;
            if (mem_mem_read   !== e_mr)  bad = 1'b1;
            if (mem_mem_write  !== e_mw)  bad = 1'b1;
            if (mem_reg_write  !== e_rw)  bad = 1'b1;
            if (mem_wb_sel     !== e_wbs) bad = 1'b1;
            if (mem_valid      !== e_val) bad = 1'b1;
            if (bad) begin
                failed_tests = failed_tests + 1;
                $display("[FAIL] #%0d %0s", total_tests, name);
                if (mem_pc_plus4   !== e_pc4) $display("       pc_plus4   actual=%h expected=%h", mem_pc_plus4, e_pc4);
                if (mem_alu_result !== e_alu) $display("       alu_result actual=%h expected=%h", mem_alu_result, e_alu);
                if (mem_store_data !== e_st)  $display("       store_data actual=%h expected=%h", mem_store_data, e_st);
                if (mem_immediate  !== e_imm) $display("       immediate  actual=%h expected=%h", mem_immediate, e_imm);
                if (mem_rd_addr    !== e_rd)  $display("       rd_addr    actual=%0d expected=%0d", mem_rd_addr, e_rd);
                if (mem_mem_read   !== e_mr)  $display("       mem_read   actual=%b expected=%b", mem_mem_read, e_mr);
                if (mem_mem_write  !== e_mw)  $display("       mem_write  actual=%b expected=%b", mem_mem_write, e_mw);
                if (mem_reg_write  !== e_rw)  $display("       reg_write  actual=%b expected=%b", mem_reg_write, e_rw);
                if (mem_wb_sel     !== e_wbs) $display("       wb_sel     actual=%b expected=%b", mem_wb_sel, e_wbs);
                if (mem_valid      !== e_val) $display("       valid      actual=%b expected=%b", mem_valid, e_val);
            end
            else begin
                passed_tests = passed_tests + 1;
                $display("[PASS] #%0d %0s | pc4=%h alu=%h st=%h rd=%0d valid=%b",
                         total_tests, name, mem_pc_plus4, mem_alu_result,
                         mem_store_data, mem_rd_addr, mem_valid);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Main stimulus
    //--------------------------------------------------------------------------
    initial begin
        total_tests       = 0;
        passed_tests      = 0;
        failed_tests      = 0;
        cr                = 1'b0;
        ct                = 32'h0;
        reset             = 1'b1;
        id_ex_pc          = 32'h0;
        id_ex_pc_plus4    = 32'h4;
        id_ex_rs1_data    = 32'h0;
        id_ex_rs2_data    = 32'h0;
        id_ex_immediate   = 32'h0;
        id_ex_rs1_addr    = 5'd0;
        id_ex_rs2_addr    = 5'd0;
        id_ex_rd_addr     = 5'd0;
        id_ex_alu_src_a   = 2'b00;
        id_ex_alu_src_b   = 1'b0;
        id_ex_alu_control = ADD;
        id_ex_branch      = 1'b0;
        id_ex_branch_type = BEQ;
        id_ex_jump        = 1'b0;
        id_ex_jump_reg    = 1'b0;
        id_ex_mem_read    = 1'b0;
        id_ex_mem_write   = 1'b0;
        id_ex_reg_write   = 1'b0;
        id_ex_wb_sel      = 2'b00;
        id_ex_valid       = 1'b0;
        set_wb(5'd0, 1'b0, 1'b0, 32'h0);

        $display("==============================================================");
        $display(" EX Stage Self-Checking Testbench Started");
        $display("==============================================================");

        // Initial reset (held through the first rising edge at 5 ns)
        @(posedge clk);
        #1;
        reset = 1'b0;

        //======================================================================
        // 1. Reset
        //======================================================================
        $display("--- 1. Reset ---");
        chk_full("1.1 reset clears EX/MEM", 32'h0, 32'h0, 32'h0, 32'h0,
                 5'd0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0);

        //======================================================================
        // 2. ALU operand selection (no forwarding)
        //======================================================================
        $display("--- 2. ALU operand selection ---");
        alu_op(32'd10, 32'd5, 32'h100, 2'b00, 1'b0, ADD);
        chk("2.1 ADD: A=rs1, B=rs2 (imm ignored)", 1'b0, 32'h0, 32'd15, 32'd5);
        alu_op(32'd10, 32'h99, 32'd7, 2'b00, 1'b1, ADD);
        chk("2.2 ADDI: B=imm, store=rs2", 1'b0, 32'h0, 32'd17, 32'h99);
        alu_op(32'd10, 32'd5, 32'h0, 2'b00, 1'b0, SUB);
        chk("2.3 SUB", 1'b0, 32'h0, 32'd5, 32'd5);
        alu_op(32'hF0F0, 32'h0FF0, 32'h0, 2'b00, 1'b0, AND_);
        chk("2.4 AND", 1'b0, 32'h0, 32'h00F0, 32'h0FF0);
        alu_op(32'hF0F0, 32'h0FF0, 32'h0, 2'b00, 1'b0, OR_);
        chk("2.5 OR", 1'b0, 32'h0, 32'hFFF0, 32'h0FF0);
        alu_op(32'hF0F0, 32'h0FF0, 32'h0, 2'b00, 1'b0, XOR_);
        chk("2.6 XOR", 1'b0, 32'h0, 32'hFF00, 32'h0FF0);
        alu_op(32'hFFFFFFFF, 32'd1, 32'h0, 2'b00, 1'b0, SLT);
        chk("2.7 SLT (-1 < 1)", 1'b0, 32'h0, 32'd1, 32'd1);
        alu_op(32'hFFFFFFFF, 32'd1, 32'h0, 2'b00, 1'b0, SLTU);
        chk("2.8 SLTU (max < 1 false)", 1'b0, 32'h0, 32'd0, 32'd1);
        alu_op(32'd1, 32'd4, 32'h0, 2'b00, 1'b0, SLL);
        chk("2.9 SLL (1 << 4)", 1'b0, 32'h0, 32'h10, 32'd4);
        alu_op(32'hFFFF, 32'h0, 32'h12345000, 2'b10, 1'b1, ADD);
        chk("2.10 LUI: A=0, B=imm", 1'b0, 32'h0, 32'h12345000, 32'h0);
        alu_op(32'hFFFF, 32'h77, 32'h2000, 2'b01, 1'b1, ADD);
        chk("2.11 AUIPC: A=PC(0x80), B=imm", 1'b0, 32'h0, 32'h2080, 32'h77);
        alu_op(32'd5, 32'd7, 32'h0, 2'b11, 1'b0, ADD);
        chk("2.12 alu_src_a=11 defaults to zero", 1'b0, 32'h0, 32'd7, 32'd7);
        ex_op(32'h80, 32'h84, 32'h1000, 32'hDEADBEEF, 32'd8, 5'd1, 5'd2, 5'd0,
              2'b00, 1'b1, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
              1'b0, 1'b1, 1'b0, 2'b00, 1'b1);
        chk("2.13 SW: addr=rs1+imm, store=rs2", 1'b0, 32'h0, 32'h1008, 32'hDEADBEEF);
        ex_op(32'h80, 32'h84, 32'h1000, 32'h12121212, 32'hC, 5'd1, 5'd2, 5'd3,
              2'b00, 1'b1, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
              1'b1, 1'b0, 1'b1, 2'b01, 1'b1);
        chk("2.14 LW: addr=rs1+imm", 1'b0, 32'h0, 32'h100C, 32'h12121212);
        alu_op(32'd5, 32'd5, 32'h0, 2'b00, 1'b0, ADD);
        chk("2.15 equal operands, no branch: none", 1'b0, 32'h0, 32'd10, 32'd5);

        //======================================================================
        // 3. EX/MEM capture
        //======================================================================
        $display("--- 3. EX/MEM capture ---");
        ex_op(32'hA0, 32'hB4, 32'h1000, 32'hCAFEF00D, 32'h24, 5'd1, 5'd2, 5'd21,
              2'b00, 1'b1, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
              1'b0, 1'b1, 1'b0, 2'b00, 1'b1);
        chk_full("3.1 SW-like capture", 32'hB4, 32'h1024, 32'hCAFEF00D, 32'h24,
                 5'd21, 1'b0, 1'b1, 1'b0, 2'b00, 1'b1);
        ex_op(32'hB0, 32'hC8, 32'h2000, 32'h0BADF00D, 32'h30, 5'd1, 5'd2, 5'd30,
              2'b00, 1'b1, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
              1'b1, 1'b0, 1'b1, 2'b01, 1'b1);
        chk_full("3.2 LW-like capture", 32'hC8, 32'h2030, 32'h0BADF00D, 32'h30,
                 5'd30, 1'b1, 1'b0, 1'b1, 2'b01, 1'b1);
        ex_op(32'hC0, 32'hD0, 32'h3000, 32'h1, 32'h4, 5'd1, 5'd2, 5'd31,
              2'b00, 1'b1, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
              1'b1, 1'b1, 1'b1, 2'b11, 1'b0);
        chk_full("3.3 bubble: controls kept, valid=0", 32'hD0, 32'h3004, 32'h1,
                 32'h4, 5'd31, 1'b1, 1'b1, 1'b1, 2'b11, 1'b0);
        ex_op(32'hE0, 32'hFFFFFFFC, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'h80000000,
              5'd1, 5'd2, 5'd31, 2'b00, 1'b1, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
              1'b1, 1'b1, 1'b1, 2'b10, 1'b1);
        chk_full("3.4 extreme values captured", 32'hFFFFFFFC, 32'h7FFFFFFF,
                 32'hFFFFFFFF, 32'h80000000, 5'd31, 1'b1, 1'b1, 1'b1, 2'b10, 1'b1);

        //======================================================================
        // 4. EX/MEM forwarding
        //======================================================================
        $display("--- 4. EX/MEM forwarding ---");
        set_wb(5'd0, 1'b0, 1'b0, 32'h0);
        producer_v(5'd5, 32'h55, 1'b1, 1'b1);
        consumer_add(5'd5, 5'd6, S1, S2);
        chk("4.1 EX/MEM -> A only", 1'b0, 32'h0, 32'h22222277, S2);
        producer_v(5'd5, 32'h55, 1'b1, 1'b1);
        consumer_add(5'd6, 5'd5, S1, S2);
        chk("4.2 EX/MEM -> B only", 1'b0, 32'h0, 32'h11111166, 32'h55);
        producer_v(5'd5, 32'h55, 1'b1, 1'b1);
        consumer_add(5'd5, 5'd5, S1, S2);
        chk("4.3 EX/MEM -> A and B", 1'b0, 32'h0, 32'hAA, 32'h55);
        producer_v(5'd5, 32'h55, 1'b1, 1'b1);
        consumer_add(5'd6, 5'd8, S1, S2);
        chk("4.4 no match: register file values", 1'b0, 32'h0, 32'h33333333, S2);
        producer_v(5'd5, 32'h55, 1'b1, 1'b1);
        ex_op(32'h200, 32'h204, S1, S2, 32'h1000, 5'd5, 5'd6, 5'd9,
              2'b01, 1'b1, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
              1'b0, 1'b0, 1'b1, 2'b00, 1'b1);
        chk("4.5 A=PC ignores forwarded rs1", 1'b0, 32'h0, 32'h1200, S2);
        producer_v(5'd5, 32'h55, 1'b1, 1'b1);
        ex_op(32'h200, 32'h204, S1, S2, 32'h1234, 5'd5, 5'd6, 5'd9,
              2'b10, 1'b1, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
              1'b0, 1'b0, 1'b1, 2'b00, 1'b1);
        chk("4.6 A=zero ignores forwarded rs1", 1'b0, 32'h0, 32'h1234, S2);
        producer_v(5'd5, 32'h55, 1'b1, 1'b1);
        consumer_addi(5'd6, 5'd5, S1, S2, 32'h10);
        chk("4.7 B=imm, rs2 forwarded to store", 1'b0, 32'h0, 32'h11111121, 32'h55);
        producer_v(5'd5, 32'h55, 1'b1, 1'b1);
        consumer_addi(5'd5, 5'd6, S1, S2, 32'h10);
        chk("4.8 A forwarded, B=imm", 1'b0, 32'h0, 32'h65, S2);
        producer_v(5'd5, 32'h55, 1'b1, 1'b1);
        store_op(5'd6, 5'd5, 32'h1000, S2, 32'd8);
        chk("4.9 SW store data from EX/MEM", 1'b0, 32'h0, 32'h1008, 32'h55);
        producer_v(5'd5, 32'h2000, 1'b1, 1'b1);
        store_op(5'd5, 5'd6, 32'h1000, S2, 32'd8);
        chk("4.10 SW base address from EX/MEM", 1'b0, 32'h0, 32'h2008, S2);

        //======================================================================
        // 5. MEM/WB forwarding
        //======================================================================
        $display("--- 5. MEM/WB forwarding ---");
        set_wb(5'd7, 1'b1, 1'b1, 32'h77);
        idle;
        consumer_add(5'd7, 5'd6, S1, S2);
        chk("5.1 MEM/WB -> A only", 1'b0, 32'h0, 32'h22222299, S2);
        consumer_add(5'd6, 5'd7, S1, S2);
        chk("5.2 MEM/WB -> B only", 1'b0, 32'h0, 32'h11111188, 32'h77);
        consumer_add(5'd7, 5'd7, S1, S2);
        chk("5.3 MEM/WB -> A and B", 1'b0, 32'h0, 32'hEE, 32'h77);
        consumer_add(5'd6, 5'd8, S1, S2);
        chk("5.4 no match: register file values", 1'b0, 32'h0, 32'h33333333, S2);
        consumer_addi(5'd7, 5'd6, S1, S2, 32'h10);
        chk("5.5 ADDI: A from MEM/WB", 1'b0, 32'h0, 32'h87, S2);
        store_op(5'd6, 5'd7, 32'h1000, S2, 32'd8);
        chk("5.6 SW store data from MEM/WB", 1'b0, 32'h0, 32'h1008, 32'h77);

        //======================================================================
        // 6. EX/MEM priority over MEM/WB
        //======================================================================
        $display("--- 6. Forwarding priority ---");
        set_wb(5'd5, 1'b1, 1'b1, 32'h77);
        producer_v(5'd5, 32'h55, 1'b1, 1'b1);
        consumer_add(5'd5, 5'd6, S1, S2);
        chk("6.1 both match A: EX/MEM wins", 1'b0, 32'h0, 32'h22222277, S2);
        producer_v(5'd5, 32'h55, 1'b1, 1'b1);
        consumer_add(5'd6, 5'd5, S1, S2);
        chk("6.2 both match B: EX/MEM wins", 1'b0, 32'h0, 32'h11111166, 32'h55);
        producer_v(5'd5, 32'h55, 1'b1, 1'b1);
        consumer_add(5'd5, 5'd5, S1, S2);
        chk("6.3 both match A and B: EX/MEM wins", 1'b0, 32'h0, 32'hAA, 32'h55);
        set_wb(5'd7, 1'b1, 1'b1, 32'h77);
        producer_v(5'd5, 32'h55, 1'b1, 1'b1);
        consumer_add(5'd5, 5'd7, S1, S2);
        chk("6.4 A from EX/MEM, B from MEM/WB", 1'b0, 32'h0, 32'hCC, 32'h77);
        producer_v(5'd5, 32'h55, 1'b1, 1'b1);
        consumer_add(5'd7, 5'd5, S1, S2);
        chk("6.5 A from MEM/WB, B from EX/MEM", 1'b0, 32'h0, 32'hCC, 32'h55);
        set_wb(5'd5, 1'b1, 1'b1, 32'h77);
        producer_v(5'd5, 32'h55, 1'b1, 1'b0);
        consumer_add(5'd5, 5'd6, S1, S2);
        chk("6.6 EX/MEM invalid: falls to MEM/WB", 1'b0, 32'h0, 32'h22222299, S2);
        producer_v(5'd5, 32'h55, 1'b0, 1'b1);
        consumer_add(5'd5, 5'd6, S1, S2);
        chk("6.7 EX/MEM no write: falls to MEM/WB", 1'b0, 32'h0, 32'h22222299, S2);

        //======================================================================
        // 7. JAL / JALR / LUI / AUIPC forwarding values
        //======================================================================
        $display("--- 7. Forward values by wb_sel ---");
        set_wb(5'd0, 1'b0, 1'b0, 32'h0);
        jump(1'b0, 5'd0, 32'h0, 32'h20, 32'h100, 1'b1);
        chk("7.1 JAL producer: redirect, target", 1'b1, 32'h120, 32'h120, 32'h0);
        consumer_addi(5'd1, 5'd6, S1, S2, 32'h0);
        chk("7.2 JAL link (PC+4) -> A", 1'b0, 32'h0, 32'h104, S2);
        jump(1'b0, 5'd0, 32'h0, 32'h20, 32'h100, 1'b1);
        consumer_add(5'd6, 5'd1, S1, S2);
        chk("7.3 JAL link (PC+4) -> B", 1'b0, 32'h0, 32'h11111215, 32'h104);
        jump(1'b1, 5'd0, 32'h2001, 32'h0, 32'h200, 1'b1);
        chk("7.4 JALR producer: bit 0 cleared", 1'b1, 32'h2000, 32'h2001, 32'h0);
        consumer_addi(5'd1, 5'd6, S1, S2, 32'h0);
        chk("7.5 JALR link (PC+4) -> A", 1'b0, 32'h0, 32'h204, S2);
        ex_op(32'h300, 32'h304, 32'hFFFF, 32'h0, 32'h12345000, 5'd0, 5'd0, 5'd2,
              2'b10, 1'b1, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
              1'b0, 1'b0, 1'b1, 2'b11, 1'b1);
        consumer_addi(5'd2, 5'd6, S1, S2, 32'h0);
        chk("7.6 LUI value forwarded", 1'b0, 32'h0, 32'h12345000, S2);
        ex_op(32'h300, 32'h304, 32'hAAAA, 32'h0, 32'h12345000, 5'd0, 5'd0, 5'd2,
              2'b00, 1'b0, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
              1'b0, 1'b0, 1'b1, 2'b11, 1'b1);
        consumer_addi(5'd2, 5'd6, S1, S2, 32'h0);
        chk("7.7 wb_sel=11 uses imm, not ALU", 1'b0, 32'h0, 32'h12345000, S2);
        ex_op(32'h400, 32'h404, 32'h0, 32'h0, 32'h2000, 5'd0, 5'd0, 5'd3,
              2'b01, 1'b1, ADD, 1'b0, 3'b000, 1'b0, 1'b0,
              1'b0, 1'b0, 1'b1, 2'b00, 1'b1);
        consumer_addi(5'd3, 5'd6, S1, S2, 32'h0);
        chk("7.8 AUIPC ALU result forwarded", 1'b0, 32'h0, 32'h2400, S2);

        //======================================================================
        // 8. Load exclusion
        //======================================================================
        $display("--- 8. Load exclusion ---");
        load_prod(5'd5);
        consumer_add(5'd5, 5'd6, S1, S2);
        chk("8.1 EX/MEM load not forwarded to A", 1'b0, 32'h0, 32'h33333333, S2);
        load_prod(5'd5);
        consumer_add(5'd6, 5'd5, S1, S2);
        chk("8.2 EX/MEM load not forwarded to B", 1'b0, 32'h0, 32'h33333333, S2);
        load_prod(5'd5);
        consumer_add(5'd5, 5'd5, S1, S2);
        chk("8.3 EX/MEM load not forwarded to A+B", 1'b0, 32'h0, 32'h33333333, S2);
        load_prod(5'd5);
        store_op(5'd6, 5'd5, 32'h1000, S2, 32'd8);
        chk("8.4 SW store data not from load", 1'b0, 32'h0, 32'h1008, S2);
        set_wb(5'd5, 1'b1, 1'b1, 32'h77);
        load_prod(5'd5);
        consumer_add(5'd5, 5'd6, S1, S2);
        chk("8.5 load + MEM/WB match: A from MEM/WB", 1'b0, 32'h0, 32'h22222299, S2);
        load_prod(5'd5);
        consumer_add(5'd6, 5'd5, S1, S2);
        chk("8.6 load + MEM/WB match: B from MEM/WB", 1'b0, 32'h0, 32'h11111188, 32'h77);
        set_wb(5'd0, 1'b0, 1'b0, 32'h0);

        //======================================================================
        // 9. Invalid and non-writing sources
        //======================================================================
        $display("--- 9. Invalid / non-writing sources ---");
        producer_v(5'd5, 32'h55, 1'b1, 1'b0);
        consumer_add(5'd5, 5'd6, S1, S2);
        chk("9.1 EX/MEM invalid: no forward", 1'b0, 32'h0, 32'h33333333, S2);
        producer_v(5'd5, 32'h55, 1'b0, 1'b1);
        consumer_add(5'd5, 5'd6, S1, S2);
        chk("9.2 EX/MEM reg_write=0: no forward", 1'b0, 32'h0, 32'h33333333, S2);
        producer_v(5'd0, 32'h55, 1'b1, 1'b1);
        consumer_add(5'd0, 5'd0, S1, S2);
        chk("9.3 EX/MEM rd=x0: no forward", 1'b0, 32'h0, 32'h33333333, S2);
        set_wb(5'd7, 1'b1, 1'b0, 32'h77);
        idle;
        consumer_add(5'd7, 5'd6, S1, S2);
        chk("9.4 MEM/WB invalid: no forward", 1'b0, 32'h0, 32'h33333333, S2);
        set_wb(5'd7, 1'b0, 1'b1, 32'h77);
        idle;
        consumer_add(5'd7, 5'd6, S1, S2);
        chk("9.5 MEM/WB reg_write=0: no forward", 1'b0, 32'h0, 32'h33333333, S2);
        set_wb(5'd0, 1'b1, 1'b1, 32'h77);
        idle;
        consumer_add(5'd0, 5'd0, S1, S2);
        chk("9.6 MEM/WB rd=x0: no forward", 1'b0, 32'h0, 32'h33333333, S2);
        set_wb(5'd0, 1'b0, 1'b0, 32'h0);

        //======================================================================
        // 10. Branches (PC 0x100, offset 0x20, target 0x120)
        //======================================================================
        $display("--- 10. Branch conditions ---");
        idle;
        branch(BEQ, 5'd1, 5'd2, 32'd5, 32'd5, 1'b1);
        chk("10.1 BEQ taken (5==5)", 1'b1, 32'h120, 32'h120, 32'd5);
        branch(BEQ, 5'd1, 5'd2, 32'd5, 32'd6, 1'b1);
        chk("10.2 BEQ not taken (5!=6)", 1'b0, 32'h0, 32'h120, 32'd6);
        branch(BNE, 5'd1, 5'd2, 32'd5, 32'd6, 1'b1);
        chk("10.3 BNE taken (5!=6)", 1'b1, 32'h120, 32'h120, 32'd6);
        branch(BNE, 5'd1, 5'd2, 32'd5, 32'd5, 1'b1);
        chk("10.4 BNE not taken (5==5)", 1'b0, 32'h0, 32'h120, 32'd5);
        branch(BLT, 5'd1, 5'd2, 32'hFFFFFFFF, 32'd1, 1'b1);
        chk("10.5 BLT taken (-1<1)", 1'b1, 32'h120, 32'h120, 32'd1);
        branch(BLT, 5'd1, 5'd2, 32'd1, 32'hFFFFFFFF, 1'b1);
        chk("10.6 BLT not taken (1<-1 false)", 1'b0, 32'h0, 32'h120, 32'hFFFFFFFF);
        branch(BLT, 5'd1, 5'd2, 32'd3, 32'd3, 1'b1);
        chk("10.7 BLT not taken (equal)", 1'b0, 32'h0, 32'h120, 32'd3);
        branch(BGE, 5'd1, 5'd2, 32'd1, 32'hFFFFFFFF, 1'b1);
        chk("10.8 BGE taken (1>=-1)", 1'b1, 32'h120, 32'h120, 32'hFFFFFFFF);
        branch(BGE, 5'd1, 5'd2, 32'd3, 32'd3, 1'b1);
        chk("10.9 BGE taken (equal)", 1'b1, 32'h120, 32'h120, 32'd3);
        branch(BGE, 5'd1, 5'd2, 32'hFFFFFFFF, 32'd1, 1'b1);
        chk("10.10 BGE not taken (-1>=1 false)", 1'b0, 32'h0, 32'h120, 32'd1);
        branch(BLTU, 5'd1, 5'd2, 32'd1, 32'hFFFFFFFF, 1'b1);
        chk("10.11 BLTU taken (1<max)", 1'b1, 32'h120, 32'h120, 32'hFFFFFFFF);
        branch(BLTU, 5'd1, 5'd2, 32'hFFFFFFFF, 32'd1, 1'b1);
        chk("10.12 BLTU not taken (max<1 false)", 1'b0, 32'h0, 32'h120, 32'd1);
        branch(BLTU, 5'd1, 5'd2, 32'd3, 32'd3, 1'b1);
        chk("10.13 BLTU not taken (equal)", 1'b0, 32'h0, 32'h120, 32'd3);
        branch(BGEU, 5'd1, 5'd2, 32'hFFFFFFFF, 32'd1, 1'b1);
        chk("10.14 BGEU taken (max>=1)", 1'b1, 32'h120, 32'h120, 32'd1);
        branch(BGEU, 5'd1, 5'd2, 32'd3, 32'd3, 1'b1);
        chk("10.15 BGEU taken (equal)", 1'b1, 32'h120, 32'h120, 32'd3);
        branch(BGEU, 5'd1, 5'd2, 32'd1, 32'hFFFFFFFF, 1'b1);
        chk("10.16 BGEU not taken (1>=max false)", 1'b0, 32'h0, 32'h120, 32'hFFFFFFFF);
        branch(BLT, 5'd1, 5'd2, 32'h80000000, 32'h7FFFFFFF, 1'b1);
        chk("10.17 BLT INT_MIN<INT_MAX: taken", 1'b1, 32'h120, 32'h120, 32'h7FFFFFFF);
        branch(BLTU, 5'd1, 5'd2, 32'h80000000, 32'h7FFFFFFF, 1'b1);
        chk("10.18 BLTU same operands: not taken", 1'b0, 32'h0, 32'h120, 32'h7FFFFFFF);
        branch(3'b110, 5'd1, 5'd2, 32'd5, 32'd5, 1'b1);
        chk("10.19 reserved 110, equal: not taken", 1'b0, 32'h0, 32'h120, 32'd5);
        branch(3'b111, 5'd1, 5'd2, 32'd5, 32'd5, 1'b1);
        chk("10.20 reserved 111, equal: not taken", 1'b0, 32'h0, 32'h120, 32'd5);
        branch(3'b110, 5'd1, 5'd2, 32'd5, 32'd6, 1'b1);
        chk("10.21 reserved 110, different", 1'b0, 32'h0, 32'h120, 32'd6);
        ex_op(32'h100, 32'h104, 32'd5, 32'd5, 32'hFFFFFFF0, 5'd1, 5'd2, 5'd0,
              2'b01, 1'b1, ADD, 1'b1, BEQ, 1'b0, 1'b0,
              1'b0, 1'b0, 1'b0, 2'b00, 1'b1);
        chk("10.22 BEQ negative offset: 0xF0", 1'b1, 32'hF0, 32'hF0, 32'd5);

        //======================================================================
        // 11. Branches with forwarded operands
        //======================================================================
        $display("--- 11. Branch with forwarding ---");
        producer_v(5'd5, 32'h10, 1'b1, 1'b1);
        branch(BEQ, 5'd5, 5'd6, 32'h99, 32'h10, 1'b1);
        chk("11.1 BEQ: rs1 from EX/MEM", 1'b1, 32'h120, 32'h120, 32'h10);
        producer_v(5'd5, 32'h10, 1'b1, 1'b1);
        branch(BEQ, 5'd6, 5'd5, 32'h10, 32'h99, 1'b1);
        chk("11.2 BEQ: rs2 from EX/MEM", 1'b1, 32'h120, 32'h120, 32'h10);
        producer_v(5'd5, 32'h10, 1'b1, 1'b1);
        branch(BNE, 5'd5, 5'd6, 32'h99, 32'h10, 1'b1);
        chk("11.3 BNE: forwarded rs1 equal, no br", 1'b0, 32'h0, 32'h120, 32'h10);
        set_wb(5'd7, 1'b1, 1'b1, 32'h10);
        idle;
        branch(BEQ, 5'd7, 5'd6, 32'h99, 32'h10, 1'b1);
        chk("11.4 BEQ: rs1 from MEM/WB", 1'b1, 32'h120, 32'h120, 32'h10);
        branch(BEQ, 5'd6, 5'd7, 32'h10, 32'h99, 1'b1);
        chk("11.5 BEQ: rs2 from MEM/WB", 1'b1, 32'h120, 32'h120, 32'h10);
        set_wb(5'd7, 1'b1, 1'b1, 32'h1);
        producer_v(5'd5, 32'hFFFFFFFF, 1'b1, 1'b1);
        branch(BLT, 5'd5, 5'd7, 32'h0, 32'h0, 1'b1);
        chk("11.6 BLT: -1 (EX/MEM) < 1 (MEM/WB)", 1'b1, 32'h120, 32'h120, 32'h1);
        producer_v(5'd5, 32'hFFFFFFFF, 1'b1, 1'b1);
        branch(BLTU, 5'd5, 5'd7, 32'h0, 32'h0, 1'b1);
        chk("11.7 BLTU: max (EX/MEM) < 1: no", 1'b0, 32'h0, 32'h120, 32'h1);
        set_wb(5'd5, 1'b1, 1'b1, 32'h77);
        producer_v(5'd5, 32'h10, 1'b1, 1'b1);
        branch(BEQ, 5'd5, 5'd6, 32'h99, 32'h10, 1'b1);
        chk("11.8 EX/MEM beats MEM/WB for compare", 1'b1, 32'h120, 32'h120, 32'h10);
        set_wb(5'd0, 1'b0, 1'b0, 32'h0);

        //======================================================================
        // 12. Jumps
        //======================================================================
        $display("--- 12. JAL / JALR redirects ---");
        idle;
        jump(1'b0, 5'd0, 32'h0, 32'h80, 32'h100, 1'b1);
        chk("12.1 JAL: PC + 0x80", 1'b1, 32'h180, 32'h180, 32'h0);
        jump(1'b0, 5'd0, 32'h0, 32'hFFFFFF00, 32'h1000, 1'b1);
        chk("12.2 JAL negative offset", 1'b1, 32'hF00, 32'hF00, 32'h0);
        jump(1'b0, 5'd0, 32'h0, 32'h21, 32'h100, 1'b1);
        chk("12.3 JAL keeps bit 0 (not masked)", 1'b1, 32'h121, 32'h121, 32'h0);
        jump(1'b1, 5'd0, 32'h2003, 32'h4, 32'h300, 1'b1);
        chk("12.4 JALR 0x2003+4: clear bit 0", 1'b1, 32'h2006, 32'h2007, 32'h0);
        jump(1'b1, 5'd0, 32'h2002, 32'h0, 32'h300, 1'b1);
        chk("12.5 JALR 0x2002: already even", 1'b1, 32'h2002, 32'h2002, 32'h0);
        jump(1'b1, 5'd0, 32'h2001, 32'h0, 32'h300, 1'b1);
        chk("12.6 JALR 0x2001: bit 0 cleared", 1'b1, 32'h2000, 32'h2001, 32'h0);
        jump(1'b1, 5'd0, 32'hFFFFFFFF, 32'h0, 32'h300, 1'b1);
        chk("12.7 JALR 0xFFFFFFFF: 0xFFFFFFFE", 1'b1, 32'hFFFFFFFE, 32'hFFFFFFFF, 32'h0);
        producer_v(5'd5, 32'h3001, 1'b1, 1'b1);
        jump(1'b1, 5'd5, 32'h9999, 32'h0, 32'h300, 1'b1);
        chk("12.8 JALR base from EX/MEM", 1'b1, 32'h3000, 32'h3001, 32'h0);
        set_wb(5'd7, 1'b1, 1'b1, 32'h4005);
        idle;
        jump(1'b1, 5'd7, 32'h9999, 32'h0, 32'h300, 1'b1);
        chk("12.9 JALR base from MEM/WB", 1'b1, 32'h4004, 32'h4005, 32'h0);
        set_wb(5'd0, 1'b0, 1'b0, 32'h0);
        producer_v(5'd5, 32'h3000, 1'b1, 1'b1);
        jump(1'b1, 5'd5, 32'h0, 32'h5, 32'h300, 1'b1);
        chk("12.10 JALR forwarded base + offset", 1'b1, 32'h3004, 32'h3005, 32'h0);

        //======================================================================
        // 13. Invalid instruction: no redirect
        //======================================================================
        $display("--- 13. Invalid redirect suppression ---");
        idle;
        branch(BEQ, 5'd1, 5'd2, 32'd5, 32'd5, 1'b0);
        chk("13.1 taken BEQ, valid=0: no redirect", 1'b0, 32'h0, 32'h120, 32'd5);
        chk_valid("13.1 EX/MEM valid=0", 1'b0);
        branch(BNE, 5'd1, 5'd2, 32'd5, 32'd6, 1'b0);
        chk("13.2 taken BNE, valid=0: no redirect", 1'b0, 32'h0, 32'h120, 32'd6);
        chk_valid("13.2 EX/MEM valid=0", 1'b0);
        jump(1'b0, 5'd0, 32'h0, 32'h80, 32'h100, 1'b0);
        chk("13.3 JAL, valid=0: no redirect", 1'b0, 32'h0, 32'h180, 32'h0);
        chk_valid("13.3 EX/MEM valid=0", 1'b0);
        jump(1'b1, 5'd0, 32'h2001, 32'h0, 32'h300, 1'b0);
        chk("13.4 JALR, valid=0: no redirect", 1'b0, 32'h0, 32'h2001, 32'h0);
        chk_valid("13.4 EX/MEM valid=0", 1'b0);

        //======================================================================
        // 14. Redirecting instruction continues into EX/MEM
        //======================================================================
        $display("--- 14. Redirecting instruction continues ---");
        jump(1'b0, 5'd0, 32'h0, 32'h80, 32'h100, 1'b1);
        chk_full("14.1 JAL reaches EX/MEM", 32'h104, 32'h180, 32'h0, 32'h80,
                 5'd1, 1'b0, 1'b0, 1'b1, 2'b10, 1'b1);
        idle;
        branch(BEQ, 5'd1, 5'd2, 32'd5, 32'd5, 1'b1);
        chk_full("14.2 taken BEQ reaches EX/MEM", 32'h104, 32'h120, 32'd5, 32'h20,
                 5'd0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b1);

        //======================================================================
        // 15. Reset clears EX/MEM and forwarding state
        //======================================================================
        $display("--- 15. Reset ---");
        producer_v(5'd5, 32'h55, 1'b1, 1'b1);
        @(negedge clk);
        reset = 1'b1;
        @(posedge clk);
        #1;
        reset = 1'b0;
        chk_full("15.1 reset clears EX/MEM", 32'h0, 32'h0, 32'h0, 32'h0,
                 5'd0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b0);
        consumer_add(5'd5, 5'd6, S1, S2);
        chk("15.2 no forwarding after reset", 1'b0, 32'h0, 32'h33333333, S2);

        //======================================================================
        // Summary
        //======================================================================
        #10;
        $display("==============================================================");
        $display(" EX STAGE VERIFICATION SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");
        if (failed_tests == 0)
            $display("EX STAGE VERIFICATION PASSED");
        else
            $display("EX STAGE VERIFICATION FAILED");
        $finish;
    end

endmodule