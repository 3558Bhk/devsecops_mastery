"""Generate + verify the OTLP/JSON payloads embedded in lab docker-compose files.

Payload structure lives in tpl/*.json as ordinary, readable JSON — no nesting is
hand-written in Python, which is where bracket-counting bugs come from.

This script:
  1. loads each template and asserts it is valid JSON
  2. compacts it to one line
  3. wraps every $PLACEHOLDER in shell quote-breaks so it can sit inside a
     single-quoted curl `-d '...'` argument
  4. emulates compose ($$ -> $) and ash expansion, and re-parses the result to
     prove the round trip yields valid OTLP JSON

Usage:  python3 gen_payloads.py [outfile.json]
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TPL = os.path.join(HERE, "tpl")

TRACE_ID = "5b8efff798038103d269b633813fc60c"
SPAN_ID = "eee19b7ec3c1b174"

# Values used when emulating an expansion (the "error" branch of the lab loop).
SAMPLE = {
    "$CODE": "500",
    "$STATUS": "2",
    "$TS": "1758000000000000000",
    "$START": "1758000000000000000",
    "$END": "1758000000137000000",
    "$SEV": "17",
    "$SEVTXT": "ERROR",
    "$I": "7",
    "$TRACEID": TRACE_ID,
    "$SPANID": SPAN_ID,
}


def _alt():
    """Alternation of all placeholders, longest first.

    ★ Built once and applied in a SINGLE regex pass. Doing sequential str.replace
      calls is a real bug: $SEV is a prefix of $SEVTXT, so a pass for $SEV rewrites
      the inside of $SEVTXT and corrupts it. One pass with longest-first alternation
      makes prefix collisions impossible.
    """
    keys = sorted(SAMPLE, key=len, reverse=True)
    return re.compile("|".join(re.escape(k) for k in keys))


_ALT = _alt()


def shelljson(obj):
    """Compact JSON, then quote-break every $PLACEHOLDER for shell inlining.

    '{"a":"'"$CODE"'"}'  ->  the shell produces  {"a":"500"}
    """
    j = json.dumps(obj, separators=(",", ":"))
    return _ALT.sub(lambda m: "'" + '"' + m.group(0) + '"' + "'", j)


def emulate(blob):
    """Apply compose ($$ -> $) then ash expansion + quote rejoin."""
    t = blob.replace("$$", "$")
    t = _ALT.sub(lambda m: SAMPLE[m.group(0)], t)
    return re.sub(r"""'"([^']*)"'""", r"\1", t)


def kind_of(obj):
    if "resourceSpans" in obj:
        return "traces"
    if "resourceMetrics" in obj:
        return "metrics"
    if "resourceLogs" in obj:
        return "logs"
    return "?"


def describe(obj):
    k = kind_of(obj)
    if k == "traces":
        sp = obj["resourceSpans"][0]["scopeSpans"][0]["spans"][0]
        return ("name=%r status.code=%s http.response.status_code=%s"
                % (sp["name"], sp["status"]["code"],
                   [a["value"]["intValue"] for a in sp["attributes"]
                    if a["key"] == "http.response.status_code"][0]))
    if k == "metrics":
        m = obj["resourceMetrics"][0]["scopeMetrics"][0]["metrics"][0]
        dp = m["sum"]["dataPoints"][0]
        return ("name=%s unit=%s temporality=%s(2=CUMULATIVE) asInt=%s ts=%s"
                % (m["name"], m["unit"], m["sum"]["aggregationTemporality"],
                   dp["asInt"], dp["timeUnixNano"]))
    lr = obj["resourceLogs"][0]["scopeLogs"][0]["logRecords"][0]
    return ("sev=%s/%s traceId=%s... body=%r"
            % (lr["severityNumber"], lr["severityText"],
               lr.get("traceId", "-")[:16], lr["body"]["stringValue"]))


def main():
    names = ["traces", "metrics", "logs"]
    payloads = {}

    print("=== loading templates ===")
    for n in names:
        path = os.path.join(TPL, n + ".json")
        with open(path) as f:
            obj = json.load(f)          # raises if the template is malformed
        payloads[n] = shelljson(obj)
        print("  %-8s template valid -> %d chars single-line" % (n, len(payloads[n])))

    print("\n=== round-trip verification (compose $$->$ , ash expansion, re-parse) ===")
    ok = True
    for n in names:
        try:
            obj = json.loads(emulate(payloads[n]))
            print("  %-8s VALID (%s)  %s" % (n, kind_of(obj), describe(obj)))
        except Exception as exc:                       # pragma: no cover
            ok = False
            print("  %-8s INVALID -> %s" % (n, exc))
            print("    " + emulate(payloads[n])[:300])

    if not ok:
        sys.exit(1)

    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "payloads.json")
    with open(out, "w") as f:
        json.dump(payloads, f, indent=1)
    print("\nwrote %s" % out)
    print("\nPaste each value as the single-quoted argument to curl -d inside a")
    print("compose `command:` block, and write $$VAR (not $VAR) so compose emits")
    print("a literal $ for the shell to expand.")


if __name__ == "__main__":
    main()
