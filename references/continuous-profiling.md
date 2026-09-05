---
description: OpenTelemetry Continuous Profiling architecture, OTEP 0212 data model, flamegraphs, and DWARF/JIT symbolication.
metadata:
  tags: [profiling, continuous-profiling, otep-0212, flamegraphs, symbolication, pprof]
---

# Continuous Profiling & OTel Profiles Data Model

Continuous profiling collects execution call stacks continuously across production workloads, linking CPU consumption, memory allocations, and lock contention directly to distributed traces.

---

## 1. The OTel Profiling Data Model (OTEP 0212)

Unlike metrics or logs, profiling samples share identical deep call stacks. The OTLP Profiles format (`profiles.proto`) uses a **Normalized Shared Dictionary Table** to achieve extreme wire compression.

- Repeated function names and filenames exist only once in `string_table`.
- A 50-frame call stack is represented in each sample by a single 4-byte `stack_index`.
- Samples link directly to distributed traces via a typed `Link` (`trace_id` and `span_id`).

---

## 2. On-CPU vs. Off-CPU Profiling Mechanics

### 2.1 On-CPU Profiling
- Uses a kernel timer interrupt configured at a prime frequency (e.g., **49 Hz** or **19 Hz**).
  > **Why Prime Numbers?** Standard 100 Hz timers synchronize with harmonic application events (10ms cron ticks, GC sweeps), causing sampling bias. Prime frequencies prevent phase locking.
- On each interrupt, the profiler unwinds the user and kernel instruction pointers and records the stack.

### 2.2 Off-CPU Profiling
- Measures time threads spend in blocked states (waiting on locks, network reads, disk I/O).
- Hooks `sched:sched_switch`:
  1. When a thread is descheduled, records `t_start = bpf_ktime_get_ns()`.
  2. When the thread resumes on a CPU, computes `delta_t = bpf_ktime_get_ns() - t_start`.
  3. If `delta_t > 1ms`, records the call stack that put the thread to sleep.

---

## 3. Symbolication Architecture

Raw eBPF samples record 64-bit instruction pointers (e.g., `0x7f8a12c4b5d0`). Symbolication maps addresses to human-readable functions and source lines:

1. **Address Normalization**: Read `/proc/<pid>/maps` to calculate relative offset:
   `Relative PC = Instruction Pointer - Base Virtual Address`
2. **Build ID Matching**: Read GNU Build ID from the ELF `.note.gnu.build-id` section to guarantee debug symbols match the running binary.
3. **Symbol Resolution**:
   - Go: Read `.gopclntab` embedded directly in Go binaries.
   - C++/Rust: Read DWARF `.debug_info` and `.debug_line` tables.
   - JIT Runtimes (Java, Node.js): Read `/tmp/perf-<pid>.map` or invoke JVM TI `AsyncGetCallTrace`.
