# AXI4-Stream Asynchronous FIFO

A parameterized asynchronous FIFO implemented in Verilog for AXI4-Stream data transfer across independent clock domains. The design uses binary pointers for local memory addressing, Gray-coded pointers for clock-domain crossing, and 2-stage synchronizers for safe pointer transfer.

## Architecture

- AXI4-Stream slave interface on the write clock domain
- AXI4-Stream master interface on the read clock domain
- 16-entry FIFO depth
- 8-bit AXI TDATA width
- 9-bit internal FIFO word width: `{TLAST, TDATA}`
- Binary read/write pointers for local addressing
- Gray-coded pointers for CDC
- 2-stage flip-flop synchronizers
- FULL/EMPTY generation
- Randomized SystemVerilog verification environment

## Dataflow

```
AXI source
   |
   | TVALID && TREADY
   v
{TLAST, TDATA}
   |
   v
FIFO memory
   |
   v
AXI output
```

The write and read sides use independent clocks. Gray-coded read/write pointers are synchronized into the opposite clock domain and used for FULL/EMPTY detection.

## Verification

The SystemVerilog testbench includes:

- Random packet lengths from 4 to 12 beats
- Randomized TDATA
- Random source idle periods
- Random downstream backpressure
- Scoreboard-based data/TLAST checking
- AXI4-Stream protocol assertions
- X/Z control-signal checks
- Simulation timeout watchdog

A finalized randomized run transferred 50 packets and 411 beats with:

- Expected beats: 411
- Sent beats: 411
- Received beats: 411
- Errors: 0

## Timing / Implementation

The design was simulated with independent 100 MHz write and approximately 38.46 MHz read clocks.

Vivado implementation results included:

- Setup WNS: +7.312 ns
- Setup TNS: 0 ns
- Setup failing endpoints: 0
- Hold WNS: +0.060 ns
- Hold TNS: 0 ns
- Hold failing endpoints: 0

## Repository Layout

```
rtl/
  async_fifo.v
  sub_modules.v

tb/
  tb_async_fifo.sv

docs/
  AXI4_Stream_Async_FIFO_Report.pdf
```

## Tools

- Verilog
- SystemVerilog
- Xilinx Vivado
- Vivado Simulator
