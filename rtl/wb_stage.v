`timescale 1ns / 1ps

//==============================================================================
// Module      : wb_stage
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : Write Back stage (combinational). Contains the 4-to-1
//               write-back mux and the register-file write-enable logic.
//               The register file itself lives in id_stage; this module only
//               produces the values for its write port.
//
// wb_sel : 00 ALU result   01 memory read data   10 PC+4   11 immediate
//
//   wb_write_enable = wb_reg_write & wb_valid & (wb_rd_addr != x0)
//   wb_write_addr   = wb_rd_addr
//
// Notes:
//   - wb_data is also the forwarding source for the MEM/WB -> EX path and the
//     WB -> ID bypass.
//   - No clock, no reset, no state, no latches.
//==============================================================================

module wb_stage (
    // MEM/WB register outputs
    input  wire [31:0] wb_alu_result,
    input  wire [31:0] wb_mem_read_data,
    input  wire [31:0] wb_pc_plus4,
    input  wire [31:0] wb_immediate,
    input  wire [4:0]  wb_rd_addr,
    input  wire        wb_reg_write,
    input  wire [1:0]  wb_sel,
    input  wire        wb_valid,

    // Register-file write port values (to id_stage) and forwarding value
    output wire [31:0] wb_data,
    output wire        wb_write_enable,
    output wire [4:0]  wb_write_addr
);

    //--------------------------------------------------------------------------
    // 4-to-1 write-back mux
    //--------------------------------------------------------------------------
    reg [31:0] wb_mux;

    always @(*) begin
        case (wb_sel)
            2'b00:   wb_mux = wb_alu_result;
            2'b01:   wb_mux = wb_mem_read_data;
            2'b10:   wb_mux = wb_pc_plus4;
            default: wb_mux = wb_immediate;      // 2'b11
        endcase
    end

    assign wb_data = wb_mux;

    //--------------------------------------------------------------------------
    // Write enable: real instruction, writes a register, destination not x0
    //--------------------------------------------------------------------------
    assign wb_write_enable = wb_reg_write & wb_valid & (wb_rd_addr != 5'd0);

    //--------------------------------------------------------------------------
    // Destination register address
    //--------------------------------------------------------------------------
    assign wb_write_addr = wb_rd_addr;

endmodule