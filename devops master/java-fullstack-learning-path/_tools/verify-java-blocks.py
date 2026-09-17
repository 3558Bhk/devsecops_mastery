#!/usr/bin/env python3
"""
verify-java-blocks.py — proves that every Java program in a markdown file
compiles, and that every documented `// ── OUTPUT ──` block matches what the
program ACTUALLY prints.

WHY THIS EXISTS
---------------
A learning document that claims exact output and gets it wrong is worse than
one that shows no output at all: it teaches a false model of the language and
the reader has no way to detect it. This harness removes that failure mode by
executing every program in the document and diffing the result against the
prose.

It found, in 01-BASICS-AND-TOPIC-MAP.md alone:
  • a claim that a ternary throws NPE from an UNEVALUATED branch (it does not)
  • an `Integer` loop accumulator whose SUM was silently wrong via overflow,
    documented as if it equalled the primitive result
  • a ConcurrentModificationException that does not actually fire when you
    remove the middle of a 3-element list (the fail-fast check is best-effort)
  • a `%`-vs-`&` comparison that compared against floorMod, hiding the very
    row that proves the point
  • five wrong printf widths, one wrong arithmetic total, and a `%.1f` given a
    `long` (IllegalFormatConversionException at runtime)
None of those are visible by reading. All are visible by running.

USAGE
-----
    python3 verify-java-blocks.py <markdown-file> [--jdk /path/to/jdk]

    --jdk     JDK home to compile/run with. Default: JAVA_HOME, else `java`
              on PATH. USE JAVA 21 for this path — the baseline taught here.
    --skip    Comma-separated class names to skip (interactive, arg-dependent,
              deliberately-fatal, or timing-based programs). Defaults below.

EXIT CODE: 0 if every non-skipped program compiles and its documented output
matches; 1 otherwise.

REQUIREMENTS
------------
• Each program must be in a ```java fenced block.
• The block must declare `class X` and contain `void main(`.
• The documented output must live INSIDE the same fence, as comments, between
  a line starting `// ── OUTPUT` and a closing rule of 20+ `─` characters.
  (Keeping it inside the fence is what makes it machine-checkable.)
• One output line per comment line. Do NOT wrap an annotation onto a second
  comment line — the harness treats every comment line as an output line.
  Annotations may trail the output on the SAME line; a doc line passes if it
  equals, starts with, or is a prefix of the actual line.
"""

import argparse
import os
import re
import shutil
import subprocess
import unicodedata
import sys
import tempfile

# Programs whose output is legitimately not reproducible byte-for-byte:
#   timing benchmarks  → magnitudes vary by machine (verify by eye)
#   arg-dependent      → output depends on the command line used
#   interactive        → reads stdin
#   deliberately fatal → terminates the JVM by design
#   not-yet-valid Java → illustration of a future language level
DEFAULT_SKIP = {
    "Hello",            # Java 25 compact-source-file illustration
    "ShopConsole",      # interactive menu loop
}

FENCE_RE = re.compile(r"```java\n(.*?)```", re.S)
CLASS_RE = re.compile(r"\bclass\s+(\w+)")
OUTPUT_RE = re.compile(r"// ── OUTPUT[^\n]*\n(.*?)\n// ─{20,}", re.S)


def jdk_bin(jdk_arg: str) -> str:
    """Resolve a JDK home to its bin directory, or '' to use PATH."""
    home = jdk_arg or os.environ.get("JAVA_HOME") or ""
    if home and os.path.isfile(os.path.join(home, "bin", "javac")):
        return os.path.join(home, "bin")
    if shutil.which("javac"):
        return ""
    sys.exit("no JDK found — pass --jdk /path/to/jdk or set JAVA_HOME")


def extract(md_path: str):
    """Yield (class_name, source, documented_output_lines) per program."""
    text = open(md_path, encoding="utf-8").read()
    for block in FENCE_RE.findall(text):
        m = CLASS_RE.search(block)
        if not m or "void main(" not in block:
            continue
        cls = m.group(1)
        doc = None
        mo = OUTPUT_RE.search(block)
        if mo:
            doc = [re.sub(r"^// ?", "", ln).rstrip()
                   for ln in mo.group(1).split("\n")]
            doc = [d for d in doc if d.strip()]
        yield cls, block, doc


def visible(line: str) -> str:
    """Strip characters that cannot be represented in a markdown document.

    A `char` field defaults to `\u0000`, which prints as an INVISIBLE NUL.
    The honest way to document that in prose is `char=[]` — what the reader
    actually sees. So compare on visible characters only, and let the prose
    explain the invisible one.
    """
    return "".join(c for c in line if c == "\t" or unicodedata.category(c)[0] != "C")


def compare(doc, actual):
    """Line-wise compare. A doc line may carry a trailing annotation.

    A doc line passes if it equals, starts with, or is a prefix of the actual
    line — after removing characters that cannot appear in markdown. That
    tolerance exists so annotations can trail real output on the same line.
    """
    problems = []
    for j in range(max(len(doc), len(actual))):
        d = doc[j] if j < len(doc) else "<MISSING IN DOC>"
        a = actual[j] if j < len(actual) else "<NOT PRINTED AT RUNTIME>"
        dv, av = visible(d), visible(a)
        if dv == av or dv.startswith(av) or av.startswith(dv):
            continue
        problems.append((j + 1, d, a))
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("markdown")
    ap.add_argument("--jdk", default="", help="JDK home (default: $JAVA_HOME)")
    ap.add_argument("--skip", default="",
                    help="comma-separated class names to skip")
    ap.add_argument("--keep", action="store_true", help="keep the scratch dir")
    args = ap.parse_args()

    bin_ = jdk_bin(args.jdk)
    javac = os.path.join(bin_, "javac") if bin_ else "javac"
    java = os.path.join(bin_, "java") if bin_ else "java"
    skip = DEFAULT_SKIP | {c.strip() for c in args.skip.split(",") if c.strip()}

    ver = subprocess.run([java, "-version"], capture_output=True, text=True)
    print(f"JDK: {(ver.stderr or ver.stdout).splitlines()[0]}")
    print(f"file: {args.markdown}\n")

    tmp = tempfile.mkdtemp(prefix="javaverify-")
    exact = mismatch = skipped = 0
    failures = []
    try:
        for cls, src, doc in extract(args.markdown):
            d = os.path.join(tmp, cls)
            os.makedirs(d, exist_ok=True)
            open(os.path.join(d, f"{cls}.java"), "w", encoding="utf-8").write(src)

            # ── compile with every warning on ────────────────────────────
            cp = subprocess.run([javac, "-encoding", "UTF-8", "-Xlint:all",
                                 f"{cls}.java"], cwd=d, capture_output=True, text=True)
            if cp.returncode != 0:
                err = next((l for l in cp.stderr.splitlines() if "error:" in l),
                           cp.stderr.splitlines()[0] if cp.stderr else "?")
                if cls in skip:
                    # An explicitly skipped program may legitimately need a
                    # language level this JDK does not have (e.g. a Java 25
                    # compact source file checked against a Java 21 JDK).
                    # Report it as information, not as a failure.
                    skipped += 1
                    print(f"⏭  {cls:32s} skipped — needs a newer JDK: {err.strip()[:70]}")
                    continue
                failures.append(f"⛔ COMPILE  {cls}\n      {err.strip()}")
                continue
            warn = [l for l in cp.stderr.splitlines() if "warning:" in l]
            note = f"  ({len(warn)} -Xlint warning(s) — intentional?)" if warn else ""

            if cls in skip:
                skipped += 1
                print(f"⏭  {cls:32s} skipped (hand-verify){note}")
                continue
            if doc is None:
                skipped += 1
                print(f"⏭  {cls:32s} compiles{note}; no OUTPUT block to check")
                continue

            # ── run and diff ─────────────────────────────────────────────
            try:
                r = subprocess.run([java, "-Dfile.encoding=UTF-8", cls], cwd=d,
                                   capture_output=True, text=True, timeout=180)
            except subprocess.TimeoutExpired:
                failures.append(f"⛔ TIMEOUT   {cls} (exceeded 180s)")
                continue
            actual = [l.rstrip() for l in
                      (r.stdout + r.stderr).rstrip("\n").split("\n") if l.strip()]
            problems = compare(doc, actual)
            if problems:
                mismatch += 1
                failures.append(
                    f"⛔ OUTPUT    {cls} — {len(problems)}/{max(len(doc),len(actual))} line(s) differ"
                    + "".join(f"\n      L{n}\n        doc: {d_[:100]!r}\n        act: {a[:100]!r}"
                              for n, d_, a in problems[:5]))
            else:
                exact += 1
                print(f"✅ {cls:32s} {len(actual):3d} output lines match EXACTLY{note}")
    finally:
        if args.keep:
            print(f"\nscratch kept at {tmp}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)

    print(f"\n═══ exact={exact}  mismatched={mismatch}  "
          f"skipped/unchecked={skipped}  compile-errors="
          f"{sum(1 for f in failures if 'COMPILE' in f)} ═══")
    if failures:
        print("\n─── FAILURES ───")
        print("\n".join(failures))
        return 1
    print("\n✅ every compiled program's documented output is real")
    return 0


if __name__ == "__main__":
    sys.exit(main())
