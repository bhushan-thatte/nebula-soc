"""
Nebula SoC — OpenSTA Timing Report Parser
==========================================
Parses `report_checks` text output into structured Python objects / JSON,
for consumption by the GenAI RTL optimization engine (Week 2/3).

USAGE:
    report_checks -path_delay max -group_path_count 9999 \
        -endpoint_path_count 1 -unique_paths_to_endpoint \
        -fields {slack} > timing_report.rpt

    python3 timing_parser.py timing_report.rpt --json out.json --summary
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional


@dataclass
class DelayLine:
    incr_delay: float
    cumulative_time: float
    direction: Optional[str]
    pin: Optional[str]
    cell_type: Optional[str]
    description: str


@dataclass
class TimingPath:
    startpoint: str
    startpoint_clock: str
    endpoint: str
    endpoint_clock: str
    path_group: str
    path_type: str
    check_type: str
    slack: float
    status: str
    data_arrival_time: Optional[float]
    data_required_time: Optional[float]
    delay_lines: list[DelayLine] = field(default_factory=list)

    @property
    def is_violated(self) -> bool:
        return self.status == "VIOLATED"

    @property
    def is_cross_domain(self) -> bool:
        return self.startpoint_clock != self.endpoint_clock

    @property
    def dominant_cells(self) -> list[tuple[str, float]]:
        totals: dict[str, float] = {}
        for line in self.delay_lines:
            if line.cell_type:
                totals[line.cell_type] = totals.get(line.cell_type, 0.0) + line.incr_delay
        return sorted(totals.items(), key=lambda kv: kv[1], reverse=True)

    def to_dict(self) -> dict:
        d = asdict(self)
        d["is_violated"] = self.is_violated
        d["is_cross_domain"] = self.is_cross_domain
        d["dominant_cells"] = self.dominant_cells
        return d


@dataclass
class TimingReport:
    paths: list[TimingPath] = field(default_factory=list)

    def violated(self) -> list[TimingPath]:
        return [p for p in self.paths if p.is_violated]

    def by_group(self, group: str) -> list[TimingPath]:
        return [p for p in self.paths if p.path_group == group]

    def groups(self) -> list[str]:
        seen = []
        for p in self.paths:
            if p.path_group not in seen:
                seen.append(p.path_group)
        return seen

    def group_summary(self) -> dict[str, dict]:
        summary: dict[str, dict] = {}
        for grp in self.groups():
            grp_paths = self.by_group(grp)
            viol = [p for p in grp_paths if p.is_violated]
            summary[grp] = {
                "total_endpoints": len(grp_paths),
                "violating_endpoints": len(viol),
                "wns": min((p.slack for p in grp_paths), default=None),
                "tns": round(sum(p.slack for p in viol), 4) if viol else 0.0,
                "check_types": sorted({p.check_type for p in viol}),
            }
        return summary

    def likely_false_violations(self) -> list[TimingPath]:
        out = []
        for p in self.violated():
            if p.check_type in ("recovery", "removal") and re.search(
                r"rst|reset", p.startpoint, re.IGNORECASE
            ):
                out.append(p)
        return out

    def genuine_setup_violations(self) -> list[TimingPath]:
        return [
            p for p in self.violated()
            if p.check_type == "setup" and p.path_group != "asynchronous"
        ]

    def to_dict(self) -> dict:
        return {
            "group_summary": self.group_summary(),
            "likely_false_violations": [p.to_dict() for p in self.likely_false_violations()],
            "genuine_setup_violations": [p.to_dict() for p in self.genuine_setup_violations()],
            "all_paths": [p.to_dict() for p in self.paths],
        }


_STARTPOINT_RE = re.compile(r"^Startpoint:\s*(\S+)")
_ENDPOINT_RE = re.compile(r"^Endpoint:\s*(\S+)")
_CLOCK_INFO_RE = re.compile(
    r"clocked by (\S+?)\)|check against (?:rising|falling)-edge clock (\S+?)\)"
)
_PATH_GROUP_RE = re.compile(r"^Path Group:\s*(\S+)")
_PATH_TYPE_RE = re.compile(r"^Path Type:\s*(\S+)")
_SLACK_RE = re.compile(r"^\s*(-?[0-9.]+)\s+slack \((VIOLATED|MET)\)")
_ARRIVAL_RE = re.compile(r"^\s*(-?[0-9.]+)\s+data arrival time")
_REQUIRED_RE = re.compile(r"^\s*(-?[0-9.]+)\s+data required time")
_DELAY_ROW_RE = re.compile(r"^\s*(-?[0-9.]+)\s+(-?[0-9.]+)\s*([\^v])?\s*(.*)$")
_PIN_CELL_RE = re.compile(r"^(\S+)\s+\(([^)]+)\)\s*$")


def _extract_clock(header_block: str) -> str:
    m = _CLOCK_INFO_RE.search(header_block)
    if not m:
        return "unknown"
    return m.group(1) or m.group(2) or "unknown"


def _classify_check_type(endpoint_header_block: str) -> str:
    if "recovery check" in endpoint_header_block:
        return "recovery"
    if "removal check" in endpoint_header_block:
        return "removal"
    if "hold" in endpoint_header_block.lower():
        return "hold"
    if "edge-triggered flip-flop" in endpoint_header_block:
        return "setup"
    return "unknown"


def parse_timing_report(text: str) -> TimingReport:
    blocks = re.split(r"\n(?=Startpoint:)", text)
    report = TimingReport()

    for block in blocks:
        block = block.strip("\n")
        if not block.startswith("Startpoint:"):
            continue

        lines = block.splitlines()
        startpoint_match = _STARTPOINT_RE.match(lines[0])
        if not startpoint_match:
            continue
        startpoint = startpoint_match.group(1)

        startpoint_clock_line = lines[1] if len(lines) > 1 else ""
        startpoint_clock = _extract_clock(startpoint_clock_line)

        endpoint = None
        endpoint_clock = "unknown"
        check_type = "unknown"
        path_group = "unknown"
        path_type = "max"

        idx = 0
        for i, line in enumerate(lines):
            m = _ENDPOINT_RE.match(line)
            if m:
                endpoint = m.group(1)
                endpoint_header_block = line
                if i + 1 < len(lines):
                    endpoint_header_block += " " + lines[i + 1]
                endpoint_clock = _extract_clock(endpoint_header_block)
                check_type = _classify_check_type(endpoint_header_block)
                idx = i
                break

        for line in lines[idx:]:
            m = _PATH_GROUP_RE.match(line)
            if m:
                path_group = m.group(1)
            m = _PATH_TYPE_RE.match(line)
            if m:
                path_type = m.group(1)

        slack_val = None
        status = None
        arrival = None
        required = None
        for line in lines:
            m = _SLACK_RE.match(line)
            if m:
                slack_val = float(m.group(1))
                status = m.group(2)
            m = _ARRIVAL_RE.match(line)
            if m and arrival is None:
                arrival = float(m.group(1))
            m = _REQUIRED_RE.match(line)
            if m and required is None:
                required = float(m.group(1))

        if endpoint is None or slack_val is None or status is None:
            continue

        delay_lines: list[DelayLine] = []
        in_table = False
        for line in lines:
            if line.strip().startswith("Delay") and "Description" in line:
                in_table = True
                continue
            if not in_table:
                continue
            if line.strip().startswith("---"):
                continue
            if "data arrival time" in line or "data required time" in line:
                break
            m = _DELAY_ROW_RE.match(line)
            if not m:
                continue
            incr, cum, direction, rest = m.groups()
            rest = rest.strip()
            if not rest:
                continue
            pin, cell_type = None, None
            pm = _PIN_CELL_RE.match(rest)
            if pm:
                pin, cell_type = pm.group(1), pm.group(2)
            delay_lines.append(
                DelayLine(
                    incr_delay=float(incr),
                    cumulative_time=float(cum),
                    direction=direction,
                    pin=pin,
                    cell_type=cell_type,
                    description=rest,
                )
            )

        report.paths.append(
            TimingPath(
                startpoint=startpoint,
                startpoint_clock=startpoint_clock,
                endpoint=endpoint,
                endpoint_clock=endpoint_clock,
                path_group=path_group,
                path_type=path_type,
                check_type=check_type,
                slack=slack_val,
                status=status,
                data_arrival_time=arrival,
                data_required_time=required,
                delay_lines=delay_lines,
            )
        )

    return report


def main():
    ap = argparse.ArgumentParser(description="Parse OpenSTA report_checks output")
    ap.add_argument("report_file", type=Path)
    ap.add_argument("--json", type=Path, default=None)
    ap.add_argument("--summary", action="store_true")
    args = ap.parse_args()

    text = args.report_file.read_text()
    report = parse_timing_report(text)

    print(f"Parsed {len(report.paths)} timing paths.")
    print()
    print("Per-path-group summary:")
    for grp, s in report.group_summary().items():
        flag = "  <-- has violations" if s["violating_endpoints"] else ""
        print(
            f"  {grp:15s} endpoints={s['total_endpoints']:4d}  "
            f"violating={s['violating_endpoints']:4d}  "
            f"WNS={s['wns']:.2f}  TNS={s['tns']:.2f}"
            f"  types={s['check_types']}{flag}"
        )

    false_viol = report.likely_false_violations()
    if false_viol:
        print()
        print(f"WARNING: {len(false_viol)} likely FALSE violations detected "
              f"(recovery/removal through reset-sync output):")
        for p in false_viol[:5]:
            print(f"    {p.startpoint} -> {p.endpoint}  slack={p.slack}")
        if len(false_viol) > 5:
            print(f"    ... and {len(false_viol) - 5} more")
        print("    Recommended action: add set_false_path -through <reset_sync_output>/Q")

    genuine = report.genuine_setup_violations()
    print()
    print(f"Genuine setup violations for GenAI engine to act on: {len(genuine)}")
    for p in sorted(genuine, key=lambda p: p.slack)[:10]:
        top_cells = p.dominant_cells[:3]
        print(f"    [{p.path_group}] {p.startpoint} -> {p.endpoint}  slack={p.slack}")
        print(f"        dominant cells: {top_cells}")

    if args.json:
        args.json.write_text(json.dumps(report.to_dict(), indent=2))
        print(f"\nWrote structured JSON to {args.json}")


if __name__ == "__main__":
    main()
