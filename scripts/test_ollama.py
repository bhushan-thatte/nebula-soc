import json
import ollama

# Load our real, validated violation data from Milestone 3b
with open("reports/milestone3_final.json") as f:
    data = json.load(f)

violations = data["genuine_setup_violations"]
print(f"Loaded {len(violations)} genuine setup violations.\n")

# Take the single worst violation (most negative slack) as our test case
worst = min(violations, key=lambda v: v["slack"])

print("=== WORST VIOLATION ===")
print(f"Startpoint: {worst['startpoint']}")
print(f"Endpoint:   {worst['endpoint']}")
print(f"Slack:      {worst['slack']} ns")
print(f"Dominant cells: {worst['dominant_cells'][:5]}")
print()

# Build a concise, structured prompt describing the violation
prompt = f"""You are a digital design engineer specializing in RTL timing closure.

A static timing analysis tool reported a SETUP TIMING VIOLATION in a synthesized
Verilog design (SKY130HD standard cell library, 250MHz clk_dsp domain, 4.0ns period):

Startpoint: {worst['startpoint']}
Endpoint:   {worst['endpoint']}
Slack:      {worst['slack']} ns (VIOLATED — negative means too slow)
Dominant cell types on the critical path (cell_type, total_delay_ns):
{worst['dominant_cells'][:5]}

Context: This path is part of a 16-tap FIR filter's adder tree, which sums
partial products using a ripple-carry adder structure. The design already has
one pipeline stage splitting the tree into 2 stages, but this specific path
still violates timing.

Question: Based on the dominant cell types shown (half-adders 'ha_1' and
full-adders 'fa_1' indicate ripple-carry chains), what is the most effective
RTL-level fix to close this timing violation? Give a specific, actionable
recommendation (e.g. add another pipeline stage, restructure the adder tree,
use a different adder architecture) in 4-6 sentences. Be concrete and technical.
"""

print("=== SENDING PROMPT TO qwen2.5-coder:3b ===\n")
response = ollama.generate(model="qwen2.5-coder:3b", prompt=prompt)
print("=== MODEL RESPONSE ===")
print(response["response"])
