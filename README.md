# FPGA Debug Probe — Phase 1: Control & Trigger

A SystemVerilog control-and-trigger prototype implemented and tested on the Terasic DE10-Lite FPGA board.

Phase 1 establishes the control path for a future mini logic analyzer: accept an ARM command, wait for an external trigger, and latch the triggered state until reset.

> Current scope: trigger detection and control only. This version does not sample signals into capture RAM or export waveform data.

## Hardware

- Terasic DE10-Lite FPGA board
- 50 MHz input clock (`MAX10_CLK1_50`)
- On-board KEY0 and KEY1 buttons
- External 4×4 matrix keypad used as a manual trigger source
- HEX0/HEX1 and LEDR0/LEDR1 for diagnostics

## Architecture

```text
KEY1 (active-low)
    |
    v
Invert -> 2-FF synchronizer -> Debounce -> Rising-edge detector
                                             |
                                             v
                                        press_pulse
                                         /                                               v         v
                                  Press counter  ARM event
                                        |         |
                                       HEX1       v
                                             Capture FSM -> HEX0
                                                  ^
                                                  |
ROW_0 (active-low) -> Invert -> 2-FF synchronizer -> Rising-edge detector

KEY0 (active-low) -> Reset
50 MHz clock     -> Heartbeat counter -> LEDR0
Debounced KEY1   -> LEDR1
```

All sequential modules in this integration use `MAX10_CLK1_50`. The debounce timing uses a one-cycle 1 ms clock-enable tick.

## State Machine

| State | Encoding | Behavior |
|---|---|---|
| IDLE | `0` | Wait for a KEY1 press event. |
| ARMED | `1` | Wait for an external trigger event. |
| DONE | `2` | Hold the triggered state until reset. |

```text
IDLE -- KEY1 press --> ARMED -- external trigger --> DONE
 ^                                                   |
 +------------------- KEY0 reset --------------------+

KEY0 also resets the design from IDLE or ARMED.
```

The FSM has a `clear_pulse` input, but the current top-level ties it to `1'b0`. A separate clear-command path is not tested in this integration.

### Event routing

```systemverilog
assign arm_event = press_pulse && (capture_state == 2'd0);
assign trigger_event = trigger_rise_pulse && (capture_state == 2'd1);
```

- KEY1 arms the system only in IDLE.
- Additional KEY1 presses still increment the diagnostic counter, but do not serve as the trigger in the current RTL.
- External trigger pulses are accepted only in ARMED.
- DONE is latched until reset.

## External Trigger Input

The top-level receives an active-low keypad row signal:

```systemverilog
input logic ROW_0;

logic trigger_in;
logic trigger_sync;
logic trigger_rise_pulse;

assign trigger_in = ~ROW_0;
```

The inversion converts a falling edge on `ROW_0` into a rising edge for the trigger pipeline. The trigger is recognized after synchronization and registered edge detection, not instantaneously at the physical pin.

### Reported working configuration

| Signal | FPGA location | Configuration |
|---|---|---|
| `ROW_0` | `PIN_AB3` | Input, weak pull-up enabled |

This documents the working Phase 1 assignment reported during hardware testing. Use the repository's `.qsf` for the complete project pin assignments.

### Keypad wiring requirement

A passive matrix keypad key connects a row to a column; it does not generate a LOW level by itself. The tested key must connect `ROW_0` to a column held LOW in the test setup.

The current top-level exposes only `ROW_0`; it does not contain a keypad column scanner or column output ports. The external column wiring is therefore part of the hardware test fixture and must be preserved or documented before reproducing the test. Do not assume that any arbitrary key will trigger the system.

Do not connect a column directly to ground if another device or FPGA output is driving that line HIGH.

## Diagnostic Outputs

| Output | Meaning |
|---|---|
| HEX0 | FSM state: `0` = IDLE, `1` = ARMED, `2` = DONE |
| HEX1 | Low hexadecimal digit of the KEY1 press counter |
| LEDR0 | Heartbeat from `count[25]` |
| LEDR1 | Debounced KEY1 pressed level; ON while KEY1 is held |

`press_count` is 8 bits wide, but HEX1 displays only `press_count[3:0]`, so the visible digit wraps after `F`. Keypad trigger events do not increment this counter.

LEDR1 is not an ARMED or DONE indicator.

## RTL Modules

| Module | Role |
|---|---|
| `debug_probe_phase1_top` | Top-level integration and event routing |
| `sync_2ff` | Two-stage synchronization of asynchronous inputs |
| `clock_enable` | Generates the 1 ms debounce timing tick |
| `debounce` | Filters the synchronized KEY1 level; configured with `STABLE_TICKS = 10` |
| `edge_detect` | Generates a registered pulse for a rising edge |
| `capture_fsm` | Implements IDLE, ARMED, and DONE |
| `hex_to_7seg` | Drives diagnostic seven-segment displays |

## Build and Program

1. Open the project in Quartus Prime.
2. Confirm that `debug_probe_phase1_top` is the top-level entity.
3. Add all required SystemVerilog source files if creating a fresh project.
4. Check the `.qsf` assignments against the actual board and keypad wiring.
5. Confirm that `ROW_0` has its weak pull-up enabled and that the 50 MHz clock has the appropriate timing constraint.
6. Compile and review warnings, especially ignored assignments, implicit nets, undriven inputs, and missing timing constraints.
7. Program the board with the newly generated `.sof`.
8. Run the hardware checks below.

Successful compilation alone is not a hardware validation result.

## Hardware Validation

### Verified: original baseline

Before the external trigger was integrated, KEY1 was used for both ARM and a simulated trigger.

- First press: IDLE -> ARMED.
- Holding KEY1: no repeated press-counter increments and no automatic transition.
- Second distinct press: ARMED -> DONE.
- Additional press in DONE: state remains DONE while the press counter increments.
- KEY0 resets both state and press counter.

This is the earlier baseline, not the event routing used by the current external-trigger version.

### Verified: external-trigger integration

The following sequence was confirmed on hardware:

| Step | Action | HEX0: state | HEX1: KEY1 count |
|---|---|---|---|
| 1 | Press and release KEY0 | `0` | `0` |
| 2 | Press and release KEY1 once | `1` | `1` |
| 3 | Wait without pressing the keypad | Remains `1` | Remains `1` |
| 4 | Press the keypad key connected to the active trigger path | `2` | Remains `1` |
| 5 | Hold and release that keypad key | Remains `2` | Remains `1` |
| 6 | Press the keypad key again | Remains `2` | Remains `1` |
| 7 | Press KEY0 | `0` | `0` |

Result: external-trigger control path PASS for this sequence.

### Additional regression check — not yet reported

The following check is supported by the current RTL, but was not explicitly confirmed after external-trigger integration:

1. Reset.
2. Press KEY1 to ARM.
3. Release KEY1 and press it again, without activating the keypad trigger.
4. Confirm that HEX0 stays at `1` while HEX1 advances to `2`.
5. Activate the keypad trigger and confirm that HEX0 becomes `2` while HEX1 stays at `2`.

This distinguishes the current external-trigger design from the earlier KEY1-trigger baseline.

## Limitations

- DONE means that a trigger was detected, not that a data capture completed.
- No capture RAM, sample buffer, or waveform export is integrated.
- No multi-channel acquisition is implemented.
- The keypad trigger path is synchronized and edge-detected, but not debounced. The latched DONE state can hide additional pulses from mechanical bounce; this test does not prove one pulse per keypad press.
- This is not a complete keypad decoder: it does not identify individual keys.
- Trigger events outside ARMED are not queued for later use.
- Two-stage synchronization does not guarantee detection of arbitrarily short external pulses. No maximum trigger rate or minimum pulse-width specification has been validated.
- Begin the manual test with the trigger key released. Holding the input active during reset/rearming is not covered by the verified test sequence.
- A dedicated clear command, reset-release synchronization improvements, and full timing/CDC sign-off are outside the verified Phase 1 scope.

## Next Milestone

Complete the remaining KEY1 regression check and preserve this version as the Phase 1 hardware baseline.

The proposed next phase is a capture engine: add sample storage, a sample counter/write address, and an acquisition-complete condition. At that point, trigger detection and capture completion should be treated as distinct events rather than using the current DONE state as a substitute for captured data.
