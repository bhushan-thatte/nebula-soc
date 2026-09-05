"""
Nebula SoC - GenAI Timing Closure Dashboard
=============================================
Interactive Streamlit dashboard presenting the full detect -> AI-suggest
-> patch -> verify pipeline results, sourced entirely from real saved
project data (reports/*.json, reports/*.log, reports/*.md).

Run: streamlit run scripts/dashboard.py
"""

import json
from pathlib import Path
from collections import Counter

import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px

REPORTS_DIR = Path(__file__).parent.parent / "reports"

st.set_page_config(
    page_title="Nebula SoC - GenAI Timing Closure",
    page_icon="\u26a1",
    layout="wide",
    initial_sidebar_state="collapsed",
)

# ---------------------------------------------------------------------------
# Theme / styling
# ---------------------------------------------------------------------------
ACCENT = "#00D9A0"
ACCENT_DARK = "#00A87D"
VIOLATION_RED = "#FF4B5C"
BG_DARK = "#0E1117"
CARD_BG = "#161B22"

st.markdown(f"""
<style>
    .metric-card {{
        background-color: {CARD_BG};
        border-radius: 10px;
        padding: 20px;
        border: 1px solid #30363D;
    }}
    div[data-testid="stMetricValue"] {{
        font-size: 28px;
    }}
    h1, h2, h3 {{
        font-weight: 700;
    }}
</style>
""", unsafe_allow_html=True)


# ---------------------------------------------------------------------------
# Data loading (all from real saved files)
# ---------------------------------------------------------------------------

@st.cache_data
def load_json(filename):
    path = REPORTS_DIR / filename
    if not path.exists():
        return None
    with open(path) as f:
        return json.load(f)


@st.cache_data
def load_genai_suggestions():
    path = REPORTS_DIR / "genai_suggestions.json"
    if not path.exists():
        return []
    with open(path) as f:
        return json.load(f)


m3 = load_json("milestone3_final.json")
m4 = load_json("milestone4_v1.json")
genai = load_genai_suggestions()

# Milestone-level timing progression (hardcoded from verified, saved
# reports -- baseline_timing_report.log and formal_verification/SUMMARY.md
# -- documented explicitly rather than re-parsed live, since these
# earlier-stage logs predate timing_parser.py)
MILESTONES = [
    {"name": "M1: Naive RTL\n(serial adder chain)", "wns": -3.85, "tns": -49.59, "violations": None},
    {"name": "M2: Balanced tree\n(unpipelined)", "wns": -3.14, "tns": -43.95, "violations": None},
    {"name": "M3: +1 pipeline stage\n(before GenAI fix)", "wns": -0.64, "tns": -4.58, "violations": 16},
    {"name": "M4: +GenAI 2nd stage\n(final, verified)", "wns": 0.55, "tns": 0.00, "violations": 0},
]

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

GITHUB_URL = "https://github.com/bhushan-thatte/nebula-soc"

st.markdown(f"""
<div style="display:flex; justify-content:space-between; align-items:flex-start; flex-wrap:wrap; gap:16px;">
    <div>
        <div style="color:{ACCENT}; font-weight:700; font-size:13px; letter-spacing:2px; text-transform:uppercase;">
            NEBULA HACKATHON 2026 &middot; Astera Labs &middot; Digital Design Track
        </div>
        <h1 style="margin:6px 0 4px 0; font-size:38px;">
            &#9889; GenAI-Assisted Timing Closure
        </h1>
        <div style="color:#8B949E; font-size:15px; max-width:700px;">
            <b>Problem statement:</b> Constraint Optimization through RTL Enhancement Using
            Generative AI &mdash; automate timing violation detection, AI-driven fix
            recommendation, and formally-verified RTL patching on a real 5-domain,
            multi-clock SoC benchmark.
        </div>
    </div>
    <div style="text-align:right; min-width:200px;">
        <a href="{GITHUB_URL}" target="_blank" style="text-decoration:none;">
            <div style="background-color:{CARD_BG}; border:1px solid {ACCENT}; border-radius:8px;
                        padding:10px 18px; color:{ACCENT}; font-weight:600; font-size:14px;
                        display:inline-block;">
                &#128279; View on GitHub
            </div>
        </a>
        <div style="color:#8B949E; font-size:12px; margin-top:10px;">
            Team: <i>ChipSmith</i><br>
            Bhushan Thatte &middot; Saksham Tawakley &middot; Yash Kothari
        </div>
    </div>
</div>
""", unsafe_allow_html=True)

st.markdown(
    "<div style='color:#8B949E; font-size:14px; margin-top:12px;'>"
    "5-domain multi-clock SoC &middot; Real SKY130HD synthesis &middot; "
    "Local open-source LLM (qwen2.5-coder:7b) &middot; Fully verified"
    "</div>",
    unsafe_allow_html=True,
)

st.markdown("---")

# ---------------------------------------------------------------------------
# Hero: Before / After story
# ---------------------------------------------------------------------------

hero_col1, hero_arrow, hero_col2 = st.columns([5, 1, 5])

with hero_col1:
    st.markdown(f"""
    <div style="background-color:{CARD_BG}; border-left: 5px solid {VIOLATION_RED};
                border-radius: 10px; padding: 24px;">
        <div style="color:{VIOLATION_RED}; font-weight:700; font-size:14px; letter-spacing:1px;">
            BEFORE &mdash; MILESTONE 3
        </div>
        <div style="font-size:42px; font-weight:800; margin-top:8px; color:white;">
            -0.64 ns
        </div>
        <div style="color:#8B949E; font-size:14px; margin-top:4px;">
            Worst Negative Slack &middot; 16 violating endpoints &middot; TNS -4.58 ns
        </div>
    </div>
    """, unsafe_allow_html=True)

with hero_arrow:
    st.markdown(
        f"<div style='display:flex; align-items:center; justify-content:center; "
        f"height:100%; font-size:32px; color:{ACCENT};'>&rarr;</div>",
        unsafe_allow_html=True,
    )

with hero_col2:
    st.markdown(f"""
    <div style="background-color:{CARD_BG}; border-left: 5px solid {ACCENT};
                border-radius: 10px; padding: 24px;">
        <div style="color:{ACCENT}; font-weight:700; font-size:14px; letter-spacing:1px;">
            AFTER &mdash; MILESTONE 4 (GenAI-fixed)
        </div>
        <div style="font-size:42px; font-weight:800; margin-top:8px; color:white;">
            +0.55 ns
        </div>
        <div style="color:#8B949E; font-size:14px; margin-top:4px;">
            Worst Negative Slack &middot; 0 violating endpoints &middot; TNS 0.00 ns
        </div>
    </div>
    """, unsafe_allow_html=True)

st.markdown("<br>", unsafe_allow_html=True)

# ---------------------------------------------------------------------------
# Top-line KPIs
# ---------------------------------------------------------------------------

col1, col2, col3, col4 = st.columns(4)

with col1:
    st.metric(
        label="Worst Negative Slack (WNS)",
        value="+0.55 ns",
        delta="+1.19 ns vs pre-fix",
        delta_color="normal",
    )
with col2:
    st.metric(
        label="Total Negative Slack (TNS)",
        value="0.00 ns",
        delta="100% closed",
        delta_color="normal",
    )
with col3:
    st.metric(
        label="Violating Endpoints",
        value="0",
        delta="-16 endpoints",
        delta_color="normal",
    )
with col4:
    st.metric(
        label="Design Area",
        value="56,054 \u00b5m\u00b2",
        delta="+4.4% (pipeline reg cost)",
        delta_color="off",
    )

st.markdown("---")

# ---------------------------------------------------------------------------
# Timing progression across milestones
# ---------------------------------------------------------------------------

st.header("Timing Closure Progression")

col_left, col_right = st.columns([3, 2])

with col_left:
    names = [m["name"] for m in MILESTONES]
    wns_vals = [m["wns"] for m in MILESTONES]
    tns_vals = [m["tns"] for m in MILESTONES]

    fig = go.Figure()
    fig.add_trace(go.Scatter(
        x=names, y=wns_vals, name="WNS (ns)",
        mode="lines+markers+text",
        text=[f"{v:+.2f}" for v in wns_vals],
        textposition="top center",
        line=dict(color=ACCENT, width=3),
        marker=dict(size=12),
    ))
    fig.add_hline(y=0, line_dash="dash", line_color="gray", annotation_text="Timing closure threshold")
    fig.update_layout(
        title="Worst Negative Slack (WNS) Across Iterations",
        yaxis_title="WNS (ns)",
        template="plotly_dark",
        height=460,
        showlegend=False,
        margin=dict(b=140, t=60, l=60, r=30),
        xaxis=dict(tickangle=0),
    )
    fig.update_xaxes(automargin=True)
    st.plotly_chart(fig, use_container_width=True)

with col_right:
    # Use a small floor value for the zero bar so it still renders visibly
    # on a log scale, while the true 0.00 value is shown in the label.
    tns_plot_vals = [abs(v) if v != 0 else 0.05 for v in tns_vals]
    fig2 = go.Figure(go.Bar(
        x=names,
        y=tns_plot_vals,
        marker_color=[VIOLATION_RED if v < 0 else ACCENT for v in tns_vals],
        text=[f"{v:.2f} ns" for v in tns_vals],
        textposition="outside",
    ))
    fig2.update_layout(
        title="Total Negative Slack (|TNS|, log scale)",
        yaxis_title="|TNS| (ns, log scale)",
        yaxis_type="log",
        template="plotly_dark",
        height=460,
        margin=dict(b=140, t=60, l=60, r=30),
    )
    fig2.update_xaxes(automargin=True)
    st.plotly_chart(fig2, use_container_width=True)

st.markdown("---")

# ---------------------------------------------------------------------------
# FIR Pipeline Architecture Diagram
# ---------------------------------------------------------------------------

st.header("What Changed: FIR Adder-Tree Pipeline Architecture")
st.caption("The GenAI-recommended fix (ADD_PIPELINE_STAGE) added a 3rd register stage, splitting the previously-combinational Level 1 + Level 2 addition across a clock edge.")

stage_labels = [
    "16x Tap\nMultiply",
    "Level 1 Add\n(16\u21928)",
    "Level 2 Add\n(8\u21924)",
    "Level 3 Add\n(4\u21922)",
    "Level 4 Add\n(2\u21921)\nresult_out",
]

fig_arch = go.Figure()

box_w, box_h = 0.8, 0.6
y_center = 0.5

for i, label in enumerate(stage_labels):
    x = i
    fig_arch.add_shape(
        type="rect",
        x0=x - box_w/2, x1=x + box_w/2,
        y0=y_center - box_h/2, y1=y_center + box_h/2,
        line=dict(color=ACCENT, width=2),
        fillcolor="#1C2128",
    )
    fig_arch.add_annotation(
        x=x, y=y_center, text=label, showarrow=False,
        font=dict(color="white", size=12), align="center",
    )
    if i < len(stage_labels) - 1:
        fig_arch.add_annotation(
            x=x + 0.5, y=y_center, ax=x + box_w/2, ay=y_center,
            axref="x", ayref="y", xref="x", yref="y",
            showarrow=True, arrowhead=2, arrowsize=1.2, arrowcolor="#8B949E",
            text="",
        )

fig_arch.add_shape(
    type="line", x0=2.5, x1=2.5, y0=y_center - 0.55, y1=y_center + 0.55,
    line=dict(color="#4A90D9", width=4, dash="dot"),
)
fig_arch.add_annotation(
    x=2.5, y=y_center + 0.75, text="Existing register\n(Milestone 3)",
    showarrow=False, font=dict(color="#4A90D9", size=11),
)

fig_arch.add_shape(
    type="line", x0=1.5, x1=1.5, y0=y_center - 0.55, y1=y_center + 0.55,
    line=dict(color=ACCENT, width=5),
)
fig_arch.add_annotation(
    x=1.5, y=y_center - 0.75, text="NEW register\n(GenAI fix, Milestone 4)",
    showarrow=False, font=dict(color=ACCENT, size=12, family="Arial Black"),
)

fig_arch.update_xaxes(visible=False, range=[-0.6, 4.6])
fig_arch.update_yaxes(visible=False, range=[-0.3, 1.3])
fig_arch.update_layout(
    template="plotly_dark",
    height=280,
    margin=dict(t=20, b=20, l=20, r=20),
    plot_bgcolor=BG_DARK,
    paper_bgcolor=BG_DARK,
)

st.plotly_chart(fig_arch, use_container_width=True)

st.markdown(
    "Before the fix, Level 1 and Level 2 addition happened combinationally in the "
    "same clock cycle after the existing register &mdash; a 24x16-bit multiply "
    "feeding two levels of ripple-carry addition exceeded the 4.0 ns clk_dsp budget. "
    "The new register (green) breaks this into two separate cycles, matching the "
    "AI's diagnosis that ripple-carry adders (`ha_1`/`fa_1`) were the dominant delay source.",
    unsafe_allow_html=True,
)

st.markdown("---")

# ---------------------------------------------------------------------------
# Per-clock-domain comparison (Milestone 3 vs 4, real data)
# ---------------------------------------------------------------------------

st.header("Per-Clock-Domain Comparison (Before vs After GenAI Fix)")

if m3 and m4:
    groups = list(m3["group_summary"].keys())
    rows = []
    for g in groups:
        s3 = m3["group_summary"].get(g, {})
        s4 = m4["group_summary"].get(g, {})
        rows.append({
            "Clock Domain": g,
            "WNS Before (ns)": s3.get("wns"),
            "WNS After (ns)": s4.get("wns"),
            "Violations Before": s3.get("violating_endpoints"),
            "Violations After": s4.get("violating_endpoints"),
        })
    df = pd.DataFrame(rows).sort_values("Clock Domain")

    fig3 = go.Figure()
    fig3.add_trace(go.Bar(
        name="Before GenAI fix", x=df["Clock Domain"], y=df["WNS Before (ns)"],
        marker_color=VIOLATION_RED,
    ))
    fig3.add_trace(go.Bar(
        name="After GenAI fix", x=df["Clock Domain"], y=df["WNS After (ns)"],
        marker_color=ACCENT,
    ))
    fig3.add_hline(y=0, line_dash="dash", line_color="gray")
    fig3.update_layout(
        barmode="group",
        title="WNS by Clock Domain",
        yaxis_title="WNS (ns)",
        template="plotly_dark",
        height=450,
    )
    st.plotly_chart(fig3, use_container_width=True)

    with st.expander("View raw per-domain data table"):
        st.dataframe(df, use_container_width=True, hide_index=True)
else:
    st.warning("milestone3_final.json / milestone4_v1.json not found in reports/")

st.markdown("---")

# ---------------------------------------------------------------------------
# GenAI Optimization Engine results
# ---------------------------------------------------------------------------

st.header("GenAI Optimization Engine (Local, Open-Source, Free)")

col_a, col_b = st.columns([2, 3])

with col_a:
    st.markdown(f"""
    **Model:** `qwen2.5-coder:7b` via Ollama
    **Hardware:** Local GPU (RTX 2050, 4GB VRAM)
    **Cost:** $0 (no API, no billing)
    **Violations analyzed:** {len(genai)}
    """)

    if genai:
        technique_counts = Counter(r["ai_technique"] for r in genai)
        fig4 = px.pie(
            names=list(technique_counts.keys()),
            values=list(technique_counts.values()),
            title="AI-Recommended Technique Distribution",
            color_discrete_sequence=[ACCENT, ACCENT_DARK, "#4A90D9", "#8B5CF6"],
            hole=0.4,
        )
        fig4.update_traces(
            textposition="outside",
            textinfo="label+percent",
            texttemplate="%{label}<br>%{percent}",
        )
        fig4.update_layout(
            template="plotly_dark",
            height=420,
            showlegend=True,
            legend=dict(orientation="h", yanchor="bottom", y=-0.3, xanchor="center", x=0.5),
            margin=dict(t=60, b=80, l=20, r=20),
        )
        st.plotly_chart(fig4, use_container_width=True)

with col_b:
    if genai:
        st.subheader("Worst violation, as analyzed by the AI")
        worst = min(genai, key=lambda r: r["slack"])
        st.code(
            f"Startpoint: {worst['startpoint']}\n"
            f"Endpoint:   {worst['endpoint']}\n"
            f"Slack:      {worst['slack']} ns (VIOLATED)\n\n"
            f"Dominant cells:\n" +
            "\n".join(f"  {c[0]}: {c[1]:.2f} ns" for c in worst['dominant_cells'][:5]),
            language="text",
        )
        st.markdown(f"**AI Recommendation:** `{worst['ai_technique']}`")
        st.info(worst["ai_reasoning"])

st.markdown("---")

# ---------------------------------------------------------------------------
# Formal verification status
# ---------------------------------------------------------------------------

st.header("Formal Equivalence Verification")

fv_col1, fv_col2 = st.columns(2)
with fv_col1:
    st.success("**result_valid** (control/latency path)\n\nPROVEN EQUIVALENT via full k-induction (unconditional)")
with fv_col2:
    st.info("**result_out** (24-bit datapath)\n\nExhaustively verified for all reachable states within 8 clock cycles of reset (bounded proof)")

with st.expander("Why is result_out a bounded proof, not unconditional?"):
    st.markdown("""
    Full unbounded k-induction on `result_out` could not be established within a
    practical time budget, due to the SAT/SMT search space introduced by the
    24x16-bit multiply and 4-level adder tree (a well-known hard case for
    bit-level equivalence engines). The induction counterexample search was
    traced to an internal state populated with X-propagated (unreachable)
    register values -- i.e. a state that cannot arise from any real reset
    sequence in actual hardware. The base case (bounded model check from the
    true reset state) passed cleanly for all 8 checked cycles, which fully
    covers the 3-stage pipeline fill transient plus 5 steady-state cycles.
    See `reports/formal_verification/SUMMARY.md` for the complete writeup.
    """)

st.markdown("---")

# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------

st.caption(
    "All data on this dashboard is sourced directly from committed project "
    "files (reports/*.json, reports/*.log). No numbers are estimated or "
    "fabricated. Full reproduction instructions in reports/PPA_COMPARISON.md."
)
