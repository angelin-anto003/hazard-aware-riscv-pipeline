# Hazard-Aware RISC-V Pipeline with Branch Prediction

A five-stage, 32-bit RISC-V processor implemented in Verilog, featuring data forwarding, load-use hazard detection, branch handling, and pipeline control.

## Overview

This project implements a pipelined processor based on the RV32I instruction format. The design focuses on understanding and implementing fundamental processor architecture concepts, including instruction execution, pipeline registers, data hazards, control hazards, and forwarding mechanisms.

The processor uses a five-stage pipeline:

1. **Instruction Fetch (IF)** – Fetches instructions using the program counter.
2. **Instruction Decode (ID)** – Decodes instructions, generates control signals, and reads register operands.
3. **Execute (EX)** – Performs ALU operations, evaluates branches, and calculates jump targets.
4. **Memory Access (MEM)** – Handles data memory reads and writes.
5. **Write Back (WB)** – Writes execution results back to the register file.
## Architecture

The processor follows a five-stage pipeline architecture:

```text
       ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐
       │   IF   │───▶│   ID   │───▶│   EX   │───▶│  MEM   │───▶│   WB   │
       │ Fetch  │    │ Decode │    │Execute │    │ Memory │    │Writeback│
       └────────┘    └────────┘    └────────┘    └────────┘    └────────┘
            │             │             │
            └─────────────┴─────────────┘
                  Hazard Control
```

**Pipeline registers:** IF/ID, ID/EX, EX/MEM, and MEM/WB separate the five stages.

**Hazard management:** Forwarding handles data dependencies, while hazard detection inserts stalls for load-use dependencies. Branch and jump redirects flush younger instructions when necessary.

## Key Features

- Five-stage RV32I pipeline.
- 32-bit datapath and 32 general-purpose registers.
- Register x0 hardwired to zero.
- Separate instruction and data memories.
- Data forwarding from EX/MEM and MEM/WB stages.
- Load-use hazard detection with pipeline stalling.
- Static not-taken branch prediction.
- Branch and jump resolution in the EX stage.
- Pipeline flushing and misprediction recovery.
- JAL and JALR support, including link-address writeback.
- Valid-bit-based control of pipeline side effects.
- Modular RTL design with separate pipeline stages and functional units.

## Supported Instructions

| Category | Instructions |
|---|---|
| Arithmetic | ADD, SUB, ADDI |
| Logical | AND, OR, XOR, ANDI, ORI, XORI |
| Comparison | SLT, SLTU |
| Upper immediate | LUI, AUIPC |
| Memory | LW, SW |
| Conditional branches | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Jumps | JAL, JALR |

**Note:** This project implements a tested subset of RV32I, not the complete RV32I instruction set. Some instructions and extensions remain unimplemented.

## Hazard Handling

### Data Hazards
The forwarding unit resolves common RAW (Read After Write) data dependencies by forwarding results from later pipeline stages to the EX stage.

### Load-Use Hazards
When an instruction immediately depends on a preceding load instruction, the hazard detection unit:
- Holds the program counter.
- Holds the IF/ID pipeline register.
- Inserts a bubble into the ID/EX pipeline register.

### Control Hazards
The processor uses static not-taken branch prediction. Branches and jumps are resolved in the EX stage. When a redirect is required, younger instructions are flushed from the pipeline.

## Project Structure

```text
hazard-aware-riscv-pipeline/
├── rtl/
│   ├── alu.v
│   ├── register_file.v
│   ├── imm_gen.v
│   ├── control_unit.v
│   ├── program_counter.v
│   ├── instruction_memory.v
│   ├── data_memory.v
│   ├── branch_comparator.v
│   ├── if_id_register.v
│   ├── id_ex_register.v
│   ├── ex_mem_register.v
│   ├── mem_wb_register.v
│   ├── forwarding_unit.v
│   ├── hazard_detection_unit.v
│   ├── if_stage.v
│   ├── id_stage.v
│   ├── ex_stage.v
│   ├── mem_stage.v
│   ├── wb_stage.v
│   └── riscv_cpu.v
├── testbench/
├── simulations/
└── docs/
```

## Verification

The processor has been tested using Verilog testbenches with Icarus Verilog.

| Test Suite | Checks Passed |
|---|---:|
| Basic CPU integration | 15/15 |
| Load/store and load-use hazards | 30/30 |
| Branch and control hazards | 48/48 |
| JAL and JALR | 31/31 |
| Remaining supported instructions | 50/50 |
| R-type ALU operations | 35/35 |
| **Total** | **209/209** |

Waveforms were inspected using GTKWave to examine pipeline behaviour and control signals.

## Tools Used

- Verilog HDL (IEEE 1364-2001 compatible coding style)
- Icarus Verilog – RTL simulation
- GTKWave – waveform analysis
- Visual Studio Code – development environment
- Git and GitHub – version control

## Current Status

The processor RTL and six top-level integration test suites have been completed, with all 209 reported checks passing.

Further work includes synthesis, hardware resource analysis, timing analysis, and expanding instruction coverage.

## Learning Objectives

This project explores practical implementation of:
- RISC-V instruction execution.
- Five-stage pipelined processor architecture.
- Pipeline data and control hazards.
- Forwarding and stall mechanisms.
- Branch prediction and pipeline recovery.
- RTL simulation and verification.
