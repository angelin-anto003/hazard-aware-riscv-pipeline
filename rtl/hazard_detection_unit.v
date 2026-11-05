`timescale 1ns / 1ps

//==============================================================================
// Module      : hazard_detection_unit
// Project     : Hazard-Aware RISC-V Pipeline with Branch Prediction
// Description : Combinational load-use hazard detector.
//
// A load-use hazard exists when the instruction in EX is a load whose
// destination is a source of the instruction in ID. The loaded data is not
// available until the end of MEM, so the dependent instruction must wait
// one cycle. The unit stalls IF and ID and inserts a bubble into EX:
//
//   hazard    : pc_write = 0, if_id_write = 0, id_ex_flush = 1
//   no hazard : pc_write = 1, if_id_write = 1, id_ex_flush = 0
//
// Hazard condition:
//   id_ex_mem_read && (id_ex_rd_addr != x0) &&
//   ((id_ex_rd_addr == if_id_rs1_addr) || (id_ex_rd_addr == if_id_rs2_addr))
//
// Notes:
//   - x0 never causes a stall.
//   - Integration: pc_write drives the PC enable, if_id_write drives the
//     IF/ID enable, id_ex_flush drives the ID/EX flush. The ID/EX register
//     gives flush priority over enable, so flush may be asserted while its
//     enable is high.
//   - This unit does not look at the valid bit of the ID instruction. A
//     bubble in ID is a NOP (rs1 = rs2 = x0) and cannot match a nonzero rd.
//     A real instruction that does not use rs1/rs2 (LUI, JAL) can still
//     match by bit pattern and cause one unnecessary stall; this is safe.
//   - No clock, no reset, no state, no latches.
//==============================================================================

module hazard_detection_unit (
    // Instruction in EX (from ID/EX register)
    input  wire       id_ex_mem_read,
    input  wire [4:0] id_ex_rd_addr,

    // Instruction in ID (from IF/ID instruction fields)
    input  wire [4:0] if_id_rs1_addr,
    input  wire [4:0] if_id_rs2_addr,

    // Stall controls
    output wire       pc_write,
    output wire       if_id_write,
    output wire       id_ex_flush
);

    // Load-use hazard detection (rs1 and rs2 compared independently)
    wire load_use_hazard = id_ex_mem_read
                         & (id_ex_rd_addr != 5'd0)
                         & ((id_ex_rd_addr == if_id_rs1_addr) |
                            (id_ex_rd_addr == if_id_rs2_addr));

    assign pc_write    = ~load_use_hazard;   // freeze PC on hazard
    assign if_id_write = ~load_use_hazard;   // freeze IF/ID on hazard
    assign id_ex_flush =  load_use_hazard;   // bubble into EX on hazard

endmodule