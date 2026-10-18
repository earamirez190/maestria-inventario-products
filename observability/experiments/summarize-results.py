#!/usr/bin/env python3
"""Summarize chaos CSV outputs without fabricating observations."""

import csv
import io
import json
import pathlib
import sys
from statistics import mean


def read_csv(path: pathlib.Path):
    rows = []
    lines = path.read_text().splitlines()
    try:
        header_index = lines.index("timestamp,http_code,time_total")
    except ValueError:
        return rows
    payload = "\n".join(lines[header_index:])
    for row in csv.DictReader(io.StringIO(payload)):
        try:
            rows.append({
                "code": int(row["http_code"]),
                "seconds": float(row["time_total"]),
            })
        except (KeyError, TypeError, ValueError):
            continue
    return rows


def summary(path: pathlib.Path):
    rows = read_csv(path)
    durations = sorted(row["seconds"] for row in rows)
    errors = sum(row["code"] >= 500 or row["code"] == 0 for row in rows)
    p95_index = max(0, min(len(durations) - 1, int(len(durations) * 0.95) - 1)) if durations else 0
    return {
        "file": path.name,
        "requests_observed": len(rows),
        "errors": errors,
        "error_rate": round(errors / len(rows), 4) if rows else None,
        "mean_seconds": round(mean(durations), 4) if durations else None,
        "p95_seconds": round(durations[p95_index], 4) if durations else None,
    }


if len(sys.argv) != 2:
    raise SystemExit("usage: summarize-results.py <evidence-directory>")

directory = pathlib.Path(sys.argv[1])
result = {
    "objective": {
        "latency_experiment": "+200 ms in service-b",
        "error_experiment": "10% error rate in data-service",
        "mttd_target_seconds": 120,
    },
    "experiments": [
        summary(directory / "baseline.csv"),
        summary(directory / "latency-200ms.csv"),
        summary(directory / "error-rate-10pct.csv"),
    ],
    "interpretation": "Complete MTTD, SLO and error-budget fields after correlating alert timestamps.",
}
print(json.dumps(result, indent=2, ensure_ascii=False))
