# RISC-V 32-bit Pipelined Processor & Arcade Console Co-Design

A 32-bit RISC-V (RV32I) processor built from scratch in Verilog, featuring a classic
5-stage pipeline, a custom data cache, and hand-built memory-mapped peripherals — all
driving a fully playable **Space Invaders clone** running bare-metal on an FPGA.

No off-the-shelf CPU IP, no OS, no existing game engine — the processor, the graphics
pipeline, the sound driver, and the game itself were all designed from the ground up.

---

## Overview

This project implements a working RV32I processor and uses it to run a complete
arcade game with real VGA video output and PWM audio, entirely in custom Verilog.
It was verified through simulation and deployed on a Xilinx Basys 3 FPGA (Artix-7
XC7A35T) using Vivado.

**Highlights:**
- Full 5-stage pipeline (Fetch → Decode → Execute → Memory → Writeback)
- Data & control hazard resolution (forwarding, stalling, flushing)
- Custom direct-mapped, write-through data cache with a hit/miss FSM
- Memory-mapped VGA controller generating real 640×480 @ 60Hz timing from scratch
- Memory-mapped PWM audio driver for real-time sound effects
- 300+ lines of hand-written, bare-metal RISC-V assembly implementing the game logic
- No OS abstraction layer — the assembly runs directly on the raw pipeline

---

## Architecture

```
        ┌────────┐   ┌────────┐   ┌─────────┐   ┌────────┐   ┌───────────┐
 PC ──▶ │ FETCH  │──▶│ DECODE │──▶│ EXECUTE │──▶│ MEMORY │──▶│ WRITEBACK │
        └────────┘   └────────┘   └─────────┘   └────────┘   └───────────┘
             ▲             ▲            │             │             │
             │             │            ▼             ▼             │
             │       ┌───────────┐  ┌────────┐   ┌──────────┐       │
             └───────│  Hazard/  │  │Forward-│   │ D-Cache  │       │
                     │  Stall    │  │ing Unit│   │ (4-line, │       │
                     │  Unit     │  └────────┘   │ direct-  │       │
                     └───────────┘               │ mapped)  │       │
                                                  └──────────┘       │
                                                                     ▼
                                                          register file (x0–x31)
```

### Pipeline & Hazard Handling
- **Data hazards** — resolved via a priority-based MEM/WB forwarding unit
  (`forwarding_unit.v`), with MEM-stage results taking priority over WB-stage results
- **Load-use hazards** — detected and resolved with single-cycle stall-and-flush logic
  (`hazard_unit.v`)
- **Control hazards** — branches resolve in the Execute stage; in-flight pipeline
  registers are flushed on taken branches

### Memory System
- `dcache.v` — a 4-line, direct-mapped, write-through data cache sitting between the
  pipeline and main memory, with an explicit hit/miss finite-state machine
- `data_mem.v` / `instruction_memory.v` — backing memory for data and instructions
- `program.mem` — the assembled machine code for the game, loaded into instruction
  memory at synthesis/simulation time

### Custom Peripherals (memory-mapped, no off-the-shelf IP)
- **`vga_controller.v`** — generates true 640×480 @ 60Hz VGA timing from scratch,
  with hand-authored sprite ROMs for a 3×8 animated alien grid, the player ship, and
  explosion effects, plus a live on-screen decimal score counter
- **PWM audio driver** — a memory-mapped square-wave generator for real-time sound
  effects (laser fire, explosions), driven directly by writes from the assembly game
  loop
- **`debounce.v`** — clean, asynchronous button input polling for player controls

### Datapath
- **`alu.v`** — 9-operation ALU (ADD, SUB, SLL, SRL, SRA, SLT, XOR, OR, AND)
- **`decoder.v`** — instruction decode logic for the supported RV32I subset
- **`imm_gen.v`** — sign-extended immediate generation for I-type, S-type, and
  B-type instruction encodings
- **`register_file.v`** — 32-entry register file with hardwired `x0`, negedge-triggered
  writes, and same-cycle write-before-read internal bypassing
- **`program_counter.v`** — PC update logic, including branch target selection

### Software
The game itself (a Space Invaders clone) is written entirely in bare-metal RISC-V
assembly. With no operating system, no runtime, just the raw instruction stream running
on the pipeline. It handles the game loop, alien movement, collision detection, laser
firing, scoring, score-based laser speed increments, and sound/graphics triggering,
all through direct memory mapped I/O.

---

## Repository Structure

| File                     | Description                                          |
|--------------------------|------------------------------------------------------|
| `top.v`                  | Top-level module wiring the full pipeline and peripherals |
| `top_tb.v`               | Testbench for simulating `top.v`                    |
| `alu.v`                  | Arithmetic logic unit                               |
| `decoder.v`              | Instruction decoder                                 |
| `imm_gen.v`              | Immediate value generator                           |
| `register_file.v`        | 32-entry general-purpose register file              |
| `program_counter.v`      | Program counter and next-PC logic                   |
| `pipe_reg.v`             | Pipeline stage registers                            |
| `forwarding_unit.v`      | Data hazard forwarding logic                        |
| `hazard_unit.v`          | Load-use stall and branch flush logic               |
| `dcache.v`               | Direct-mapped, write-through data cache             |
| `data_mem.v`             | Data memory                                         |
| `instruction_memory.v`   | Instruction memory                                  |
| `vga_controller.v`       | VGA timing, sprite rendering, and score display     |
| `debounce.v`             | Button input debouncing                             |
| `program.mem`            | Assembled machine code for the game                 |

---

## Getting Started

### Simulation
1. Open the project in Vivado (or your Verilog simulator of choice).
2. Run `top_tb.v` as the simulation top module.
3. Inspect waveforms to verify pipeline timing, hazard resolution, and memory bus
   behavior.

### Synthesis & FPGA Deployment
1. Target hardware: **Xilinx/AMD Basys 3 (Artix-7 XC7A35T)**.
2. Set `top.v` as the synthesis top module and assign the Basys 3 constraints file
   (VGA output, buzzer pin, buttons, clock, reset).
3. Generate the bitstream in Vivado and program the board.
4. Connect a VGA monitor and speaker/buzzer — the game boots directly from
   `program.mem` with no bootloader.

---

## Demo

*(Add a photo or short clip of the game running on the Basys 3 + VGA monitor here —
this is the single most effective thing you can add to this README.)*

---

## Background

Built as an independent project to explore computer architecture end-to-end: pipeline
design, hazard resolution, cache design, and custom peripheral integration, all the
way up through a real, playable piece of software running with zero OS support. This project
ended up being much more than what was originally planned, and I could not be any happier with
the result in both the perspective of a learning student, and a game development enthusiast. The
concept of my own processor running a classic video game is so fascinating to me, and something that 
I look forward to exploring further in the future!
