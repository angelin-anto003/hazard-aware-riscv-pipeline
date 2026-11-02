
`timescale 1ns / 1ps

//==============================================================================
// Testbench   : tb_alu
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// DUT         : alu
// Description : Self-checking testbench for the 32-bit RV32I ALU
//==============================================================================

module tb_alu;

// ALU control encodings
localparam [3:0] ALU_ADD  = 4'b0000;
localparam [3:0] ALU_SUB  = 4'b0001;
localparam [3:0] ALU_AND  = 4'b0010;
localparam [3:0] ALU_OR   = 4'b0011;
localparam [3:0] ALU_XOR  = 4'b0100;
localparam [3:0] ALU_SLT  = 4'b0101;
localparam [3:0] ALU_SLTU = 4'b0110;
localparam [3:0] ALU_SLL  = 4'b0111;
localparam [3:0] ALU_SRL  = 4'b1000;
localparam [3:0] ALU_SRA  = 4'b1001;

// DUT inputs and outputs
reg  [31:0] a;
reg  [31:0] b;
reg  [3:0]  alu_control;

wire [31:0] result;
wire        zero;

// Test counters
integer total_tests;
integer passed_tests;
integer failed_tests;
integer i;

// DUT instantiation
alu uut (
    .a           (a),
    .b           (b),
    .alu_control (alu_control),
    .result      (result),
    .zero        (zero)
);

// Waveform generation
initial begin
    $dumpfile("simulations/alu.vcd");
    $dumpvars(0, tb_alu);
end

// Reusable self-checking task
task apply_and_check;
    input [319:0] test_name;
    input [31:0] in_a;
    input [31:0] in_b;
    input [3:0]  in_ctrl;
    input [31:0] exp_result;
    input        exp_zero;

    reg result_ok;
    reg zero_ok;

    begin
        a = in_a;
        b = in_b;
        alu_control = in_ctrl;

        // Allow combinational logic to settle
        #10;

        // Case inequality detects X and Z values
        result_ok = !(result !== exp_result);
        zero_ok   = !(zero !== exp_zero);

        total_tests = total_tests + 1;

        if (result_ok && zero_ok) begin
            passed_tests = passed_tests + 1;

            $display(
                "[PASS] %0s | CTRL=%b | A=%h | B=%h | RESULT=%h | ZERO=%b",
                test_name, in_ctrl, in_a, in_b, result, zero
            );
        end
        else begin
            failed_tests = failed_tests + 1;

            $display("[FAIL] %0s", test_name);
            $display("Expected: RESULT=%h ZERO=%b",
                     exp_result, exp_zero);
            $display("Actual  : RESULT=%h ZERO=%b",
                     result, zero);

            if (!result_ok)
                $display("RESULT mismatch");

            if (!zero_ok)
                $display("ZERO flag mismatch");
        end
    end
endtask

// Main test sequence
initial begin

    // Initialize inputs and counters
    a = 32'd0;
    b = 32'd0;
    alu_control = 4'b0000;

    total_tests  = 0;
    passed_tests = 0;
    failed_tests = 0;

    #5;

    $display("================================================");
    $display("     ALU SELF-CHECKING TESTBENCH STARTED");
    $display("================================================");

    //==================================================
    // A. ARITHMETIC OPERATIONS
    //==================================================

    $display("\n--- A. Arithmetic ---");

    apply_and_check("ADD: 10 + 5",
        32'd10, 32'd5, ALU_ADD, 32'd15, 1'b0);

    apply_and_check("ADD: 0 + 0",
        32'd0, 32'd0, ALU_ADD, 32'd0, 1'b1);

    apply_and_check("ADD: Maximum unsigned + 1",
        32'hFFFFFFFF, 32'd1, ALU_ADD, 32'd0, 1'b1);

    apply_and_check("ADD: Signed maximum + 1",
        32'h7FFFFFFF, 32'd1, ALU_ADD, 32'h80000000, 1'b0);

    apply_and_check("SUB: 10 - 5",
        32'd10, 32'd5, ALU_SUB, 32'd5, 1'b0);

    apply_and_check("SUB: 10 - 10",
        32'd10, 32'd10, ALU_SUB, 32'd0, 1'b1);

    apply_and_check("SUB: 0 - 1",
        32'd0, 32'd1, ALU_SUB, 32'hFFFFFFFF, 1'b0);

    apply_and_check("SUB: Signed minimum - 1",
        32'h80000000, 32'd1, ALU_SUB, 32'h7FFFFFFF, 1'b0);


    //==================================================
    // B. LOGICAL OPERATIONS
    //==================================================

    $display("\n--- B. Logical operations ---");

    apply_and_check("AND: 12 & 10",
        32'd12, 32'd10, ALU_AND, 32'd8, 1'b0);

    apply_and_check("OR: 12 | 10",
        32'd12, 32'd10, ALU_OR, 32'd14, 1'b0);

    apply_and_check("XOR: 12 ^ 10",
        32'd12, 32'd10, ALU_XOR, 32'd6, 1'b0);

    apply_and_check("AND: Zero operands",
        32'd0, 32'd0, ALU_AND, 32'd0, 1'b1);

    apply_and_check("OR: Zero operands",
        32'd0, 32'd0, ALU_OR, 32'd0, 1'b1);

    apply_and_check("XOR: Zero operands",
        32'd0, 32'd0, ALU_XOR, 32'd0, 1'b1);

    apply_and_check("AND: All ones",
        32'hFFFFFFFF, 32'hA5A5A5A5,
        ALU_AND, 32'hA5A5A5A5, 1'b0);

    apply_and_check("OR: Complementary patterns",
        32'hF0F0F0F0, 32'h0F0F0F0F,
        ALU_OR, 32'hFFFFFFFF, 1'b0);

    apply_and_check("XOR: Identical operands",
        32'hDEADBEEF, 32'hDEADBEEF,
        ALU_XOR, 32'd0, 1'b1);


    //==================================================
    // C. SIGNED COMPARISONS (SLT)
    //==================================================

    $display("\n--- C. Signed comparisons ---");

    apply_and_check("SLT: -5 < 3",
        -32'sd5, 32'd3, ALU_SLT, 32'd1, 1'b0);

    apply_and_check("SLT: 3 < -5",
        32'd3, -32'sd5, ALU_SLT, 32'd0, 1'b1);

    apply_and_check("SLT: -5 < -3",
        -32'sd5, -32'sd3, ALU_SLT, 32'd1, 1'b0);

    apply_and_check("SLT: 5 < 5",
        32'd5, 32'd5, ALU_SLT, 32'd0, 1'b1);

    apply_and_check("SLT: -3 < -5",
        -32'sd3, -32'sd5, ALU_SLT, 32'd0, 1'b1);

    apply_and_check("SLT: INT_MIN < INT_MAX",
        32'h80000000, 32'h7FFFFFFF,
        ALU_SLT, 32'd1, 1'b0);

    apply_and_check("SLT: INT_MAX < INT_MIN",
        32'h7FFFFFFF, 32'h80000000,
        ALU_SLT, 32'd0, 1'b1);


    //==================================================
    // D. UNSIGNED COMPARISONS (SLTU)
    //==================================================

    $display("\n--- D. Unsigned comparisons ---");

    apply_and_check("SLTU: FFFFFFFF < 1",
        32'hFFFFFFFF, 32'd1, ALU_SLTU, 32'd0, 1'b1);

    apply_and_check("SLTU: 1 < FFFFFFFF",
        32'd1, 32'hFFFFFFFF, ALU_SLTU, 32'd1, 1'b0);

    apply_and_check("SLTU: 5 < 5",
        32'd5, 32'd5, ALU_SLTU, 32'd0, 1'b1);

    apply_and_check("SLTU: 80000000 < 7FFFFFFF",
        32'h80000000, 32'h7FFFFFFF,
        ALU_SLTU, 32'd0, 1'b1);

    apply_and_check("SLTU: 7FFFFFFF < 80000000",
        32'h7FFFFFFF, 32'h80000000,
        ALU_SLTU, 32'd1, 1'b0);


    //==================================================
    // E. SHIFT OPERATIONS
    //==================================================

    $display("\n--- E. Shift operations ---");

    // SLL
    apply_and_check("SLL: 1 << 1",
        32'd1, 32'd1, ALU_SLL, 32'd2, 1'b0);

    apply_and_check("SLL: 1 << 31",
        32'd1, 32'd31, ALU_SLL, 32'h80000000, 1'b0);

    apply_and_check("SLL: Shift by zero",
        32'hA5A5A5A5, 32'd0,
        ALU_SLL, 32'hA5A5A5A5, 1'b0);

    apply_and_check("SLL: Overflow bits",
        32'h80000000, 32'd1, ALU_SLL, 32'd0, 1'b1);

    // SRL
    apply_and_check("SRL: 80000000 >> 1",
        32'h80000000, 32'd1, ALU_SRL, 32'h40000000, 1'b0);

    apply_and_check("SRL: 80000000 >> 31",
        32'h80000000, 32'd31, ALU_SRL, 32'd1, 1'b0);

    apply_and_check("SRL: Shift by zero",
        32'h80000000, 32'd0,
        ALU_SRL, 32'h80000000, 1'b0);

    apply_and_check("SRL: Zero fill",
        32'hFFFFFFFF, 32'd4,
        ALU_SRL, 32'h0FFFFFFF, 1'b0);

    apply_and_check("SRL: Result becomes zero",
        32'd1, 32'd1, ALU_SRL, 32'd0, 1'b1);

    // SRA
    apply_and_check("SRA: 80000000 >>> 1",
        32'h80000000, 32'd1, ALU_SRA, 32'hC0000000, 1'b0);

    apply_and_check("SRA: FFFFFFFF >>> 4",
        32'hFFFFFFFF, 32'd4, ALU_SRA, 32'hFFFFFFFF, 1'b0);

    apply_and_check("SRA: 80000000 >>> 31",
        32'h80000000, 32'd31, ALU_SRA, 32'hFFFFFFFF, 1'b0);

    apply_and_check("SRA: Shift by zero",
        32'h80000000, 32'd0,
        ALU_SRA, 32'h80000000, 1'b0);

    apply_and_check("SRA: Positive operand",
        32'h40000000, 32'd4,
        ALU_SRA, 32'h04000000, 1'b0);

    apply_and_check("SRA: Positive maximum >>> 31",
        32'h7FFFFFFF, 32'd31, ALU_SRA, 32'd0, 1'b1);


    // Shift amount masking
    // Only b[4:0] must be used.

    apply_and_check("SLL: Shift amount 32",
        32'h12345678, 32'd32, ALU_SLL, 32'h12345678, 1'b0);

    apply_and_check("SRL: Shift amount 32",
        32'h80000000, 32'd32, ALU_SRL, 32'h80000000, 1'b0);

    apply_and_check("SRA: Shift amount 32",
        32'h80000000, 32'd32, ALU_SRA, 32'h80000000, 1'b0);

    apply_and_check("SLL: Shift amount 33",
        32'd1, 32'd33, ALU_SLL, 32'd2, 1'b0);

    apply_and_check("SRL: Upper B bits ignored",
        32'h80000000, 32'hFFFFFFE1,
        ALU_SRL, 32'h40000000, 1'b0);

    apply_and_check("SRA: Upper B bits ignored",
        32'h80000000, 32'hABCDEFE1,
        ALU_SRA, 32'hC0000000, 1'b0);


    //==================================================
    // F. ZERO FLAG VERIFICATION
    //==================================================

    $display("\n--- F. Zero flag ---");

    apply_and_check("ZERO: ADD",
        32'd5, 32'hFFFFFFFB, ALU_ADD, 32'd0, 1'b1);

    apply_and_check("ZERO: SUB",
        32'h12345678, 32'h12345678, ALU_SUB, 32'd0, 1'b1);

    apply_and_check("ZERO: SLT",
        32'd7, 32'd2, ALU_SLT, 32'd0, 1'b1);

    apply_and_check("ZERO: SLTU",
        32'd7, 32'd2, ALU_SLTU, 32'd0, 1'b1);

    apply_and_check("ZERO: Invalid control",
        32'hFFFFFFFF, 32'hFFFFFFFF, 4'b1010, 32'd0, 1'b1);

    apply_and_check("NONZERO: ADD",
        32'd1, 32'd1, ALU_ADD, 32'd2, 1'b0);

    apply_and_check("NONZERO: SLT",
        32'd2, 32'd7, ALU_SLT, 32'd1, 1'b0);

    apply_and_check("NONZERO: SLTU",
        32'd2, 32'd7, ALU_SLTU, 32'd1, 1'b0);

    apply_and_check("NONZERO: Bit zero",
        32'd1, 32'd0, ALU_OR, 32'd1, 1'b0);

    apply_and_check("NONZERO: Bit 31",
        32'h80000000, 32'd0, ALU_OR, 32'h80000000, 1'b0);


    //==================================================
    // G. ALL INVALID CONTROL VALUES
    //==================================================

    $display("\n--- G. Invalid control values ---");

    apply_and_check("INVALID: 1010",
        32'hFFFFFFFF, 32'h12345678, 4'b1010, 32'd0, 1'b1);

    apply_and_check("INVALID: 1011",
        32'hFFFFFFFF, 32'h12345678, 4'b1011, 32'd0, 1'b1);

    apply_and_check("INVALID: 1100",
        32'hFFFFFFFF, 32'h12345678, 4'b1100, 32'd0, 1'b1);

    apply_and_check("INVALID: 1101",
        32'hFFFFFFFF, 32'h12345678, 4'b1101, 32'd0, 1'b1);

    apply_and_check("INVALID: 1110",
        32'hFFFFFFFF, 32'h12345678, 4'b1110, 32'd0, 1'b1);

    apply_and_check("INVALID: 1111",
        32'hFFFFFFFF, 32'h12345678, 4'b1111, 32'd0, 1'b1);


    //==================================================
    // H. ALL 16 CONTROL CODE SWEEP
    //==================================================

    $display("\n--- H. Control code sweep ---");

    for (i = 0; i < 16; i = i + 1) begin

        case (i)

            0: apply_and_check("SWEEP: ADD",
                32'hF0F0F0F0, 32'd4, i[3:0],
                32'hF0F0F0F4, 1'b0);

            1: apply_and_check("SWEEP: SUB",
                32'hF0F0F0F0, 32'd4, i[3:0],
                32'hF0F0F0EC, 1'b0);

            2: apply_and_check("SWEEP: AND",
                32'hF0F0F0F0, 32'd4, i[3:0],
                32'h00000000, 1'b1);

            3: apply_and_check("SWEEP: OR",
                32'hF0F0F0F0, 32'd4, i[3:0],
                32'hF0F0F0F4, 1'b0);

            4: apply_and_check("SWEEP: XOR",
                32'hF0F0F0F0, 32'd4, i[3:0],
                32'hF0F0F0F4, 1'b0);

            5: apply_and_check("SWEEP: SLT",
                32'hF0F0F0F0, 32'd4, i[3:0],
                32'd1, 1'b0);

            6: apply_and_check("SWEEP: SLTU",
                32'hF0F0F0F0, 32'd4, i[3:0],
                32'd0, 1'b1);

            7: apply_and_check("SWEEP: SLL",
                32'hF0F0F0F0, 32'd4, i[3:0],
                32'h0F0F0F00, 1'b0);

            8: apply_and_check("SWEEP: SRL",
                32'hF0F0F0F0, 32'd4, i[3:0],
                32'h0F0F0F0F, 1'b0);

            9: apply_and_check("SWEEP: SRA",
                32'hF0F0F0F0, 32'd4, i[3:0],
                32'hFF0F0F0F, 1'b0);

            default: apply_and_check("SWEEP: INVALID",
                32'hF0F0F0F0, 32'd4, i[3:0],
                32'd0, 1'b1);

        endcase
    end


    //==================================================
    // FINAL VERIFICATION SUMMARY
    //==================================================

    #10;

    $display("\n================================================");
    $display("          ALU VERIFICATION SUMMARY");
    $display("================================================");

    $display("Total tests : %0d", total_tests);
    $display("Passed      : %0d", passed_tests);
    $display("Failed      : %0d", failed_tests);

    $display("================================================");

    if (failed_tests == 0)
        $display("ALU VERIFICATION PASSED");
    else
        $display("ALU VERIFICATION FAILED");

    $finish;

end

endmodule
