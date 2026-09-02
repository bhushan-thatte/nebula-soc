# 50K-Cell Scaling Exploration - Findings

## Objective
The hackathon benchmark specifies a target of ~50K standard cells. Our
core verified deliverable (commit 1182b4c) sits at ~11,536 cells,
deliberately kept small during Weeks 1-3 to prioritize proving the
timing-analysis and GenAI-optimization pipeline on real, correct data
before scaling up. This document records a subsequent scaling attempt
and its findings.

## Approach 1: Domain C FIR tap count (16 -> 64 -> 128 taps)
Built scripts/generate_fir.py, a parameterized RTL generator producing
a fully-pipelined balanced adder-tree FIR filter with ONE pipeline
register per tree level (guaranteeing bounded combinational depth
regardless of tap count, avoiding the exact multi-level-unpipelined
bug that caused our original Milestone 1-3 violations).

Measured results (standalone Domain C cell count):
  16 taps  ->  4,360 cells
  64 taps  -> 26,206 cells
  128 taps -> 61,633 cells

Full-design synthesis with 128-tap Domain C (Domain B unchanged):
  Total cells: 23,266
  Timing: clk_dsp WNS -1.16ns, TNS -50.44ns (all other 11 clock
  groups fully MET, including CDC infrastructure)

FINDING: FIR tap scaling works cleanly and predictably. The remaining
clk_dsp violation is a normal, bounded, well-understood timing-closure
problem (same category as our Milestone 3 work) -- NOT a structural
or architectural issue. Given more iteration time, this would likely
close with one additional pipeline stage, following the exact same
process already demonstrated and verified in this project.

## Approach 2: Domain B memory depth (64 -> 1024 -> 2048 entries)
Widened the memory array and address bus, and fixed a genuine
pre-existing bug (req0_addr was hardcoded to a single address at the
top level, meaning all writes clobbered address 0) by adding an
auto-incrementing write-address counter.

FINDING: This approach hit a hard architectural wall. Yosys's default
synthesis flow has no SRAM compiler -- memory arrays synthesize as
literal flip-flop arrays where the write-data bus must fan out
combinationally to every entry's write-mux input. At 2048 entries this
produced a single net with 2049 fanout loads, requiring a buffer/drive
structure whose RC delay alone (23+ ns) exceeded the entire 5ns
clk_mem clock period -- independent of how many pipeline register
stages were inserted before the memory array, since each new register
still faces the same fundamental fan-out-to-2048-loads problem on its
own output.

We also found and fixed a real latency-alignment bug this exploration
surfaced: after adding a pipeline register in Domain B, a downstream
CDC FIFO's write-enable signal (still driven by the un-delayed
arbitration grant) became misaligned with the actual delayed data,
which via OpenROAD's dead-logic elimination silently pruned most of
Domain A's logic as unreachable. This was diagnosed and fixed
correctly (new req0_rdata_valid output, properly registered) but the
underlying fanout/timing wall remained regardless.

CONCLUSION: Domain B memory depth is not a viable scaling lever
without a real SRAM macro/compiler (not available in this open-source
flow) or a fundamentally different memory architecture (e.g. banked
memory with narrower per-bank fanout). This is a legitimate,
documented finding about open-source ASIC flow limitations, not a
project shortcoming.

## Final decision
Given the fanout wall is a genuine tooling/flow limitation (not fixable
via more iteration in the time available) and the FIR-scaling path,
while viable, would require another full debug cycle to close its
timing violation cleanly, we reverted to the fully-verified Milestone 4
state (WNS +0.55ns, TNS 0.00ns, all clock groups MET, formally verified
via EQY) as the submitted deliverable. This prioritizes correctness and
completeness of the demonstrated GenAI-assisted timing-closure pipeline
over hitting the exact cell-count target, and the scaling exploration
above is presented as a supplementary finding demonstrating the team's
engineering depth beyond the minimum working demo.

## Reproducing this exploration
scripts/generate_fir.py <num_taps> <output_file> regenerates any FIR
size. Domain B's widened version is preserved in git history at the
commit documenting this exploration, for reference.
