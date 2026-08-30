"""
Nebula SoC — GenAI RTL Timing Optimization Engine (Week 2)
=============================================================
Runs each genuine setup violation (from timing_parser.py output) through
a local open-source LLM (qwen2.5-coder:7b via Ollama) to propose a fix,
constrained to a fixed set of real, standard timing-closure techniques.
"""

import json
import time
import ollama

MODEL = "qwen2.5-coder:7b"

# Fixed vocabulary of real, standard fixes -- prevents the model from
# inventing non-existent architecture names (observed failure mode in
# early testing: "parallel ripple-carry adder" is not a real technique).
VALID_TECHNIQUES = [
    "ADD_PIPELINE_STAGE",
    "CARRY_LOOKAHEAD_ADDER",
    "CARRY_SAVE_ADDER",
    "TREE_REBALANCING",
    "RETIMING",
    "OTHER",
]

PROMPT_TEMPLATE = """You are a digital design engineer specializing in RTL timing closure.

A static timing analysis tool reported a SETUP TIMING VIOLATION in a synthesized
Verilog design (SKY130HD standard cell library, clk_dsp domain, 4.0ns period):

Startpoint: {startpoint}
Endpoint:   {endpoint}
Slack:      {slack} ns (VIOLATED)
Dominant cell types on the critical path (cell_type, total_delay_ns):
{dominant_cells}

Context: This is part of a 16-tap FIR filter's adder tree (already has one
pipeline stage). The dominant cells are standard-cell half-adders (ha_1) and
full-adders (fa_1), indicating a ripple-carry-style structure.

You MUST choose exactly ONE technique from this fixed list, and explain briefly:
- ADD_PIPELINE_STAGE: insert another register stage to split the critical path
- CARRY_LOOKAHEAD_ADDER: replace ripple-carry summation with carry-lookahead logic
- CARRY_SAVE_ADDER: use carry-save form for multi-operand addition, resolve at the end
- TREE_REBALANCING: restructure the adder tree for better logic-depth balance
- RETIMING: move existing registers across combinational logic to balance stages
- OTHER: only if none of the above genuinely apply (explain why)

Respond in EXACTLY this format:
TECHNIQUE: <one of the six labels above>
REASONING: <2-3 sentences explaining why, referencing the specific cell types/delays given>
"""


def query_violation(violation: dict) -> dict:
    prompt = PROMPT_TEMPLATE.format(
        startpoint=violation["startpoint"],
        endpoint=violation["endpoint"],
        slack=violation["slack"],
        dominant_cells=violation["dominant_cells"][:5],
    )
    start = time.time()
    response = ollama.generate(model=MODEL, prompt=prompt)
    elapsed = time.time() - start

    text = response["response"].strip()

    # Parse the structured response
    technique = "PARSE_FAILED"
    reasoning = text
    for line in text.splitlines():
        if line.strip().upper().startswith("TECHNIQUE:"):
            candidate = line.split(":", 1)[1].strip().upper()
            for valid in VALID_TECHNIQUES:
                if valid in candidate:
                    technique = valid
                    break
        if line.strip().upper().startswith("REASONING:"):
            reasoning = line.split(":", 1)[1].strip()

    return {
        "startpoint": violation["startpoint"],
        "endpoint": violation["endpoint"],
        "slack": violation["slack"],
        "dominant_cells": violation["dominant_cells"][:5],
        "ai_technique": technique,
        "ai_reasoning": reasoning,
        "raw_response": text,
        "query_time_seconds": round(elapsed, 1),
    }


def main():
    with open("reports/milestone3_final.json") as f:
        data = json.load(f)

    violations = data["genuine_setup_violations"]
    print(f"Loaded {len(violations)} genuine setup violations.")
    print(f"Running each through {MODEL}... this will take a few minutes.\n")

    results = []
    for i, v in enumerate(violations, 1):
        print(f"[{i}/{len(violations)}] {v['startpoint']} -> {v['endpoint']} (slack={v['slack']})...", end=" ", flush=True)
        result = query_violation(v)
        results.append(result)
        print(f"-> {result['ai_technique']} ({result['query_time_seconds']}s)")

    with open("reports/genai_suggestions.json", "w") as f:
        json.dump(results, f, indent=2)

    print(f"\nDone. Wrote {len(results)} results to reports/genai_suggestions.json")

    # Quick summary
    from collections import Counter
    technique_counts = Counter(r["ai_technique"] for r in results)
    print("\nTechnique distribution:")
    for tech, count in technique_counts.most_common():
        print(f"  {tech}: {count}")


if __name__ == "__main__":
    main()
