`timescale 1ns / 1ps

//==============================================================================
// Module      : branch_comparator
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : Combinational RV32I branch condition evaluator (EX stage).
//               Compares two operands according to branch_type (encodings
//               fixed by control_unit.v) and reports whether the branch is
//               taken. No clock, no reset, no state.
//
// branch_type encodings:
//   3'b000 : BEQ   taken if rs1 == rs2
//   3'b001 : BNE   taken if rs1 != rs2
//   3'b010 : BLT   taken if signed(rs1)   <  signed(rs2)
//   3'b011 : BGE   taken if signed(rs1)   >= signed(rs2)
//   3'b100 : BLTU  taken if unsigned(rs1) <  unsigned(rs2)
//   3'b101 : BGEU  taken if unsigned(rs1) >= unsigned(rs2)
//   3'b110 : reserved -> branch_taken = 0
//   3'b111 : reserved -> branch_taken = 0
//
// Integration note:
//   branch_taken is only meaningful for branch instructions. The pipeline
//   must qualify it with the control unit's 'branch' signal, e.g.
//   take_branch = branch & branch_taken.
//==============================================================================

module branch_comparator (
    input  wire [31:0] rs1_data,      // Operand 1 (forwarded rs1 value)
    input  wire [31:0] rs2_data,      // Operand 2 (forwarded rs2 value)
    input  wire [2:0]  branch_type,   // Branch condition selector
    output reg         branch_taken   // 1 when the condition is true
);

    always @(*) begin
        // Safe default: no branch. Guarantees an assignment on every path.
        branch_taken = 1'b0;

        case (branch_type)
            3'b000:  branch_taken = (rs1_data == rs2_data);                   // BEQ
            3'b001:  branch_taken = (rs1_data != rs2_data);                   // BNE
            3'b010:  branch_taken = ($signed(rs1_data) <  $signed(rs2_data)); // BLT  (signed)
            3'b011:  branch_taken = ($signed(rs1_data) >= $signed(rs2_data)); // BGE  (signed)
            3'b100:  branch_taken = (rs1_data <  rs2_data);                   // BLTU (unsigned)
            3'b101:  branch_taken = (rs1_data >= rs2_data);                   // BGEU (unsigned)
            default: branch_taken = 1'b0;                                     // 110, 111 reserved
        endcase
    end

endmodule