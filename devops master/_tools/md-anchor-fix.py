#!/usr/bin/env python3
"""Verify + repair in-page TOC anchors and relative links in Markdown files.

Slugging follows github-slugger EXACTLY:
    lowercase
    -> strip punctuation / symbols / marks / controls (keeping '-' and '_')
    -> spaces to hyphens ONE-TO-ONE (never collapsed)

That last rule is the one that bites: a heading like

    ## 3 · ⭐ The three repo topologies

loses '·' and '⭐' but KEEPS all three surrounding spaces, so the real slug is
'3---the-three-repo-topologies' (three hyphens), not '3--...'.

Usage:
    md-anchor-fix.py PATH...                      report only
    md-anchor-fix.py --fix PATH...                rewrite resolvable anchors
    md-anchor-fix.py --fix --rebuild-toc PATH...  ALSO rebuild every TOC row
                                                  from the real heading slug

Exit code 1 if any defect remains after the run.
"""
import os
import re
import sys
import unicodedata
import urllib.parse

SKIP_DIRS = {'.git', 'node_modules', '__pycache__', '.venv', 'dist', 'build', '.arena'}


def slug(t):
    """github-slugger, exactly:
         lowercase -> strip regex -> ' ' replaced by '-' ONE-TO-ONE.
    The strip set is Unicode P*, S*, C*, Z* (punctuation, symbols, control/
    format, separators) EXCEPT '-' (U+002D) and '_' (U+005F), which the
    published regex deliberately keeps.
    NOTE: Mn is KEPT. U+FE0F (variation selector) and combining accents are
    NOT in github-slugger's character class, so they survive into the slug.
    That is why '## 10 . U+25B6 U+FE0F Run' slugs to '10--\uFE0F-run-...',
    with TWO hyphens, not three."""
    t = t.strip().lower()
    out = []
    for ch in t:
        if ch == ' ':
            out.append('-')
            continue
        if ch in '-_':
            out.append(ch)
            continue
        if unicodedata.category(ch)[0] in ('P', 'S', 'C', 'Z'):
            continue
        out.append(ch)
    return ''.join(out)


def headings(lines):
    """Ordered [(level, text, slug)] outside code fences, with github's -N dup suffix."""
    heads = []
    occ = {}
    fence = False
    for l in lines:
        if l.startswith('```'):
            fence = not fence
            continue
        if fence:
            continue
        m = re.match(r'^(#{1,6})\s+(.*)$', l)
        if m:
            txt = m.group(2)
            base = slug(txt)
            s = base
            while s in occ:
                occ[base] += 1
                s = f'{base}-{occ[base]}'
            occ.setdefault(base, 0)
            heads.append((len(m.group(1)), txt, s))
    return heads


def _tokens(slugfrag):
    return {t for t in re.split(r'-+', slugfrag) if t and not t.isdigit() == False or t} \
        if False else {t for t in re.split(r'-+', slugfrag) if t}


def best_heading(frag, heads):
    """Map a (possibly stale) anchor fragment to exactly one heading, or None.

    Strategy, most specific first:
      1. numeric section match — 'N U+00B7 Title', 'N. Title', or 'N.M Title'
      2. token-overlap similarity, accepted only when there is a CLEAR winner
    Returns the heading tuple, or None when ambiguous/unmatched.
    """
    mm = re.match(r'^(\d+(?:\.\d+)?)\D', frag + ' ')
    if mm:
        num = mm.group(1)
        if '.' in num:
            cands = [h for h in heads if re.match(r'^' + re.escape(num) + r'\s', h[1])]
        else:
            esc = re.escape(num)
            strict = [h for h in heads if re.match(r'^' + esc + r'\s+\u00b7', h[1])]
            dotted = [h for h in heads if re.match(r'^' + esc + r'\.\s', h[1])]
            bare = [h for h in heads if re.match(r'^' + esc + r'\s', h[1])]
            cands = strict or dotted or bare
        if len(cands) == 1:
            return cands[0]
        if len(cands) > 1:
            # ⭐ ambiguous by number alone (e.g. '## 1. Docker command structure'
            #   AND '### 1. Build'). TOC rows point at the shallowest level, so
            #   prefer the minimum heading level; only if STILL tied, fall
            #   through to token similarity rather than giving up.
            lo = min(h[0] for h in cands)
            cands = [h for h in cands if h[0] == lo]
            if len(cands) == 1:
                return cands[0]

    # ── fallback: token overlap, clear winner only ───────────────────────
    want = {t for t in re.split(r'[^0-9a-z\u00c0-\uffff]+', frag.lower()) if t}
    if len(want) < 2:
        return None
    scored = []
    for h in heads:
        have = {t for t in re.split(r'[^0-9a-z\u00c0-\uffff]+', h[2].lower()) if t}
        if not have:
            continue
        inter = len(want & have)
        scored.append((inter / len(want), inter, h))
    scored.sort(key=lambda x: (-x[0], -x[1]))
    if not scored or scored[0][0] < 0.6:
        return None
    if len(scored) > 1 and scored[1][0] >= scored[0][0] - 1e-9 and scored[1][2] is not scored[0][2]:
        return None                      # ambiguous
    return scored[0][2]


def explicit_anchors(lines):
    out = set()
    fence = False
    for l in lines:
        if l.startswith('```'):
            fence = not fence
            continue
        if fence:
            continue
        a = re.match(r'^<a\s+(?:name|id)="([^"]+)"', l)
        if a:
            out.add(a.group(1))
    return out


_SLUG_CACHE = {}


def slugset_for(path):
    if path in _SLUG_CACHE:
        return _SLUG_CACHE[path]
    if not os.path.exists(path):
        _SLUG_CACHE[path] = None
        return None
    lines = open(path, encoding='utf-8').read().split('\n')
    s = {h[2] for h in headings(lines)} | explicit_anchors(lines)
    _SLUG_CACHE[path] = s
    return s


def process(path, fix):
    src = open(path, encoding='utf-8').read()
    lines = src.split('\n')
    heads = headings(lines)
    known = {h[2] for h in heads} | explicit_anchors(lines)
    rep = {'fence': 0, 'anchor': [], 'link': [], 'xfrag': [], 'fixed': 0}

    nf = sum(1 for l in lines if l.startswith('```'))
    if nf % 2:
        rep['fence'] = nf

    def resolve(frag):
        """Map a stale anchor to a real heading (see best_heading)."""
        h = best_heading(frag, heads)
        return h[2] if h else None

    out = []
    fence = False
    for i, l in enumerate(lines):
        if l.startswith('```'):
            fence = not fence
            out.append(l)
            continue
        if fence:
            out.append(l)
            continue

        def repl(m, lineno=i + 1):
            lbl, tgt = m.group(1), m.group(2)
            t = tgt.strip()
            if t.startswith('#'):
                frag = t[1:]
                if frag in known:
                    return m.group(0)
                new = resolve(frag)
                if new:
                    rep['fixed'] += 1
                    return f'[{lbl}](#{new})'
                rep['anchor'].append((lineno, frag))
                return m.group(0)
            if t.startswith(('http://', 'https://', 'mailto:', '$(')) or '${' in t:
                return m.group(0)
            pathpart = urllib.parse.unquote(t.split('#')[0])
            if pathpart:
                full = os.path.normpath(os.path.join(os.path.dirname(path), pathpart))
                if not os.path.exists(full):
                    rep['link'].append((lineno, t))
                    return m.group(0)
                if '#' in t:
                    fs = slugset_for(full)
                    if fs is not None and t.split('#')[1] not in fs:
                        rep['xfrag'].append((lineno, t))
            return m.group(0)

        out.append(re.sub(r'\[([^\]]*)\]\(([^)]+)\)', repl, l))

    if fix and rep['fixed']:
        open(path, 'w', encoding='utf-8').write('\n'.join(out))
    return rep


def rebuild_toc(path, dry):
    """Rewrite every TOC row '| [N](#frag) |' from the REAL heading slug.

    Unconditional (not 'only if it looks broken'), so it is idempotent and
    self-correcting: it repairs anchors that resolve to a heading but to the
    WRONG one, which a resolution check alone can never detect.
    """
    lines = open(path, encoding='utf-8').read().split('\n')
    heads = headings(lines)
    n = 0; out = []; fence = False; unresolved = []
    row = re.compile(r'^(\s*\|\s*)\[([^\]]*)\]\(#([^)]*)\)(\s*\|.*)$')
    for i, l in enumerate(lines):
        if l.startswith('```'):
            fence = not fence; out.append(l); continue
        if fence:
            out.append(l); continue
        m = row.match(l)
        if not m:
            out.append(l); continue
        pre, lbl, frag, post = m.group(1), m.group(2), m.group(3), m.group(4)
        h = best_heading(frag, heads)
        if h is None:
            unresolved.append((i + 1, frag)); out.append(l); continue
        if h[2] == frag:
            out.append(l); continue
        n += 1
        out.append(f'{pre}[{lbl}](#{h[2]}){post}')
    if n and not dry:
        open(path, 'w', encoding='utf-8').write('\n'.join(out))
    return n, unresolved


def main():
    fix = '--fix' in sys.argv
    rebuild = '--rebuild-toc' in sys.argv
    args = [a for a in sys.argv[1:] if a not in ('--fix', '--rebuild-toc')]
    if not args:
        print(__doc__)
        return 2

    files = []
    for a in args:
        if os.path.isdir(a):
            for r, d, f in os.walk(a):
                d[:] = [x for x in d if x not in SKIP_DIRS]
                files += [os.path.join(r, x) for x in sorted(f) if x.endswith('.md')]
        elif a.endswith('.md'):
            files.append(a)

    tot = {'files': 0, 'fixed': 0, 'fence': 0, 'anchor': 0, 'link': 0, 'xfrag': 0,
           'toc': 0, 'tocunres': 0}
    for p in sorted(set(files)):
        if rebuild:
            n, unres = rebuild_toc(p, not fix)
            tot['toc'] += n; tot['tocunres'] += len(unres)
            if n: print(f"toc {n:3d} anchor(s) rebuilt  {p}")
            for ln, f in unres: print(f"TOC-UNRESOLVED {p}:{ln}  #{f}")
        r = process(p, fix)
        tot['files'] += 1
        tot['fixed'] += r['fixed']
        if r['fence']:
            tot['fence'] += 1
            print(f"ODD-FENCES ({r['fence']})  {p}")
        for k in ('anchor', 'link', 'xfrag'):
            tot[k] += len(r[k])
            for ln, v in r[k]:
                print(f"{k.upper():8} {p}:{ln}  {v}")
        if r['fixed']:
            print(f"fixed {r['fixed']:3d} anchor(s)  {p}")

    print(f"\nscanned {tot['files']} files | TOC anchors rebuilt {tot['toc']} "
          f"(unmatched {tot['tocunres']}) | other anchors rewritten {tot['fixed']} | "
          f"odd-fence files {tot['fence']} | unresolved anchors {tot['anchor']} | "
          f"broken links {tot['link']} | broken cross-file fragments {tot['xfrag']}")
    remaining = (tot['anchor'] + tot['link'] + tot['xfrag'] + tot['fence']
                 + tot['tocunres'])
    return 1 if remaining else 0


if __name__ == '__main__':
    sys.exit(main())
