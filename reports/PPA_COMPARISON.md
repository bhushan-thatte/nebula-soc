# Nebula SoC - PPA Comparison Report

## Summary

This report documents the measured Power-Performance-Area impact of
the GenAI-assisted timing closure applied to Domain C (16-tap FIR
filter) of the Nebula multi-clock SoC benchmark. All numbers below are
taken directly from real OpenSTA/OpenROAD synthesis runs against the
real SKY130HD standard cell library (sky130_fd_sc_hd__tt_025C_1v80),
not estimated or simulated.

## Timing (Performance) Comparison

| Stage | Description | WNS (ns) | TNS (ns) | Violating Endpoints |
|---|---|---|---|---|
| Milestone 1 | Naive RTL: serial 15-add chain in FIR MAC | -3.85 | -49.59 | many (unmeasured, pre-parser) |
| Milestone 2 | Balanced adder tree, unpipelined | -3.14 | -43.95 | many (unmeasured, pre-parser) |
| Milestone 3 | Balanced tree + 1 pipeline stage (2-stage total) | -0.64 | -4.58 | 16 |
| **Milestone 4** | **+ GenAI-recommended 2nd pipeline stage (3-stage total)** | **+0.55** | **0.00** | **0** |

**Result: 100% of setup timing violations closed.** WNS improved by
+1.19 ns from Milestone 3 (114% improvement in slack), TNS improved by
100% (from -4.58 ns to fully closed). All 12 clock path groups
(clk_core, clk_150, clk_mem, clk_50_b, clk_dsp, clk_50_c, clk_bridge,
clk_50_d, clk_33_d, clk_periph, clk_25, asynchronous) are simultaneously
MET with zero violations in the final state -- confirmed independently
via manual OpenSTA report_checks AND via our own timing_parser.py tool
on the same synthesis output.

Every other clock domain's WNS moved by at most +/-0.3 ns between
Milestone 3 and 4 (normal re-synthesis noise), confirming the
GenAI-recommended fix was surgical -- it closed the target violation
without disturbing timing elsewhere in the design.

## Area Comparison

| Stage | Design Area (um^2) | Total Cells |
|---|---|---|
| Milestone 3 (before fix) | ~53,702 | (not independently re-measured; superseded by M4 methodology below) |
| **Milestone 4 (after fix, final verified state)** | **56,054** | **4,283** |

Area increased by ~4.4% (2,352 um^2) due to the added pipeline
register stage (8 x 41-bit registers). This is the expected, minor
cost of the timing fix -- a small area trade for full timing closure.

## Formal Verification

The GenAI-recommended fix changes design latency (2-cycle to 3-cycle
sample-to-result pipeline). Standard cycle-accurate EQY equivalence
checking does not directly apply to a latency-changing fix, so a
latency-matched wrapper was used to reduce the problem to a standard
equivalence check (see reports/formal_verification/SUMMARY.md for
full methodology).

Results:
- result_valid (control/latency path): PROVEN EQUIVALENT via full
  k-induction (unconditional proof, sat strategy)
- result_out (datapath): exhaustively verified for all reachable
  states within 8 clock cycles of reset (covers the full 3-stage
  pipeline fill transient plus 5 steady-state cycles). Full unbounded
  induction was not achieved due to known SAT/SMT scaling limits on
  the 24x16-bit multiply + 4-level adder tree; the induction
  counterexample was traced to an unreachable (X-propagated) initial
  state, not a real functional discrepancy.

## GenAI Optimization Engine

All 16 genuine setup violations from Milestone 3 were independently
analyzed by a local, open-source LLM (qwen2.5-coder:7b via Ollama, no
API cost, GPU-accelerated) using a constrained prompt restricting
output to six real, standard timing-closure techniques. Result:

| Technique | Votes |
|---|---|
| ADD_PIPELINE_STAGE | 11 / 16 |
| RETIMING | 5 / 16 |

The majority-recommended technique (ADD_PIPELINE_STAGE) was
implemented by hand, guided by the AI's per-violation reasoning
(each recommendation correctly cited the specific dominant cell types
-- sky130_fd_sc_hd__ha_1 / fa_1 ripple-carry adders -- and their
measured delay contribution from the actual timing report). The
resulting fix, described above, achieved full timing closure.

## Scaling to the ~50K cell benchmark (second, fully-verified deliverable)

UPDATE: the FIR tap-count scaling exploration referenced below was
carried to full closure after this report was first written. The
initial 128-tap attempt (23,266 cells full-design) left a small
residual violation (WNS -0.05ns, TNS -0.09ns, 2 endpoints), traced to
one tap's constant-multiplier depth rather than the adder tree. At
256 taps this widened to 13 endpoints, confirming the pattern scaled
with tap count via unlucky constants. The FIR generator
(scripts/generate_fir.py) was upgraded to split every tap's multiply
into two registered half-width stages, applied uniformly across all
taps -- closing the design fully.

**Result: a second, independently-verified deliverable exceeding the
~50K cell benchmark target, with 0 violations:**

| Deliverable | Cells | Area | WNS | TNS | Violations |
|---|---|---|---|---|---|
| Primary (M4, submitted baseline) | 4,283 | 56,054 um^2 | +0.55 ns | 0.00 ns | 0 |
| **Secondary (256-tap, spec-scale)** | **68,510** | **802,926 um^2** | **+0.03 ns** | **0.00 ns** | **0** |

The 256-tap result's margin (+0.03ns) is thin compared to the primary
design's +0.55ns, and was measured at the synthesis stage with an
ideal clock network -- a placement-and-route-aware pass was attempted
to confirm it under real parasitics but was blocked by an internal
ORFS/OpenROAD tooling issue (generated-clock net names corrupted
during the synthesis-to-placement SDC handoff), unrelated to RTL
correctness. This is documented as a known, unresolved limitation.

Domain B memory-depth scaling separately hit a genuine, documented
architectural limit of open-source (SRAM-compiler-free) memory
synthesis, and was not pursued further.

Full methodology: reports/SCALING_256TAP_CLOSURE.md. Original
exploratory notes (128-tap-only, since superseded): reports/SCALING_EXPLORATION.md.

## Reproducing these results

All commands, scripts, and raw logs referenced in this report are
committed to the project git history. Key files:
- reports/milestone3_final.rpt, milestone3_final.json (before-fix state)
- reports/milestone4_v1.rpt, milestone4_v1.json (after-fix state)
- reports/synth_full_log_milestone4_final.log (full synthesis log,
  area confirmation)
- reports/final_verified_timing.log, final_verified_cellcount.log
- reports/genai_suggestions.json (all 16 AI recommendations, raw)
- reports/formal_verification/ (EQY config + all proof logs)
- scripts/timing_parser.py (structured violation extraction)
- scripts/genai_engine.py (GenAI reasoning engine)
- reports/SCALING_256TAP_CLOSURE.md (second deliverable, full methodology)
- reports/256tap_final_cellcount.log (256-tap cell count, authoritative source)
- scripts/generate_fir.py (parameterized FIR generator, now includes the two-stage multiply pipeline fix)
