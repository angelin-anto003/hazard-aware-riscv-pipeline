`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_id_stage
// DUT         : id_stage (with control_unit, imm_gen, register_file,
//               id_ex_register)
// Description : Self-checking Verilog-2001 testbench.
//
// Output vector layout (197 bits, MSB -> LSB), same as tb_id_ex_register:
//   [196:165] pc  [164:133] pc_plus4  [132:101] rs1_data  [100:69] rs2_data
//   [68:37] imm   [36:32] rs1_addr    [31:27] rs2_addr    [26:22] rd_addr
//   [21:20] alu_src_a  [19] alu_src_b [18:15] alu_control [14:12] imm_sel
//   [11] branch  [10:8] branch_type   [7] jump [6] jump_reg
//   [5] mem_read [4] mem_write [3] reg_write [2:1] wb_sel [0] valid
//
// Timing (race-free): 10 ns clock, rising edges at 5, 15, 25 ... ns.
// Inputs change at the FALLING edge; results are checked 1 ns after the
// rising edge. A WB write and the ID/EX capture happen at the same edge, so
// the ID/EX value shows what the bypass presented BEFORE the edge.
//
// Expected values: instruction fields, immediates and controls are hand
// worked literals. Register-file contents come from a small testbench model
// (model[]) that is updated only by valid, non-x0 WB writes with literal data.
//
// Run from the repository root.
//==============================================================================

module tb_id_stage;

    localparam [31:0] NOP = 32'h00000013;

    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------
    reg         clk;
    reg         reset;
    reg  [31:0] id_pc;
    reg  [31:0] id_pc_plus4;
    reg  [31:0] id_instruction;
    reg         id_valid;
    reg         redirect;
    reg         id_ex_flush;
    reg         wb_reg_write;
    reg         wb_valid;
    reg  [4:0]  wb_rd_addr;
    reg  [31:0] wb_data;

    wire [31:0] ex_pc;
    wire [31:0] ex_pc_plus4;
    wire [31:0] ex_rs1_data;
    wire [31:0] ex_rs2_data;
    wire [31:0] ex_immediate;
    wire [4:0]  ex_rs1_addr;
    wire [4:0]  ex_rs2_addr;
    wire [4:0]  ex_rd_addr;
    wire [1:0]  ex_alu_src_a;
    wire        ex_alu_src_b;
    wire [3:0]  ex_alu_control;
    wire [2:0]  ex_imm_sel;
    wire        ex_branch;
    wire [2:0]  ex_branch_type;
    wire        ex_jump;
    wire        ex_jump_reg;
    wire        ex_mem_read;
    wire        ex_mem_write;
    wire        ex_reg_write;
    wire [1:0]  ex_wb_sel;
    wire        ex_valid;

    wire [196:0] out_vec = {ex_pc, ex_pc_plus4, ex_rs1_data, ex_rs2_data,
                            ex_immediate, ex_rs1_addr, ex_rs2_addr,
                            ex_rd_addr, ex_alu_src_a, ex_alu_src_b,
                            ex_alu_control, ex_imm_sel, ex_branch,
                            ex_branch_type, ex_jump, ex_jump_reg,
                            ex_mem_read, ex_mem_write, ex_reg_write,
                            ex_wb_sel, ex_valid};

    //--------------------------------------------------------------------------
    // Bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer passed_tests;
    integer failed_tests;
    integer k;
    reg [31:0]  model [0:31];     // expected register-file contents
    reg [196:0] ZERO;

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    id_stage uut (
        .clk            (clk),
        .reset          (reset),
        .id_pc          (id_pc),
        .id_pc_plus4    (id_pc_plus4),
        .id_instruction (id_instruction),
        .id_valid       (id_valid),
        .redirect       (redirect),
        .id_ex_flush    (id_ex_flush),
        .wb_reg_write   (wb_reg_write),
        .wb_valid       (wb_valid),
        .wb_rd_addr     (wb_rd_addr),
        .wb_data        (wb_data),
        .ex_pc          (ex_pc),
        .ex_pc_plus4    (ex_pc_plus4),
        .ex_rs1_data    (ex_rs1_data),
        .ex_rs2_data    (ex_rs2_data),
        .ex_immediate   (ex_immediate),
        .ex_rs1_addr    (ex_rs1_addr),
        .ex_rs2_addr    (ex_rs2_addr),
        .ex_rd_addr     (ex_rd_addr),
        .ex_alu_src_a   (ex_alu_src_a),
        .ex_alu_src_b   (ex_alu_src_b),
        .ex_alu_control (ex_alu_control),
        .ex_imm_sel     (ex_imm_sel),
        .ex_branch      (ex_branch),
        .ex_branch_type (ex_branch_type),
        .ex_jump        (ex_jump),
        .ex_jump_reg    (ex_jump_reg),
        .ex_mem_read    (ex_mem_read),
        .ex_mem_write   (ex_mem_write),
        .ex_reg_write   (ex_reg_write),
        .ex_wb_sel      (ex_wb_sel),
        .ex_valid       (ex_valid)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("simulations/id_stage.vcd");
        $dumpvars(0, tb_id_stage);
    end

    // Watchdog
    initial begin
        #100000;
        $display("[FAIL] WATCHDOG TIMEOUT");
        $display("ID STAGE VERIFICATION FAILED");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Function: build an expected vector from fields (layout above)
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
    // Task: report one mismatching field
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
    // Task: compare all 21 ID/EX outputs against an expected vector
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
                $display("[PASS] #%0d %0s | rs1=%h rs2=%h imm=%h valid=%b",
                         total_tests, name, ex_rs1_data, ex_rs2_data,
                         ex_immediate, ex_valid);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: one clock cycle with every input. Drive at the falling edge,
    // return 1 ns after the rising edge, then update the register model.
    //--------------------------------------------------------------------------
    task step;
        input         rst;
        input  [31:0] inst;
        input  [31:0] pc;
        input         v;
        input         redir;
        input         hzf;
        input         wbrw;
        input         wbv;
        input  [4:0]  wbrd;
        input  [31:0] wbdata;
        begin
            @(negedge clk);
            reset          = rst;
            id_instruction = inst;
            id_pc          = pc;
            id_pc_plus4    = pc + 32'd4;
            id_valid       = v;
            redirect       = redir;
            id_ex_flush    = hzf;
            wb_reg_write   = wbrw;
            wb_valid       = wbv;
            wb_rd_addr     = wbrd;
            wb_data        = wbdata;
            @(posedge clk);
            #1;
            if (rst) begin
                for (k = 0; k < 32; k = k + 1)
                    model[k] = 32'h00000000;
            end
            else if (wbrw && wbv && (wbrd != 5'd0)) begin
                model[wbrd] = wbdata;
            end
        end
    endtask

    // Fetch an instruction with no WB activity and no flush
    task fetch;
        input [31:0] inst;
        input [31:0] pc;
        input        v;
        begin
            step(1'b0, inst, pc, v, 1'b0, 1'b0, 1'b0, 1'b0, 5'd0, 32'h0);
        end
    endtask

    // Write a register through the WB port (instruction is an invalid NOP)
    task wr;
        input [4:0]  rd;
        input [31:0] data;
        begin
            step(1'b0, NOP, 32'h0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, rd, data);
        end
    endtask

    //--------------------------------------------------------------------------
    // Main stimulus
    //   Common control sets used below (as build arguments):
    //     ADD-type : asa=00 asb=0 ctl=0000 imms=000 br=0 bt=000 j=0 jr=0
    //                mr=0 mw=0 rw=1 wb=00
    //--------------------------------------------------------------------------
    initial begin
        total_tests    = 0;
        passed_tests   = 0;
        failed_tests   = 0;
        ZERO           = 197'd0;
        reset          = 1'b0;
        id_pc          = 32'h0;
        id_pc_plus4    = 32'h4;
        id_instruction = NOP;
        id_valid       = 1'b0;
        redirect       = 1'b0;
        id_ex_flush    = 1'b0;
        wb_reg_write   = 1'b0;
        wb_valid       = 1'b0;
        wb_rd_addr     = 5'd0;
        wb_data        = 32'h0;
        for (k = 0; k < 32; k = k + 1)
            model[k] = 32'h00000000;

        $display("==============================================================");
        $display(" ID Stage Self-Checking Testbench Started");
        $display("==============================================================");

        //======================================================================
        // Reset
        //======================================================================
        $display("--- Reset ---");
        step(1'b1, NOP, 32'h0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 5'd0, 32'h0);
        check_out("1 reset clears ID/EX", ZERO);

        fetch(32'h002081B3, 32'h100, 1'b1);       // add x3,x1,x2
        check_out("2 register file cleared by reset",
                  build(32'h100, 32'h104, model[1], model[2], 32'h2,
                        5'd1, 5'd2, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        //======================================================================
        // Populate registers through the WB port
        //======================================================================
        wr(5'd1, 32'h11111111);
        wr(5'd2, 32'h22222222);
        wr(5'd3, 32'h33333333);
        wr(5'd4, 32'h44444444);
        wr(5'd5, 32'h55555555);
        wr(5'd8, 32'h88888888);

        //======================================================================
        // Decoding and register reads (rs fields of I/S/B/U/J formats hold
        // other bits, but the register file still reads them: rs2 of ADDI
        // 8 is x8, etc.)
        //======================================================================
        $display("--- Decoding ---");
        fetch(32'h002081B3, 32'h100, 1'b1);       // add x3,x1,x2   imm field = 2
        check_out("3 ADD",
                  build(32'h100, 32'h104, model[1], model[2], 32'h00000002,
                        5'd1, 5'd2, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        fetch(32'h00810293, 32'h104, 1'b1);       // addi x5,x2,8
        check_out("4 ADDI",
                  build(32'h104, 32'h108, model[2], model[8], 32'h00000008,
                        5'd2, 5'd8, 5'd5, 2'b00, 1'b1, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        fetch(32'h00812283, 32'h108, 1'b1);       // lw x5,8(x2)
        check_out("5 LW",
                  build(32'h108, 32'h10C, model[2], model[8], 32'h00000008,
                        5'd2, 5'd8, 5'd5, 2'b00, 1'b1, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 2'b01, 1'b1));

        fetch(32'h00512423, 32'h10C, 1'b1);       // sw x5,8(x2)
        check_out("6 SW",
                  build(32'h10C, 32'h110, model[2], model[5], 32'h00000008,
                        5'd2, 5'd5, 5'd8, 2'b00, 1'b1, 4'b0000, 3'b001,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 1'b1));

        fetch(32'h00208463, 32'h110, 1'b1);       // beq x1,x2,8
        check_out("7 BEQ",
                  build(32'h110, 32'h114, model[1], model[2], 32'h00000008,
                        5'd1, 5'd2, 5'd8, 2'b01, 1'b1, 4'b0000, 3'b010,
                        1'b1, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b1));

        fetch(32'h123452B7, 32'h114, 1'b1);       // lui x5,0x12345
        check_out("8 LUI",
                  build(32'h114, 32'h118, model[8], model[3], 32'h12345000,
                        5'd8, 5'd3, 5'd5, 2'b10, 1'b1, 4'b0000, 3'b011,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b11, 1'b1));

        fetch(32'h008000EF, 32'h118, 1'b1);       // jal x1,8
        check_out("9 JAL",
                  build(32'h118, 32'h11C, model[0], model[8], 32'h00000008,
                        5'd0, 5'd8, 5'd1, 2'b01, 1'b1, 4'b0000, 3'b100,
                        1'b0, 3'b000, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 2'b10, 1'b1));

        fetch(32'h004100E7, 32'h11C, 1'b1);       // jalr x1,4(x2)
        check_out("10 JALR",
                  build(32'h11C, 32'h120, model[2], model[4], 32'h00000004,
                        5'd2, 5'd4, 5'd1, 2'b00, 1'b1, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 2'b10, 1'b1));

        fetch(32'h00000000, 32'h120, 1'b1);       // illegal: all side effects 0
        check_out("11 illegal word: no side effects",
                  build(32'h120, 32'h124, model[0], model[0], 32'h00000000,
                        5'd0, 5'd0, 5'd0, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 1'b1));

        //======================================================================
        // WB bypass
        //======================================================================
        $display("--- WB bypass ---");
        // add x3,x1,x2 while WB writes x1: rs1 bypassed, rs2 from the file
        step(1'b0, 32'h002081B3, 32'h130, 1'b1, 1'b0, 1'b0,
             1'b1, 1'b1, 5'd1, 32'hAAAA0001);
        check_out("12 bypass rs1 only",
                  build(32'h130, 32'h134, 32'hAAAA0001, model[2], 32'h2,
                        5'd1, 5'd2, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        // WB writes x2: rs2 bypassed, rs1 reads the value written above
        step(1'b0, 32'h002081B3, 32'h134, 1'b1, 1'b0, 1'b0,
             1'b1, 1'b1, 5'd2, 32'hBBBB0002);
        check_out("13 bypass rs2 only",
                  build(32'h134, 32'h138, model[1], 32'hBBBB0002, 32'h2,
                        5'd1, 5'd2, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        // add x3,x5,x5 while WB writes x5: both ports bypassed
        step(1'b0, 32'h005281B3, 32'h138, 1'b1, 1'b0, 1'b0,
             1'b1, 1'b1, 5'd5, 32'hCCCC0005);
        check_out("14 bypass both operands",
                  build(32'h138, 32'h13C, 32'hCCCC0005, 32'hCCCC0005, 32'h5,
                        5'd5, 5'd5, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        // The bypassed writes must also have reached the register file
        fetch(32'h002081B3, 32'h13C, 1'b1);
        check_out("15 register file holds written values",
                  build(32'h13C, 32'h140, model[1], model[2], 32'h2,
                        5'd1, 5'd2, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        // sw x5,8(x2) while WB writes x5: store data (rs2) bypassed
        step(1'b0, 32'h00512423, 32'h140, 1'b1, 1'b0, 1'b0,
             1'b1, 1'b1, 5'd5, 32'hDDDD0005);
        check_out("16 SW store data bypassed",
                  build(32'h140, 32'h144, model[2], 32'hDDDD0005, 32'h8,
                        5'd2, 5'd5, 5'd8, 2'b00, 1'b1, 4'b0000, 3'b001,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00, 1'b1));

        //======================================================================
        // x0 bypass exclusion
        //======================================================================
        $display("--- x0 exclusion ---");
        step(1'b0, 32'h000001B3, 32'h150, 1'b1, 1'b0, 1'b0,   // add x3,x0,x0
             1'b1, 1'b1, 5'd0, 32'hDEAD0000);
        check_out("17 x0 never bypassed (both ports)",
                  build(32'h150, 32'h154, 32'h0, 32'h0, 32'h0,
                        5'd0, 5'd0, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        step(1'b0, 32'h000081B3, 32'h154, 1'b1, 1'b0, 1'b0,   // add x3,x1,x0
             1'b1, 1'b1, 5'd0, 32'hDEAD0000);
        check_out("18 x0 on rs2, real value on rs1",
                  build(32'h154, 32'h158, model[1], 32'h0, 32'h0,
                        5'd1, 5'd0, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        //======================================================================
        // Invalid WB writes
        //======================================================================
        $display("--- Invalid WB write exclusion ---");
        step(1'b0, 32'h002081B3, 32'h160, 1'b1, 1'b0, 1'b0,   // wb_valid = 0
             1'b1, 1'b0, 5'd1, 32'hBAD00001);
        check_out("19 wb_valid=0: no bypass",
                  build(32'h160, 32'h164, model[1], model[2], 32'h2,
                        5'd1, 5'd2, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        step(1'b0, 32'h002081B3, 32'h164, 1'b1, 1'b0, 1'b0,   // reg_write = 0
             1'b0, 1'b1, 5'd2, 32'hBAD00002);
        check_out("20 wb_reg_write=0: no bypass",
                  build(32'h164, 32'h168, model[1], model[2], 32'h2,
                        5'd1, 5'd2, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        step(1'b0, 32'h002081B3, 32'h168, 1'b1, 1'b0, 1'b0,   // valid write, other reg
             1'b1, 1'b1, 5'd7, 32'h77777777);
        check_out("21 address mismatch: no bypass",
                  build(32'h168, 32'h16C, model[1], model[2], 32'h2,
                        5'd1, 5'd2, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        // Invalid writes must not have modified x1/x2
        fetch(32'h002081B3, 32'h16C, 1'b1);
        check_out("22 x1/x2 untouched by invalid writes",
                  build(32'h16C, 32'h170, model[1], model[2], 32'h2,
                        5'd1, 5'd2, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        // The valid write to x7 in test 21 must have landed in the file
        fetch(32'h000381B3, 32'h170, 1'b1);                   // add x3,x7,x0
        check_out("23 x7 written by the valid WB write",
                  build(32'h170, 32'h174, model[7], 32'h0, 32'h0,
                        5'd7, 5'd0, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        //======================================================================
        // Valid propagation
        //======================================================================
        $display("--- Valid propagation ---");
        fetch(32'h002081B3, 32'h180, 1'b0);                   // bubble from IF/ID
        check_out("24 valid_in=0: fields kept, valid=0",
                  build(32'h180, 32'h184, model[1], model[2], 32'h2,
                        5'd1, 5'd2, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b0));
        fetch(32'h002081B3, 32'h184, 1'b1);
        check_out("25 valid_in=1: valid=1",
                  build(32'h184, 32'h188, model[1], model[2], 32'h2,
                        5'd1, 5'd2, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        //======================================================================
        // Flush
        //======================================================================
        $display("--- Flush ---");
        step(1'b0, 32'h002081B3, 32'h190, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 5'd0, 32'h0);
        check_out("26 redirect flushes ID/EX", ZERO);
        step(1'b0, 32'h002081B3, 32'h194, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 5'd0, 32'h0);
        check_out("27 load-use flush clears ID/EX", ZERO);
        step(1'b0, 32'h002081B3, 32'h198, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 5'd0, 32'h0);
        check_out("28 both flush sources", ZERO);

        // A flush must not block the WB write into the register file
        step(1'b0, 32'h002081B3, 32'h19C, 1'b1, 1'b0, 1'b1,
             1'b1, 1'b1, 5'd6, 32'h66666666);
        check_out("29 flush while WB writes x6", ZERO);
        fetch(32'h000301B3, 32'h1A0, 1'b1);                   // add x3,x6,x0
        check_out("30 x6 written during the flush, capture resumes",
                  build(32'h1A0, 32'h1A4, model[6], 32'h0, 32'h0,
                        5'd6, 5'd0, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        //======================================================================
        // Mid-run reset
        //======================================================================
        $display("--- Mid-run reset ---");
        step(1'b1, 32'h002081B3, 32'h1B0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 5'd0, 32'h0);
        check_out("31 mid-run reset clears ID/EX", ZERO);
        fetch(32'h002081B3, 32'h1B4, 1'b1);
        check_out("32 registers cleared by reset",
                  build(32'h1B4, 32'h1B8, model[1], model[2], 32'h2,
                        5'd1, 5'd2, 5'd3, 2'b00, 1'b0, 4'b0000, 3'b000,
                        1'b0, 3'b000, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 1'b1));

        //======================================================================
        // Summary
        //======================================================================
        #10;
        $display("==============================================================");
        $display(" ID STAGE VERIFICATION SUMMARY");
        $display("==============================================================");
        $display(" Total Tests : %0d", total_tests);
        $display(" Passed      : %0d", passed_tests);
        $display(" Failed      : %0d", failed_tests);
        $display("==============================================================");
        if (failed_tests == 0)
            $display("ID STAGE VERIFICATION PASSED");
        else
            $display("ID STAGE VERIFICATION FAILED");
        $finish;
    end

endmodule