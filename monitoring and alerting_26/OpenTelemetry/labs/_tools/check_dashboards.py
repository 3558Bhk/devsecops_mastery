#!/usr/bin/env python3
"""Parse-check every PromQL expression in every lab Grafana dashboard.

Extracts each panel target's `expr` and validates it according to the panel's
DATASOURCE TYPE:

  * prometheus -> wrapped as synthetic Prometheus recording rules and checked
                  with `promtool check rules`. Catches syntax errors (bad
                  brackets, wrong function arity) with no server needed.
  * loki       -> LogQL. promtool cannot parse it, so these are structurally
                  checked instead: balanced braces/backticks/quotes, and no
                  unescaped Grafana variable in a position LogQL can't take.

It does NOT verify that metric or label names exist — only that the expressions
parse. Run it after editing any dashboard JSON.

Usage:  python3 labs/_tools/check_dashboards.py
"""
import json, glob, os, subprocess, sys, tempfile

PROMTOOL = "/home/user/.tools/prometheus-3.14.0/promtool"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def collect(path):
    """Return (dashboard, [(panel_id, refId, expr, datasource_type), ...])."""
    d = json.load(open(path))
    out = []

    def walk(panels, inherited=None):
        for p in panels:
            # A row panel carries no datasource; targets inherit the panel's.
            ds = p.get("datasource")
            dtype = None
            if isinstance(ds, dict):
                dtype = ds.get("type")
            elif isinstance(ds, str):
                dtype = ds
            dtype = dtype or inherited
            for t in (p.get("targets") or []):
                if t.get("expr"):
                    tds = t.get("datasource")
                    ttype = tds.get("type") if isinstance(tds, dict) else tds
                    out.append((p.get("id"), t.get("refId"), t["expr"],
                                ttype or dtype or "prometheus"))
            if p.get("panels"):
                walk(p["panels"], dtype)

    walk(d["panels"])
    return d, out


def check_logql(expr):
    """Structural check for LogQL. Returns an error string, or None if it looks fine."""
    problems = []
    if expr.count("{") != expr.count("}"):
        problems.append("unbalanced braces (%d '{' vs %d '}')"
                        % (expr.count("{"), expr.count("}")))
    if expr.count("`") % 2:
        problems.append("odd number of backticks")
    if expr.count('"') % 2:
        problems.append("odd number of double quotes")
    # LogQL stream selectors need at least one label matcher inside {}.
    if "{" in expr:
        head = expr.split("{", 1)[1].split("}", 1)[0]
        if not head.strip() and not head.strip().startswith("~"):
            problems.append("empty label matcher in stream selector")
    # A bare Grafana variable interpolation is fine in dashboards but is a smell
    # in a provisioned dashboard nobody will fill in.
    if "${__" not in expr and "$" in expr:
        problems.append("stray '$' that is not a Grafana macro")
    return "; ".join(problems) if problems else None


def main():
    dashboards = sorted(glob.glob(os.path.join(ROOT, "*/grafana/provisioning/dashboards/*.json")))
    if not dashboards:
        print("no dashboards found under", ROOT)
        return 1
    if not os.path.exists(PROMTOOL):
        print("promtool not found at", PROMTOOL)
        return 1

    failures = 0
    total = 0
    tmp = tempfile.mkdtemp()
    for f in dashboards:
        lab = f.split("/labs/")[1].split("/")[0]
        d, items = collect(f)
        dup_panel_ids = {p.get("id") for p in d["panels"]
                         if [q.get("id") for q in d["panels"]].count(p.get("id")) > 1}
        if dup_panel_ids:
            print("  !! %s duplicate panel ids: %s" % (lab, dup_panel_ids))
            failures += 1

        if not items:
            print("  -- %s: no targets" % lab)
            continue

        # Split by datasource type: promtool only understands PromQL.
        prom = [(pid, rid, e) for pid, rid, e, t in items if t == "prometheus"]
        logq = [(pid, rid, e) for pid, rid, e, t in items if t == "loki"]
        other = [(pid, rid, e, t) for pid, rid, e, t in items
                 if t not in ("prometheus", "loki")]

        total += len(items)
        bad = []

        # --- PromQL via promtool -------------------------------------------
        if prom:
            lines = ["groups:", "  - name: %s" % lab, "    rules:"]
            for n, (pid, rid, e) in enumerate(prom):
                lines.append("      - record: check_%d" % n)
                lines.append("        expr: %s" % json.dumps(e))
            rp = os.path.join(tmp, "%s.yaml" % lab)
            open(rp, "w").write("\n".join(lines) + "\n")
            r = subprocess.run([PROMTOOL, "check", "rules", rp],
                               capture_output=True, text=True)
            if r.returncode != 0:
                bad.append("promtool: " + (r.stderr or r.stdout).strip())

        # --- LogQL, structural --------------------------------------------
        for pid, rid, e in logq:
            err = check_logql(e)
            if err:
                bad.append("LogQL panel %s/%s: %s" % (pid, rid, err))

        for pid, rid, e, t in other:
            bad.append("panel %s/%s: unsupported datasource type %r" % (pid, rid, t))

        summary = "%2d PromQL, %2d LogQL" % (len(prom), len(logq))
        if other:
            summary += ", %d other" % len(other)
        if bad:
            failures += 1
            print("  FAIL %-40s %s" % (lab, summary))
            for b in bad:
                print("       " + b.replace("\n", "\n       "))
        else:
            print("  OK   %-40s %s" % (lab, summary))

    print("\n%d expressions checked across %d dashboards; %d failures"
          % (total, len(dashboards), failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
