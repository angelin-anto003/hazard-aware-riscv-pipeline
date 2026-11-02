
`timescale 1ns / 1ps

//==============================================================================
// Module      : imm_gen
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : RV32I Immediate Generator
//
// Features:
//   - Supports all five standard RV32I immediate formats
//   - I-type: 12-bit signed immediate
//   - S-type: 12-bit signed immediate
//   - B-type: 13-bit signed branch offset
//   - U-type: 20-bit upper immediate
//   - J-type: 21-bit signed jump offset
//   - Combinational operation
//   - Explicit sign extension
//   - No clock, reset, or internal state
//
// Immediate Selector Encoding:
//   000 : I-type
//   001 : S-type
//   010 : B-type
//   011 : U-type
//   100 : J-type
//   Others : Zero output
//
// Notes:
//   - Sign extension uses instruction[31] for I, S, B and J formats.
//   - B-type and J-type offsets have an implicit zero at bit 0.
//   - U-type immediate has twelve trailing zero bits.
//==============================================================================

module imm_gen (
    input  wire [31:0] instruction,
    input  wire [2:0]  imm_sel,
    output reg  [31:0] immediate
);

    //--------------------------------------------------------------------------
    // Combinational Immediate Generation
    //--------------------------------------------------------------------------

    always @(*) begin

        // Default assignment prevents latch inference
        immediate = 32'b0;

        case (imm_sel)

            // I-type: 12-bit immediate, sign-extended to 32 bits
            3'b000: begin
                immediate = {
                    {20{instruction[31]}},
                    instruction[31:20]
                };
            end

            // S-type: 12-bit immediate reconstructed from two instruction fields
            3'b001: begin
                immediate = {
                    {20{instruction[31]}},
                    instruction[31:25],
                    instruction[11:7]
                };
            end

            // B-type: 13-bit branch offset with implicit bit 0
            3'b010: begin
                immediate = {
                    {19{instruction[31]}},
                    instruction[31],
                    instruction[7],
                    instruction[30:25],
                    instruction[11:8],
                    1'b0
                };
            end

            // U-type: Upper 20-bit immediate with twelve trailing zeros
            3'b011: begin
                immediate = {
                    instruction[31:12],
                    12'b0
                };
            end

            // J-type: 21-bit jump offset with implicit bit 0
            3'b100: begin
                immediate = {
                    {11{instruction[31]}},
                    instruction[31],
                    instruction[19:12],
                    instruction[20],
                    instruction[30:21],
                    1'b0
                };
            end

            // Unsupported immediate selection
            default: begin
                immediate = 32'b0;
            end

        endcase

    end

endmodule
