# ⎈ Helm 06 · Values Design and Precedence
### ⭐⭐ The most important file in this folder for real work. The exact precedence order, how deep merge actually behaves (maps merge, lists **replace**, `null` **deletes**), the `--set` type traps, the `--reuse-values` footgun — and how to design a `values.yaml` a stranger can use without reading your templates.

> **WHAT this file is:** the values layer — how Helm turns seven possible sources into the single `.Values` object your templates read, and how to design that object so your chart is usable.
>
> **WHY it is the most important file here:** because templates are written once and values are read constantly. Every person who deploys your chart interacts with `values.yaml` and never opens `templates/`. A chart with clever templates and badly-shaped values is a chart nobody can use. Conversely, *"why did my value not take effect?"* is the single most common Helm question, and the answer is always in this file.
>
> **TARGET:** you can state the precedence order from memory, predict the result of any values merge, diagnose a silently-ignored value in one command, and design a values file for the reader rather than the writer.
>
> **Prerequisite:** [`04-GO-TEMPLATE-SYNTAX-FROM-ZERO.md`](04-GO-TEMPLATE-SYNTAX-FROM-ZERO.md) — you need to know what `.Values` is before you can design it.
>
> **Time:** 4 hours.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1--the-one-values-object) | The one `.Values` object |
| [2](#2---precedence--the-exact-order-lowest-to-highest) | ⭐⭐ **Precedence** — the exact order, lowest to highest |
| [3](#3---how-to-inspect-what-helm-actually-computed) | ⭐ How to inspect what Helm **actually** computed |
| [4](#4---deep-merge--maps-merge-lists-replace-null-deletes) | ⭐⭐ **Deep merge** — maps merge, **lists replace**, `null` deletes |
| [5](#5--the---set-family-and-its-type-traps) | The `--set` family and its **type traps** |
| [6](#6-----reuse-values-and---reset-values--the-helm-3-footgun) | ⛔⛔ `--reuse-values` and `--reset-values` — **the Helm 3 footgun** |
| [7](#7--subcharts-and-the-global-values-trap) | Subcharts, and the **`global` values trap** |
| [8](#8---designing-valuesyaml-for-the-reader-not-the-writer) | ⭐⭐ Designing `values.yaml` **for the reader**, not the writer |
| [9](#9--flat-vs-nested--the-real-trade-off) | Flat vs nested — the real trade-off |
| [10](#10--environment-layering--the-pattern-that-scales) | Environment layering — the pattern that scales |
| [11](#11--nine-anti-patterns-with-the-fix-for-each) | Nine anti-patterns, with the fix for each |
| [12](#12---tasks) | 🔨 Tasks — **answers at the END** |

---

## 1 · The one `.Values` object

Your templates read `.Values`. There is **exactly one** of them per render, and it is built by merging up to seven sources.

```
   SOURCE                                   WHEN IT APPLIES
   ──────────────────────────────────────────────────────────────────
   subchart's own values.yaml          ←  always, for each subchart
   parent chart's values.yaml          ←  always
   parent's values for the SUBCHART    ←  when the parent addresses
       (keyed by the subchart name)        the subchart's namespace
   -f values-dev.yaml                  ←  each -f, in order given
   -f values-prod.yaml                 ←
   --set image.tag=1.4.2               ←  each --set, in order given
   --set-string image.tag=1.4.2        ←
   --set-json 'x=[{"a":1}]'            ←
   --set-file config=./app.properties  ←
   --reuse-values / --reset-values     ←  on `helm upgrade` only
   ──────────────────────────────────────────────────────────────────
                        ▼
              ONE MERGED .Values OBJECT
                        ▼
              every template reads this
```

⭐ **Three consequences that follow immediately:**

1. **A template can never tell which source set a value.** `.Values.image.tag` is `1.4.2` and nothing records that it came from `--set`. This is why `helm get values` (§3) exists and why "what did we actually deploy?" is a question you must ask Helm rather than read from the chart.
2. **Higher precedence wins per key, not per file.** If `values-dev.yaml` sets `image.tag` and `--set` sets `image.repository`, you get the dev tag and the CLI repository. Merging is **key-by-key**, not file-by-file.
3. **Order within the same precedence level matters.** Two `-f` files: the later one wins. Two `--set` flags: the later one wins.

---

## 2 · ⭐⭐ Precedence — the exact order, lowest to highest

```
LOWEST ─────────────────────────────────────────────────────────► HIGHEST

 1. Subchart's own values.yaml
      charts/postgresql/values.yaml

 2. Parent chart's values.yaml
      ./values.yaml

 3. Parent's values addressed to the subchart
      ./values.yaml →  postgresql:
                         auth:
                           password: x

 4. -f / --values FILES, in the order given
      -f values-dev.yaml -f values-prod.yaml
                          └── wins over values-dev.yaml

 5. --set / --set-string / --set-json / --set-file, in the order given
      --set image.tag=1.4.2

 6. On `helm upgrade` only: the interaction with
    --reuse-values / --reset-values        (§6 — ⛔ read this carefully)

 7. Post-renderer output                    (§ last, and rarely used)
```

### The two rules people get wrong

**Rule 1 — a parent's values for a subchart beat the subchart's own defaults.**

```yaml
# charts/postgresql/values.yaml      (the subchart's own default)
auth:
  username: postgres

# ./values.yaml                      (the parent, addressing the subchart)
postgresql:
  auth:
    username: shop
```
→ rendered: `auth.username: shop`. ✅ The parent wins. That is the entire point of subcharts.

**Rule 2 — `--set` beats every file, always.**

```bash
helm upgrade --install r ./chart -f values-prod.yaml --set replicas=1
```
→ `replicas: 1`, even if `values-prod.yaml` says `replicas: 5`.

⭐ **That is correct behaviour and a common incident.** Someone debugging in production runs `--set replicas=1` to test something. The next deploy uses the pipeline, which does not pass `--set`, and replicas go back to 5 — or, worse, someone *bakes* `--set` into the deploy command and it silently overrides the committed values file forever, so editing `values-prod.yaml` appears to do nothing. ⛔ **Never mix committed values files and `--set` in a deploy pipeline.** `--set` is for your laptop.

### Precedence in one command

```bash
# see it happen
helm template r ./chart \
  -f values.yaml \
  -f values-prod.yaml \
  --set image.tag=from-cli \
  --debug 2>&1 | sed -n '/COMPUTED VALUES/,/HOOKS/p'
```

---

## 3 · ⭐ How to inspect what Helm **actually** computed

⭐ **Learn these four commands and "my value was ignored" becomes a ten-second question instead of an afternoon.**

```bash
# ① ⭐⭐ THE ONE. What values did the LIVE release get?
helm get values RELEASE -n NAMESPACE
#   → only the USER-SUPPLIED values (-f files, --set). NOT the chart defaults.

# ② ⭐ The full merged picture — user values + chart defaults
helm get values RELEASE -n NAMESPACE --all

# ③ What will a render produce, before you apply it?
helm template r ./chart -f values.yaml --debug | sed -n '/COMPUTED VALUES/,/HOOKS/p'

# ④ What does the CHART default to? (no release needed)
helm show values CHART --version X.Y.Z > values-default.yaml
```

### ⭐⭐ The difference between ① and ② is the source of most confusion

```bash
$ helm get values shop-api -n shop-production
image:
  tag: 1.4.2
replicaCount: 3

$ helm get values shop-api -n shop-production --all
affinity: {}
autoscaling:
  enabled: false
  maxReplicas: 100
  minReplicas: 1
fullnameOverride: ""
image:
  digest: ""
  pullPolicy: IfNotPresent
  repository: ghcr.io/3558bhk/shop-api
  tag: 1.4.2
ingress:
  enabled: false
…
replicaCount: 3
resources: {}
```

- **Without `--all`** → what *you* supplied. Useful for "did my change land?"
- **With `--all`** → what the *templates saw*. ⭐ Useful for "what is this chart actually going to render?" — because the defaults are most of the picture.

> ⭐ **The diagnostic that ends most arguments.** Someone says "we set `resources` in the values file". Run `helm get values RELEASE --all | grep -A6 resources`. If it shows `resources: {}`, either the key path was wrong, or the file was not passed, or a later source overrode it. **The command tells you what Helm believes; arguing about what the YAML says is a different conversation.**

### The three ways a value silently does nothing

| Cause | How you spot it | Fix |
|---|---|---|
| **Wrong key path** — `image.tags` instead of `image.tag` | `helm get values --all` shows your key present *and* the correct key still at its default | ⭐ **`values.schema.json`** ([`11-TESTING-LINTING-SCHEMA-VALIDATION.md`](11-TESTING-LINTING-SCHEMA-VALIDATION.md)) — rejects unknown properties |
| **The template never reads it** | the key is in `--all`, but `helm template` output is unchanged | `grep -rn 'thatKey' templates/` — if nothing matches, the chart does not implement it |
| **A higher-precedence source overrode it** | your file says X, `helm get values` (no `--all`) shows Y | find the later `-f`, the `--set` in the pipeline, or the GitOps overlay |

```bash
# ⭐ the grep that answers "does this chart even support that value?"
grep -rn 'image.digest' ./chart/templates/ ./chart/values.yaml
```

---

## 4 · ⭐⭐ Deep merge — maps merge, **lists replace**, `null` deletes

This is the section that prevents real production incidents.

### 4.1 Maps merge recursively

```yaml
# values.yaml
image:
  repository: ghcr.io/3558bhk/shop-api
  pullPolicy: IfNotPresent
  tag: "1.0.0"
```
```yaml
# values-prod.yaml
image:
  tag: "1.4.2"
```
```yaml
# RESULT — merged key by key
image:
  repository: ghcr.io/3558bhk/shop-api    # ← kept from values.yaml
  pullPolicy: IfNotPresent                # ← kept
  tag: "1.4.2"                            # ← overridden
```

✅ Intuitive. This is why layering works.

### 4.2 ⛔⛔ Lists are REPLACED, not merged or appended

```yaml
# values.yaml
tolerations:
  - key: workload
    operator: Equal
    value: backend
    effect: NoSchedule
  - key: node-role
    operator: Exists
```
```yaml
# values-prod.yaml
tolerations:
  - key: gpu
    operator: Exists
```
```yaml
# RESULT — ⛔ ONE toleration, not three
tolerations:
  - key: gpu
    operator: Exists
```

**The entire base list is gone.** The same is true for `env`, `ports`, `volumes`, `route.routes`, `ingress.hosts`, `extraArgs` — every list in every chart you have ever layered.

> ⭐⭐ **This is the single most common values-layering bug, and it is silent.** Your production Deployment loses the `workload=backend` toleration, so it schedules onto the wrong nodes, or fails to schedule at all. Nothing warns you. `helm get values --all` shows exactly one toleration and it looks *fine*.
>
> **The three ways to defend against it:**
> 1. **Do not split lists across layer files.** Put the complete list in the layer that owns it. If production needs three tolerations, write all three in `values-prod.yaml`.
> 2. **Use maps instead of lists where the chart allows it.** A map merges key-by-key, so `env: {LOG_LEVEL: info}` layers safely while `env: [{name: LOG_LEVEL…}]` does not. ⭐ This is a *chart design* decision — see §8.
> 3. **Diff before you upgrade, always.** `helm diff upgrade` shows the list shrinking. If you are not running `helm diff`, you will find out from an incident.

```bash
# the check that catches it
helm diff upgrade RELEASE ./chart -f values.yaml -f values-prod.yaml | grep -B3 -A10 'tolerations'
```

### 4.3 ⭐ `null` deletes a key

```yaml
# values.yaml
nodeSelector:
  disktype: ssd
  zone: ap-south-1a
```
```yaml
# values-prod.yaml
nodeSelector:
  disktype: null          # ⭐ DELETE this key
```
```yaml
# RESULT
nodeSelector:
  zone: ap-south-1a
```

```yaml
# and null at the top of a map deletes the whole map
nodeSelector: null
# RESULT
nodeSelector: null       # → {{- with .Values.nodeSelector }} renders NOTHING
```

⭐ **This is how you turn off an inherited default.** A parent chart sets `postgresql.persistence.enabled: true`; your overlay wants it off. `enabled: false` works for booleans, but for a *map* you cannot "unset" it by omission — omission means "keep the parent's". You must set it to `null`.

> ⚠️ **The trap:** in YAML, `key:` with nothing after it **is** `null`. So an accidentally-empty key deletes rather than defaults:
> ```yaml
> resources:          # ⛔ this is null, not "use the default"
> ```
> If your chart's `values.yaml` has `resources:` on a line by itself with the real values intended below it and someone mis-indents, you have just deleted the block. Write `{}` explicitly when you mean "empty map".

### 4.4 Merge summary table

| Base | Overlay | Result | Why |
|---|---|---|---|
| `a: 1` | `a: 2` | `a: 2` | scalar override |
| `m: {x: 1, y: 2}` | `m: {y: 3}` | `m: {x: 1, y: 3}` | ⭐ **maps merge recursively** |
| `l: [1, 2, 3]` | `l: [9]` | `l: [9]` | ⛔ **lists are replaced** |
| `m: {x: 1}` | `m: {x: null}` | `m: {}` | ⭐ **null deletes** |
| `m: {x: 1}` | `m: null` | `m: null` | null deletes the whole map |
| *(absent)* | `n: 5` | `n: 5` | added |
| `s: "a"` | `s: 1` | `s: 1` | ⚠️ **type changes silently** — see §5 |

---

## 5 · The `--set` family and its **type traps**

### 5.1 The four variants

| Flag | Parses the value as | Use for |
|---|---|---|
| `--set` | ⚠️ **YAML-ish**: infers int, float, bool, null | most things |
| `--set-string` | ⭐ **always a string** | ⭐ **anything that looks like a number but must be text** |
| `--set-file` | the **contents of a file** as a string | certs, config blobs, a long YAML snippet |
| `--set-json` | **JSON** | lists and nested structures |
| `--set-literal` | string, no comma/period processing | values containing `,` or `.` |

### 5.2 ⛔⛔ The trap that has caused more incidents than any other

```bash
helm upgrade --install r ./chart --set image.tag=1.10
```

**Helm parses `1.10` as a FLOAT and renders:**

```yaml
image:
  tag: 1.1        # ⛔⛔ NOT "1.10"
```

Your image tag `1.10` became `1.1`. Kubernetes then pulls `repo:1.1` — which may **exist**, and be a completely different image. Or fail. Either way, you deployed something you did not intend, and the rendered YAML shows a number that looks plausible.

**The same trap, other forms:**

| You typed | Helm parsed | Rendered |
|---|---|---|
| `--set image.tag=1.10` | float | `1.1` ⛔ |
| `--set image.tag=1.0` | float | `1` ⛔ |
| `--set app.version=007` | int | `7` ⛔ |
| `--set port=8080` | int | `8080` — but as a number, and `EnvVar.value` must be a string ⛔ |
| `--set enabled=yes` | bool | `true` |
| `--set enabled=on` | bool | `true` |
| `--set name=null` | nil | `<no value>` or omitted |
| `--set zip=12345678901234567890` | ⚠️ large int | precision loss possible |
| `--set password=a,b` | ⛔ **list split on comma** | `[a, b]` |

**The fixes:**

```bash
# ⭐ ALWAYS --set-string for versions, tags, and anything numeric-looking that is text
--set-string image.tag=1.10
--set-string app.version=007

# quote inside --set (works, but --set-string is clearer)
--set image.tag="1.10"

# commas and periods: escape them
--set "key=a\,b"
--set-literal key=a,b

# lists and nested structures: --set-json
--set-json 'tolerations=[{"key":"gpu","operator":"Exists"}]'

# file contents
--set-file caCert=./tls/ca.pem
```

> ⭐⭐ **The rule to adopt unconditionally: `--set-string` for every value that is conceptually text, even if it looks numeric.** There is no downside. The upside is that `1.10` stays `1.10`. And in a chart you control, add `| quote` in the template — but do not *rely* on it, because `quote` applied to the float `1.1` gives you `"1.1"`, which is faithfully wrong.

### 5.3 Verify what `--set` actually did

```bash
helm template r ./chart --set image.tag=1.10 --debug 2>&1 \
  | sed -n '/COMPUTED VALUES/,/HOOKS/p' | grep -A3 image
```
```yaml
image:
  repository: ghcr.io/3558bhk/shop-api
  tag: 1.1          # ⛔ caught it, locally, in two seconds
```

---

## 6 · ⛔⛔ `--reuse-values` and `--reset-values` — the Helm 3 footgun

### The behaviour change almost nobody knows about

**In Helm 2,** `helm upgrade` **reused** the previous release's values by default. You could upgrade a chart version and your `--set` flags from last time would persist.

**In Helm 3, `helm upgrade` uses ONLY the chart defaults plus what you pass on this command.** The previous release's user values are **not** carried over.

```bash
# Revision 1
helm install r ./chart --set replicaCount=5 --set image.tag=1.4.2

# Revision 2 — Helm 3 ⛔ SILENTLY RESETS BOTH
helm upgrade r ./chart
#   → replicaCount: 1   (chart default)
#   → image.tag: ""     (chart default → renders <no value>)
```

**No warning. No error.** `helm upgrade` reports success, and your Deployment scales from 5 replicas to 1 with an unresolvable image. ⛔ This is a production outage from a command that looks like a routine chart bump.

### The two flags

| Flag | Effect |
|---|---|
| `--reuse-values` | ⭐ start from the **stored values of the current release**, then apply this command's `-f`/`--set` on top |
| `--reset-values` | use only chart defaults + this command's values (⛔ **this is the Helm 3 default**) |
| `--reset-then-reuse-values` *(Helm 3.14+)* | ⭐ **the one you usually want** — start from chart defaults of the **new** chart, merge in the stored user values, then this command's flags |

```bash
# reproduce the Helm 2 behaviour
helm upgrade r ./chart --reuse-values

# the safer modern form
helm upgrade r ./chart --reset-then-reuse-values
```

### ⭐ Why `--reuse-values` is *also* dangerous

It sounds like the fix, and it is worse in a specific way: **it merges your old user values over the NEW chart's defaults.**

So if chart v2 renamed `replicaCount` → `replicas`, your stored `replicaCount: 5` is merged in as a **stray unknown key**, the new `replicas` takes its **default**, and you get 1 replica — while `helm get values` shows `replicaCount: 5` and looks correct.

```bash
# the failure looks like this
$ helm get values r
replicaCount: 5        # ⛔ from revision 1; chart v2 does not read this key any more
$ helm get values r --all | grep -i replica
replicas: 1            # ⛔ the new chart's default
```

> ⭐⭐ **The correct answer is neither flag. It is: keep all your values in files, in git, and pass them explicitly on every upgrade.**
>
> ```bash
> helm upgrade --install r ./chart --version 2.0.0 \
>   -f values.yaml -f values-prod.yaml \
>   --wait --atomic
> ```
>
> Then the release's values are a **function of committed files**, not of what someone happened to type three revisions ago. Reproducible, reviewable, diffable, and immune to both footguns. This is the same discipline as the artifact-contract rule in [`../cicd-learning-path/`](../cicd-learning-path/README.md): **what you deployed must be reconstructible from git.**
>
> Use `--reuse-values` only interactively, on a laptop, against a throwaway release — and never in a pipeline or a GitOps repo.

### How to check what a live release actually has

```bash
helm get values r -n ns             # user-supplied (may be from three revisions ago!)
helm get values r -n ns --all       # the full merged set the templates saw
helm get manifest r -n ns           # ⭐ the RENDERED result — the ground truth
helm history r -n ns                # which revision is live, and was it an upgrade or rollback
```

⭐ **`helm get manifest` is the ultimate arbiter.** Values can be confusing; the manifest is what is in the cluster.

---

## 7 · Subcharts, and the **`global` values trap**

### 7.1 Addressing a subchart

```yaml
# Chart.yaml
dependencies:
  - name: postgresql
    version: "16.x"
    repository: "https://charts.bitnami.com/bitnami"
    condition: postgresql.enabled
```

```yaml
# the PARENT's values.yaml — the subchart name is the top-level key
postgresql:
  enabled: true
  auth:
    username: shop
    database: shop
  primary:
    persistence:
      size: 20Gi
```

⭐ The subchart's own `values.yaml` provides its defaults; the parent's `postgresql:` block overrides them (§2 rule 1).

### 7.2 `condition`, `tags`, `alias`

```yaml
dependencies:
  - name: postgresql
    condition: postgresql.enabled,backend.database.enabled   # ⭐ ANY of these true
    tags:
      - database                                             # toggle a GROUP at once
    alias: shopdb                                            # ⭐ include it twice under different names
  - name: redis
    condition: redis.enabled
    tags: [cache]
```

```yaml
# then:
tags:
  database: true      # enables BOTH postgresql and anything else tagged database
  cache: false
```

⭐ **`alias` is how you run two instances of one chart** — two Redis instances, three tenants of the same service. Each alias gets its own values namespace and its own release-scoped resource names.

### 7.3 ⛔ The `global` trap

```yaml
global:
  imageRegistry: registry.internal
  imagePullSecrets:
    - name: regcred
  storageClass: gp3-ssd
```

`global` is **special**: it is passed **unchanged into every subchart**, and subcharts read it directly. That is its purpose — one place to set the registry for twenty subcharts.

**The traps:**

| Trap | Why it bites |
|---|---|
| ⛔ **`global` cannot be overridden per-subchart.** | If `global.imageRegistry` is set, a subchart that honours it uses it — and you cannot say "this one subchart pulls from Docker Hub". You must either not use `global` for that key, or the subchart must support an override |
| ⛔ **Name collisions are silent.** | Your `global.storageClass` and a subchart's expectation of `global.storageClass` may mean different things (a class name vs a boolean). Both read `.Values.global.storageClass`. Nobody errors |
| ⛔ **`global` leaks your parent's opinions into third-party charts.** | Adding a key to `global` can change the behaviour of a Bitnami subchart you have never read. ⭐ **Only put keys in `global` that you have confirmed the subcharts actually consume** |
| ⛔ **Lists in `global` still replace, not merge** (§4.2) | `global.imagePullSecrets` in a subchart overlay replaces the parent's entirely |

```bash
# see what global actually resolves to, per subchart
helm template r ./chart --debug | grep -B2 -A6 'global:'
```

⭐ **The discipline:** treat `global` as a **published contract** with your subcharts. Document every key in it, keep the set small (`imageRegistry`, `imagePullSecrets`, `storageClass` are the conventional three), and never add a key without checking which charts read it.

---

## 8 · ⭐⭐ Designing `values.yaml` **for the reader**, not the writer

⭐ **The test that decides whether your chart is good:**

> **Can someone change the replica count, the image tag, and enable the ingress — without opening a single template?**

If no, your values are shaped like your *templates* rather than like the *user's intent*, and every change requires reading Go template code. That is a chart only its author can operate.

### 8.1 The seven design rules

**Rule 1 — name values after the *decision*, not the *manifest field*.**

```yaml
# ⛔ shaped like the template
spec:
  template:
    spec:
      containers:
        resources:
          limits:
            memory: 4Gi

# ✅ shaped like the decision
resources:
  limits:
    memory: 4Gi

# ✅✅ even better, when the chart can compute it
sizing: small        # → the chart maps small/medium/large to real requests+limits
```

**Rule 2 — every value that appears in `values.yaml` must be read by a template.** Dead values are lies: they promise configurability that does not exist.

```bash
# the audit that finds them
for key in $(yq -r '.. | path | join(".")' values.yaml | sort -u); do
  grep -rq "$(basename ${key//./\\.})" templates/ || echo "⛔ UNUSED: $key"
done
```

**Rule 3 — every value a template reads must have a default in `values.yaml`.** Otherwise a user gets `<no value>` or a nil-pointer error, and cannot discover the key exists.

```bash
# the reverse audit — find template reads with no default
grep -rhoE '\.Values\.[a-zA-Z0-9_.]+' templates/ | sed 's/^\.Values\.//' | sort -u > used.txt
yq -r '.. | path | join(".")' values.yaml | sort -u > declared.txt
comm -23 used.txt declared.txt        # ⛔ read but never declared
```

**Rule 4 — comment every value, including the obvious ones.** `values.yaml` is documentation. The comment is the only place a user learns the *unit*, the *valid range*, and the *consequence*.

```yaml
# ⛔ useless
timeout: 30

# ✅ useful
# Request timeout in SECONDS. Must be less than the ingress proxy-read-timeout
# (default 60s) or the client sees a 504 before your app does.
# Range: 1-300. Higher values hold connections open under load.
timeout: 30
```

**Rule 5 — put the three things every deployer needs at the top.** Image, replicas, resources. Everything else below, grouped. Nobody should scroll to find the image tag.

**Rule 6 — group by *concern*, not by Kubernetes object.**

```yaml
# ⛔ by object — forces the reader to know the manifest
deployment:
  replicas: 3
service:
  port: 8080
ingress:
  host: shop.example.com

# ✅ by concern
image:        { repository: …, tag: …, digest: … }
scaling:      { replicas: 3, autoscaling: { enabled: false } }
networking:   { port: 8080, ingress: { enabled: true, host: … } }
resources:    { requests: …, limits: … }
security:     { runAsNonRoot: true, readOnlyRootFilesystem: true }
observability:{ metrics: { enabled: true }, tracing: { enabled: false } }
```

**Rule 7 — make dangerous states unrepresentable.**

```yaml
# ⛔ a boolean that turns off a security control
security:
  enabled: false        # → the whole securityContext block vanishes

# ✅ the control is always on; only the specifics are configurable
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  seccompProfile: { type: RuntimeDefault }
```

⭐ A control that can be switched off by a config file is not a control. This is exactly the divergence demonstrated in [`../security-tools/checkov/00-INSTALL-AND-FUNDAMENTALS.md`](../security-tools/checkov/00-INSTALL-AND-FUNDAMENTALS.md) task 0.4: secure `values.yaml`, insecure `values-production.yaml`, and Checkov scanning only the defaults gives a green light on an insecure production deploy.

### 8.2 A well-designed `values.yaml`

```yaml
# ─────────────────────────────────────────────────────────────────────
# shop-api — the Java 21 / Spring Boot backend of the shop platform
# Docs: ./README.md    Schema: ./values.schema.json    Chart: 1.4.0
#
# ⭐ The three you almost always change:
#      image.digest · scaling.replicas · resources
# ⛔ NEVER put secrets in this file. See `secrets:` below.
# ─────────────────────────────────────────────────────────────────────

# ═══ IMAGE ══════════════════════════════════════════════════════════
image:
  repository: ghcr.io/3558bhk/shop-api

  # ⭐ REQUIRED in every environment. The artifact contract for this platform
  #    is a DIGEST, not a tag — a tag can be re-pointed, a digest cannot.
  #    The pipeline sets this; do not hand-edit it.
  #    Format: sha256:<64 hex>
  digest: ""

  # Used only when digest is empty (local development).
  tag: ""

  pullPolicy: IfNotPresent
  pullSecrets: []          # list of {name: …}; ⚠️ lists REPLACE when layered

# ═══ SCALING ════════════════════════════════════════════════════════
scaling:
  # ⭐ Always emitted. 0 is a valid value (scale to zero) — the template must
  #    NOT wrap this in `if`, or 0 renders as Kubernetes' default of 1.
  replicas: 3

  strategy:
    type: RollingUpdate
    # Zero-downtime requires maxUnavailable: 0. See the K8s path, Project 2.
    maxUnavailable: 0
    maxSurge: 1

  autoscaling:
    enabled: false         # when true, `replicas` is IGNORED by the HPA
    minReplicas: 3
    maxReplicas: 20
    targetCPUUtilization: 70

  # Graceful shutdown. Must exceed the app's request-drain time.
  terminationGracePeriodSeconds: 45

# ═══ RESOURCES ══════════════════════════════════════════════════════
# ⭐ requests drive SCHEDULING; limits prevent one pod starving the node.
#    For a JVM, set -Xmx to ~75% of limits.memory or it will be OOMKilled.
resources:
  requests: { cpu: 500m, memory: 1Gi }
  limits:   { cpu: "2",  memory: 3Gi }

# ═══ NETWORKING ═════════════════════════════════════════════════════
service:
  type: ClusterIP
  port: 8080               # ⭐ Spring Boot's server.port must match

ingress:
  enabled: false
  className: nginx
  hosts:
    - host: shop-api.internal
      paths: [{ path: /, pathType: Prefix }]
  tls: []                  # ⚠️ list — REPLACED, not appended, when layered
  annotations: {}          # map — merged safely

# ═══ CONFIG ═════════════════════════════════════════════════════════
# Rendered into a ConfigMap. Changing anything here triggers a rolling
# restart via the checksum/config annotation — that is intentional.
config:
  springProfilesActive: production
  logLevel: INFO
  managementEndpoints: "health,info,prometheus"

# ⛔ SECRETS: never in this file. Reference an existing Secret:
secrets:
  existingSecret: shop-api-secrets     # created out-of-band; keys in ./README.md
  # envFrom: true → mounted via envFrom.secretRef, not per-key

# ═══ SECURITY (not switchable — see README §"Hardening") ════════════
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  seccompProfile: { type: RuntimeDefault }

containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true         # ⭐ requires the emptyDir mounts below
  capabilities: { drop: [ALL] }

# Writable paths, required because the root filesystem is read-only
extraVolumeMounts:
  - { name: tmp,     mountPath: /tmp }
  - { name: runtime, mountPath: /app/runtime }

# ═══ OBSERVABILITY ══════════════════════════════════════════════════
metrics:
  enabled: true
  port: 8080               # Spring Boot serves /actuator/prometheus on the same port
  path: /actuator/prometheus
  # Creates a ServiceMonitor for kube-prometheus-stack.
  # ⭐ Requires the Prometheus CR to select it — see the Prometheus path §3.
  serviceMonitor:
    enabled: true
    interval: 30s
    labels: {}             # add {release: <prom-release>} if the selector requires it

probes:
  liveness:  { path: /actuator/health/liveness,  initialDelaySeconds: 60, periodSeconds: 10, failureThreshold: 6 }
  readiness: { path: /actuator/health/readiness, initialDelaySeconds: 20, periodSeconds: 5,  failureThreshold: 3 }
  # ⭐ A JVM needs 30-60s. Too-short a startup probe restart-loops the app forever.
  startup:   { path: /actuator/health/liveness,  failureThreshold: 30, periodSeconds: 5 }

# ═══ PLACEMENT (optional maps — omit or {} to render nothing) ═══════
nodeSelector: {}
tolerations: []            # ⚠️ list — REPLACED when layered. Put the FULL list here.
affinity: {}
podDisruptionBudget:
  enabled: true
  minAvailable: 2          # ⛔ must be < scaling.replicas or the node cannot drain

# ═══ ADVANCED ═══════════════════════════════════════════════════════
serviceAccount:
  create: true
  # ⭐ false unless the app calls the Kubernetes API. Checkov CKV_K8S_38.
  automountServiceAccountToken: false
  annotations: {}          # for IRSA / Workload Identity

networkPolicy:
  enabled: true
  allowedNamespaces: [shop-production, monitoring]

extraEnv: {}               # ⭐ MAP, not a list — layers safely (§4.2)
  # LOG_LEVEL: debug
```

⭐ **Count the comments.** That file is about 40% comment, and the comments carry the *units*, the *interactions* ("`replicas` is IGNORED by the HPA"), the *hazards* ("lists REPLACE when layered"), and the *reasons* ("`maxUnavailable: 0` for zero-downtime"). **That is what makes it usable by a stranger.**

---

## 9 · Flat vs nested — the real trade-off

```yaml
# FLAT
imageRepository: ghcr.io/3558bhk/shop-api
imageTag: "1.4.2"
imagePullPolicy: IfNotPresent
replicaCount: 3
servicePort: 8080
ingressEnabled: true

# NESTED
image:
  repository: ghcr.io/3558bhk/shop-api
  tag: "1.4.2"
  pullPolicy: IfNotPresent
replicaCount: 3
service:
  port: 8080
ingress:
  enabled: true
```

| | Flat | Nested |
|---|---|---|
| **`--set` ergonomics** | ⭐ `--set imageTag=1.4.2` | `--set image.tag=1.4.2` — fine |
| **Discovery** | ⛔ 60 keys in one flat list; nothing groups | ⭐ `image:` shows you everything about the image |
| **Passing a whole group to a helper** | ⛔ impossible | ⭐ `{{ toYaml .Values.resources \| nindent 12 }}`, `{{- with .Values.image }}` |
| **Subchart addressing** | ⛔ cannot namespace | ⭐ `postgresql.auth.username` works naturally |
| **Layering** | ⭐ a flat key can never be partially overridden | ⚠️ nested maps merge — powerful, but `null` deletes and lists replace |
| **Schema validation** | verbose | ⭐ natural — each group is one object definition |

⭐ **Verdict: nest by concern, keep the nesting shallow (2–3 levels max), and stay flat for the handful of scalars everybody changes.**

```yaml
# ✅ the shape most production charts converge on
image: { repository: …, tag: …, digest: …, pullPolicy: … }
scaling: { replicas: …, autoscaling: { … } }
resources: { requests: { … }, limits: { … } }
service: { type: …, port: … }
ingress: { enabled: …, hosts: [ … ] }
metrics: { enabled: …, serviceMonitor: { … } }
```

⛔ **Deeper than three levels and the merge behaviour becomes impossible to reason about**, the `--set` paths get long, and `helm diff` output becomes unreadable.

---

## 10 · Environment layering — the pattern that scales

```
chart/
├── Chart.yaml
├── values.yaml              ← ⭐ SAFE DEFAULTS for the least-privileged env (dev)
├── values.schema.json       ← validation (§11 in the testing file)
└── templates/

environments/
├── values-dev.yaml          ← almost empty; dev == the defaults
├── values-staging.yaml      ← the differences from dev
└── values-production.yaml   ← the differences from staging
```

```bash
helm upgrade --install shop-api ./chart \
  --version 1.4.0 \
  -n shop-production \
  -f ./chart/values.yaml \
  -f ./environments/values-production.yaml \
  --wait --atomic --timeout 10m
```

### ⭐ The four rules that make layering work

**Rule 1 — `values.yaml` must be a complete, working, safe configuration for the *least* privileged environment.** Not a template with holes. If `values.yaml` alone cannot deploy to dev, your layering is broken and every environment file is compensating.

**Rule 2 — environment files contain only DIFFERENCES.**

```yaml
# environments/values-production.yaml  ✅
scaling:
  replicas: 6
  autoscaling: { enabled: true, minReplicas: 6, maxReplicas: 30 }
resources:
  requests: { cpu: "1", memory: 2Gi }
  limits:   { cpu: "4", memory: 6Gi }
ingress:
  enabled: true
  hosts: [{ host: api.shop.example.com, paths: [{ path: /, pathType: Prefix }] }]
  tls: [{ secretName: shop-api-tls, hosts: [api.shop.example.com] }]
```

⛔ **Do not copy the whole file and edit it.** A duplicated 200-line production file diverges from the base within a month, and then "the chart" means three different things.

**Rule 3 — ⚠️ every list in an overlay must be COMPLETE** (§4.2).

```yaml
# ⛔ WRONG — production now has ONE toleration, not two
tolerations:
  - { key: gpu, operator: Exists }

# ✅ RIGHT — the full intended list
tolerations:
  - { key: workload, operator: Equal, value: backend, effect: NoSchedule }
  - { key: gpu, operator: Exists }
```

**Rule 4 — diff every layer, every time.**

```bash
# what does production actually get, versus dev?
diff <(helm template r ./chart -f environments/values-dev.yaml) \
     <(helm template r ./chart -f environments/values-production.yaml)

# and before any upgrade:
helm diff upgrade shop-api ./chart -f ./chart/values.yaml -f environments/values-production.yaml -n shop-production
```

### Where secrets go — ⛔ never in a values file

| Approach | Notes |
|---|---|
| ⭐ **`existingSecret`** | create the Secret out-of-band; the chart only references its name. Simplest, and the chart stays secret-free |
| **ExternalSecrets Operator** | Secret materialised from Vault/AWS SM/GCP SM. ⭐ Best at scale |
| **Sealed Secrets** | an encrypted `SealedSecret` CR you *can* commit |
| **Vault Agent injector** | annotations drive injection; nothing in the chart |
| ⛔ **plaintext in `values.yaml`** | a leaked credential with a commit history, and `git filter-repo` afterwards is a bad afternoon |

---

## 11 · Nine anti-patterns, with the fix for each

| # | Anti-pattern | Why it fails | Fix |
|---|---|---|---|
| **1** | ⛔ `--set` in a deploy pipeline | Silently overrides committed files forever; editing the values file appears to do nothing | Files in git, passed with `-f`. `--set` is for laptops |
| **2** | ⛔ Splitting a list across layer files | Lists **replace** (§4.2) — production loses the base entries, silently | Complete lists in the owning layer; prefer maps |
| **3** | ⛔ `--set image.tag=1.10` | Parsed as float → `1.1` → wrong image | `--set-string` |
| **4** | ⛔ `helm upgrade` with no value flags | Helm 3 resets to chart defaults (§6) | Always pass `-f` explicitly; use `upgrade --install` |
| **5** | ⛔ `--reuse-values` in production | Merges stale user values over new chart defaults; renamed keys become strays | Committed files, explicit `-f` |
| **6** | ⛔ Values shaped like the manifest | Users must read templates to change anything | Shape by *decision* (§8.1 rule 1) |
| **7** | ⛔ Declared values no template reads | Promises configurability that does not exist | Run the §8.1 rule-2 audit; delete or implement |
| **8** | ⛔ A boolean that disables a security control | Secure defaults, insecure production overlay — and Checkov scanning only defaults says PASS | Make the control unconditional (§8.1 rule 7) |
| **9** | ⛔ Secrets in `values.yaml` | A leaked credential with git history | `existingSecret` / ExternalSecrets / SealedSecrets |

---

## 12 · 🔨 Tasks

> **6.1** State the full precedence order from memory, lowest to highest, including where subchart values and the parent's values-for-the-subchart sit. Then prove it with one `helm template` command that shows a `--set` beating two `-f` files.

> **6.2** A colleague says "we set `resources.limits.memory: 8Gi` in `values-prod.yaml` but the pod still has 2Gi". Give the **five** distinct causes in the order you would check them, with the exact command for each.

> **6.3** Demonstrate all three merge behaviours — map merge, list replacement, and `null` deletion — with one chart and three commands. Then find a real list in a chart you use and show what an overlay would destroy.

> **6.4** Reproduce the `--set image.tag=1.10` float trap, prove it with `--debug`, and fix it three different ways. Say which you would standardise on and why.

> **6.5** Reproduce the Helm 3 `helm upgrade` values reset (§6) on a throwaway release. Report what `helm get values` shows before and after, and what `helm get manifest` shows. Then explain why `--reuse-values` is not the fix.

> **6.6** Audit a chart you own (or `helm create demo`) for §8.1 rules 2 and 3: values declared but never read, and values read but never declared. Report both lists and fix them.

> **6.7** Rewrite a flat `values.yaml` into a nested one grouped by concern, keeping every value reachable. Then show the two things nesting makes possible that flat could not do.

> **6.8** Build the three-file environment layering from §10 for the `shop-api` chart, and prove with a `diff` of two renders that the only differences are the ones you intended.

> **6.9** ⭐⭐ Your chart has `security.enabled` which gates the entire `securityContext` block. `values.yaml` sets it `true`; `values-production.yaml` sets it `false` because "the app needs to write to the filesystem". Explain the full chain of consequences, what Checkov would and would not have caught, and redesign the values so the situation cannot occur.

> **6.10** ⭐⭐ You inherit a chart deployed with `helm install r ./chart --set replicaCount=7 --set image.tag=2.1 --set-string db.password=s3cr3t`. Nobody recorded the values. Write the recovery procedure that gets this release onto committed files in git **without** changing what is running, and name the step where a mistake causes an outage.

<details>
<summary>👉 Answers</summary>

**6.1** The order, lowest → highest:

```
 1. Subchart's own values.yaml                charts/postgresql/values.yaml
 2. Parent chart's values.yaml                ./values.yaml
 3. Parent's values addressed to the subchart ./values.yaml → postgresql: { … }
 4. -f / --values files, IN THE ORDER GIVEN   -f a.yaml -f b.yaml   (b wins)
 5. --set / --set-string / --set-json /
    --set-file, IN THE ORDER GIVEN            the last one wins
 6. (helm upgrade only) the --reuse-values /
    --reset-values interaction                §6
 7. Post-renderer output                       last of all
```

⭐ **The two positions people get wrong:** the **subchart's own defaults are the *lowest*** (level 1) — the parent overrides them, which is the entire point of a subchart. And level 3 (**the parent addressing the subchart**) is *higher* than level 2 (the parent's own top-level keys), which sounds odd but is simply "more specific wins": `postgresql.auth.username` in the parent beats `auth.username` in the subchart.

**Proving it — one command, `--set` beating two files:**

```bash
# three sources, three different answers for the same key
cat > /tmp/a.yaml <<'EOF'
image: { tag: "from-a" }
replicaCount: 2
EOF
cat > /tmp/b.yaml <<'EOF'
image: { tag: "from-b" }
EOF

helm template r ./demo -f /tmp/a.yaml -f /tmp/b.yaml --set image.tag=from-cli --debug \
  2>&1 | sed -n '/COMPUTED VALUES/,/HOOKS/p'
```
```yaml
COMPUTED VALUES:
image:
  pullPolicy: IfNotPresent
  repository: ghcr.io/3558bhk/shop-api
  tag: from-cli            # ⭐ --set (level 5) beat b.yaml (level 4) beat a.yaml (level 4)
replicaCount: 2            # ⭐ only in a.yaml — and it SURVIVED, because merging is
                           #    per-KEY, not per-file (§1 consequence 2)
```

⭐ **That second line is the part worth noticing.** `replicaCount: 2` came from `a.yaml` and was not overridden by `b.yaml` or `--set`, because neither mentioned it. **Merging is key-by-key across all sources**, not "the last file wins wholesale". That is why a partially-populated overlay is safe, and why a *complete* overlay that re-states everything is redundant.

**6.2** Five causes, in the order to check them — cheapest and most likely first.

**① Was the file actually passed to the release that is running?** ⭐ *Most likely by far.*

```bash
helm get values shop-api -n shop-production
```
If `resources.limits.memory` is **absent** from the output, the file was never applied to this release — the pipeline deployed without `-f values-prod.yaml`, or someone ran a bare `helm upgrade` (§6's reset). **This is the cause ~60% of the time**, and it takes three seconds.

**② Is the live manifest actually what you think?**

```bash
helm get manifest shop-api -n shop-production | grep -A8 'resources:'
kubectl get deploy shop-api -n shop-production -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
```
⭐ **Check the cluster, not Helm.** If the manifest says 8Gi but the Deployment says 2Gi, the upgrade never applied — a failed rollout, a `pending-upgrade` release, or an HPA/controller overwriting it. `helm get manifest` is what Helm *believes*; `kubectl get` is what *is*.

**③ Is the key path exactly right, including nesting and spelling?**

```bash
helm get values shop-api -n shop-production --all | yq '.resources'
helm show values ./chart --version 1.4.0 | yq '.resources'
```
Common failures: `resource:` (singular), `limits` nested under the wrong parent, or the chart expects `resources.limits.memory` but you wrote `containers[0].resources…` because you were reading the *manifest* shape rather than the *values* shape (§8.1 rule 1 exists precisely to stop this confusion).

**④ Did a higher-precedence source override it?**

```bash
helm get values shop-api -n shop-production          # user-supplied only
helm history shop-api -n shop-production             # who deployed, when, what revision
grep -rn 'resources' .github/workflows/ Jenkinsfile* azure-pipelines.yml 2>/dev/null | grep -i 'set'
```
Look for a `--set resources.limits.memory=2Gi` baked into the pipeline (§11 anti-pattern 1), a **later** `-f` file that re-states `resources`, or a GitOps overlay applied after yours. Remember: **the last `-f` and the last `--set` win.**

**⑤ Does the template actually read it?**

```bash
grep -rn 'resources' ./chart/templates/
```
If the grep shows nothing — or shows a hardcoded `memory: 2Gi` — the chart does not implement the value. ⛔ This is §11 anti-pattern 7: a declared value no template reads. It looks configurable, is not, and no amount of correct YAML will change the output.

```bash
# the definitive end-to-end check, combining ③ ④ ⑤
helm template shop-api ./chart -f values.yaml -f values-prod.yaml --debug \
  --show-only templates/deployment.yaml | grep -A6 resources
```
If the **render** is wrong, the problem is in the chart or your values. If the render is **right** but the cluster is wrong, the problem is in the deploy step. ⭐ **That single branch is what makes this list ordered rather than a guessing game.**

**6.3** One chart, three demonstrations.

```bash
mkdir -p merge-demo/templates && cd merge-demo
cat > Chart.yaml <<'EOF'
apiVersion: v2
name: merge-demo
version: 0.1.0
EOF
cat > values.yaml <<'EOF'
map:   { a: 1, b: 2 }
list:  [one, two, three]
block: { keep: yes, drop: me }
EOF
cat > templates/cm.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: { name: demo }
data:
  map:   {{ .Values.map   | toJson | quote }}
  list:  {{ .Values.list  | toJson | quote }}
  block: {{ .Values.block | toJson | quote }}
EOF
```

**① Maps merge recursively:**
```bash
helm template r . -f <(echo 'map: { b: 99, c: 3 }') --show-only templates/cm.yaml | grep 'map:'
#   map: "{\"a\":1,\"b\":99,\"c\":3}"
```
⭐ `a: 1` **survived**, `b` was **overridden**, `c` was **added**. Recursive per-key merge.

**② Lists are replaced:**
```bash
helm template r . -f <(echo 'list: [nine]') --show-only templates/cm.yaml | grep 'list:'
#   list: "[\"nine\"]"          ⛔ "one","two","three" are GONE
```

**③ `null` deletes:**
```bash
helm template r . -f <(echo 'block: { drop: null }') --show-only templates/cm.yaml | grep 'block:'
#   block: "{\"keep\":true}"     ⭐ the key is removed, not set to empty
```

**A real list an overlay would destroy** — `kube-prometheus-stack`'s Alertmanager routing tree:

```bash
helm show values prometheus-community/kube-prometheus-stack --version 88.1.5 \
  | yq '.alertmanager.config.route'
```
```yaml
route:
  group_by: [job]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  receiver: prometheus-alertmanager
  routes:                       # ⭐ a LIST of sub-routes
    - matchers: [alertname =~ ".*"]
      receiver: …
```

```yaml
# ⛔ An overlay that adds ONE route for critical alerts:
alertmanager:
  config:
    route:
      routes:
        - matchers: ['severity = critical']
          receiver: pagerduty
```

**Result: every bundled sub-route is gone.** Only the PagerDuty route remains — so *all* alerts go to PagerDuty, including the informational ones, and every team-specific route the chart shipped disappears. ⛔ **That is a paging incident caused by a values overlay**, and it is invisible in `helm get values` because what you see there is exactly what you wrote.

```yaml
# ✅ The fix — restate the COMPLETE intended list:
alertmanager:
  config:
    route:
      group_by: [job, alertname, namespace]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 12h
      receiver: 'null'
      routes:
        - matchers: ['severity = critical']
          receiver: pagerduty
        - matchers: ['severity = warning']
          receiver: slack-warnings
        - matchers: ['team = data']
          receiver: data-oncall
```

```bash
# and the check that catches it before it ships:
helm diff upgrade kps prometheus-community/kube-prometheus-stack --version 88.1.5 \
  -f values.yaml -f values-prod.yaml -n monitoring | grep -B2 -A25 'routes:'
```

⭐ **Note also that `group_by` is a list** — an overlay setting `group_by: [alertname]` replaces `[job]` rather than extending it. **Every list in every layered values file must be complete.**

**6.4** Reproduce:

```bash
helm template r ./demo --set image.tag=1.10 --debug 2>&1 \
  | sed -n '/COMPUTED VALUES/,/HOOKS/p' | grep -A3 '^image:'
```
```yaml
image:
  pullPolicy: IfNotPresent
  repository: ghcr.io/3558bhk/shop-api
  tag: 1.1              # ⛔⛔ you typed 1.10
```

**Why:** `--set` parses the value with YAML-ish type inference. `1.10` is a valid **float literal**, so it becomes `1.1`. Go's float formatting then drops the trailing zero — it was never part of the number. Rendering gives you `1.1`.

**Three fixes:**

```bash
# ① ⭐ --set-string — forces the value to stay text
helm template r ./demo --set-string image.tag=1.10 --debug | grep -A3 '^image:'
#   tag: 1.10   ✅

# ② quote inside --set
helm template r ./demo --set 'image.tag="1.10"' --debug | grep -A3 '^image:'
#   tag: 1.10   ✅   (the quotes make it a YAML string before inference)

# ③ a values file — YAML string quoting is explicit and reviewed
echo 'image: { tag: "1.10" }' > /tmp/v.yaml
helm template r ./demo -f /tmp/v.yaml --debug | grep -A3 '^image:'
#   tag: 1.10   ✅
```

**Which to standardise on: ③, a values file — and ① as the rule for the rare interactive case.**

Reasons, in order:

1. ⭐ **A file is reviewed, versioned and diffable.** `"1.10"` in `values-production.yaml` is a *quoted string in git*, so the type is explicit, a reviewer can see it, and `helm diff` shows a change when someone edits it. `--set` leaves no trace anywhere except `helm get values` on a live release.
2. **It removes the class of bug rather than fixing an instance.** With ①, every person must remember `--set-string` every time, for every numeric-looking value — `1.10`, `007`, `1.0`, `8080` as an env value, a leading-zero version. With ③, nobody has to remember anything.
3. ⛔ **`--set` in a pipeline is anti-pattern 1 anyway** — it silently overrides committed files forever, so nobody can tell why editing the values file does nothing.

**And in the chart itself, defend regardless of the caller:**

```yaml
image: "{{ .Values.image.repository }}:{{ .Values.image.tag | quote }}"
```
⭐ **But note `quote` is not a complete defence:** `quote` applied to the float `1.1` produces `"1.1"` — faithfully rendering the wrong value. Quoting fixes *type* problems (a string where Kubernetes wants a string), not *value* problems (a float where you meant text). That is why `--set-string` and values files matter and template quoting does not substitute for them.

The strongest version — make the ambiguity impossible:
```yaml
image: {{ required "image.digest is required — pin by digest, never by tag" .Values.image.digest | quote }}
```
A digest is 64 hex characters and can never be parsed as a number. ⭐ This is the artifact contract used throughout [`../cicd-learning-path/`](../cicd-learning-path/README.md), asserted with the `@[0-9a-f]{64}` gate — and it eliminates this entire bug class as a side effect.

**6.5**

```bash
# ── set up a release with real user values
helm install r ./demo --set replicaCount=7 --set-string image.tag=2.1.0
helm get values r
```
```yaml
USER-SUPPLIED VALUES:
image:
  tag: 2.1.0
replicaCount: 7
```
```bash
helm get manifest r | grep -E 'replicas:|image:'
#   replicas: 7
#   image: "ghcr.io/3558bhk/shop-api:2.1.0"
```

```bash
# ── ⛔ now "upgrade" with no value flags
helm upgrade r ./demo
#   Release "r" has been upgraded. Happy Helming!     ← reports SUCCESS
helm get values r
```
```yaml
USER-SUPPLIED VALUES:
null                       # ⛔⛔ EVERYTHING GONE
```
```bash
helm get manifest r | grep -E 'replicas:|image:'
#   replicas: 1                                   ← chart default
#   image: "ghcr.io/3558bhk/shop-api:<no value>"   # or the AppVersion default
```

**What each command showed:**

| Command | Before | After |
|---|---|---|
| `helm get values r` | `image.tag: 2.1.0`, `replicaCount: 7` | ⛔ **`null`** — no user values at all |
| `helm get values r --all` | the merged picture incl. your 7 | only chart defaults |
| `helm get manifest r` | `replicas: 7` | ⛔ `replicas: 1`, image `<no value>` |

⭐ **`helm get values` printing literally `null` is the diagnostic.** It means the release has **no** user-supplied values — which is only possible if an upgrade wiped them. Helm 3's `helm upgrade` computes values from **chart defaults + this command's flags**, and this command had no flags. Nothing was "lost"; nothing was carried forward, because carrying forward was never the default.

And note **`helm upgrade` reported success.** There is no warning. The Deployment then scales 7 → 1 and the pods go `ImagePullBackOff`.

**Why `--reuse-values` is not the fix:**

```bash
helm upgrade r ./demo --reuse-values
```

It restores the old user values — but it merges them **over the NEW chart's defaults**, which fails in three specific ways:

1. ⛔ **Renamed keys become strays.** If chart v2 renamed `replicaCount` → `scaling.replicas`, your stored `replicaCount: 7` merges in as an unknown key that no template reads, while `scaling.replicas` takes its **default of 1**. `helm get values` shows `replicaCount: 7` and looks perfectly correct. You have 1 replica and evidence that says 7.
2. ⛔ **You cannot adopt new defaults.** A v2 chart adds `security.runAsNonRoot: true` as a *safe new default*. Fine. But it also changes `resources.limits.memory` from 2Gi to 4Gi because the app grew — and your stored `2Gi` overrides it, so the new chart runs under-provisioned and OOMs, with no indication that a three-revisions-ago `--set` is responsible.
3. ⛔ **State accumulates invisibly.** Every interactive `--set` anyone ever ran is now permanently part of the release's values, layered over each other across revisions. Six months later nobody can answer "what is this release configured with, and why?" — which is the exact question you need answered during an incident.

⭐ **The correct fix is to make the release's values a function of committed files:**

```bash
# 1. recover the truth about what is running right now
helm get values r --all > environments/values-recovered.yaml

# 2. write the intended state into git (task 6.10 does this properly)
# 3. from now on, every deploy is explicit and reproducible:
helm upgrade --install r ./demo --version 2.0.0 \
  -f values.yaml -f environments/values-production.yaml \
  --wait --atomic
```

Then `helm get values r` shows exactly the union of your committed files, and there is no hidden state. **Reproducibility is the fix; `--reuse-values` is a way of preserving the non-reproducibility.**

**6.6** Two audits on `helm create demo`.

**Audit A — declared but never read (dead values):**

```bash
cd demo
# every leaf path in values.yaml
yq -r '.. | path | join(".")' values.yaml | grep -v '^$' | sort -u > declared.txt
# every .Values.* the templates read
grep -rhoE '\.Values\.[a-zA-Z0-9_.]+' templates/ | sed 's/^\.Values\.//' | sort -u > read.txt
# normalise: compare on the LEAF name too, since templates often range into sub-keys
comm -23 declared.txt read.txt
```

Realistic output on a stock `helm create` chart:

```
image.pullSecrets
ingress.annotations
ingress.tls
serviceAccount.annotations
```

**Verdict: these are false positives from a naive audit.** They *are* read — via `range`, `with`, or a helper that receives a parent object:

```bash
grep -rn 'pullSecrets\|imagePullSecrets' templates/
#   templates/deployment.yaml:  {{- with .Values.image.pullSecrets }}
```

⭐ **So the audit must be run per leaf with the parent context in mind.** The reliable version:

```bash
# for each declared leaf, does ANY template mention the leaf name at all?
while read -r path; do
  leaf="${path##*.}"
  grep -rq "$leaf" templates/ || echo "⛔ DEAD: $path"
done < declared.txt
```

That produces the honest list. On a hand-written chart it commonly finds keys someone added "for later" and never implemented — ⛔ which is worse than absent, because it advertises configurability that silently does nothing (§11 anti-pattern 7). Fix: implement it, or delete it from `values.yaml` and document it in the README as a future addition.

**Audit B — read but never declared (undiscoverable values):**

```bash
comm -23 read.txt declared.txt
```

Realistic output:

```
Chart.AppVersion          # ✅ not a value — a built-in, ignore
global.imageRegistry      # ⛔ READ but never declared
metrics.serviceMonitor.labels
```

**Fixes:**

```yaml
# values.yaml — add them, with defaults and comments

# Registry prefix applied to every image. Leave empty to use each image's own
# registry. ⚠️ If a subchart reads `global.imageRegistry`, this must match.
global:
  imageRegistry: ""

metrics:
  serviceMonitor:
    enabled: true
    # Extra labels on the ServiceMonitor. Add {release: <prometheus-release>}
    # if the Prometheus CR requires a release label to select it.
    labels: {}          # ⭐ {} explicitly — not an absent key
```

⭐ **Why "read but never declared" is the more dangerous of the two.** A declared-but-dead value wastes a reader's time. An **undeclared-but-read** value is **invisible**: it does not appear in `values.yaml`, so nobody knows it exists, so nobody sets it, so it is always nil — and the code path that handles it is never exercised until the day someone discovers it in a template at 2 a.m. `grep`-driven audits of both directions belong in CI ([`11-TESTING-LINTING-SCHEMA-VALIDATION.md`](11-TESTING-LINTING-SCHEMA-VALIDATION.md)), and `values.schema.json` with `additionalProperties: false` catches the first class automatically.

**6.7** Flat → nested.

```yaml
# ⛔ BEFORE — 22 flat keys, nothing grouped
imageRepository: ghcr.io/3558bhk/shop-api
imageTag: "1.4.2"
imageDigest: ""
imagePullPolicy: IfNotPresent
imagePullSecrets: []
replicaCount: 3
strategyType: RollingUpdate
strategyMaxUnavailable: 0
strategyMaxSurge: 1
autoscalingEnabled: false
autoscalingMinReplicas: 3
autoscalingMaxReplicas: 20
autoscalingTargetCPU: 70
resourcesRequestsCpu: 500m
resourcesRequestsMemory: 1Gi
resourcesLimitsCpu: "2"
resourcesLimitsMemory: 3Gi
serviceType: ClusterIP
servicePort: 8080
ingressEnabled: false
ingressClassName: nginx
metricsEnabled: true
```

```yaml
# ✅ AFTER — 6 concerns, ≤3 levels deep
image:
  repository: ghcr.io/3558bhk/shop-api
  tag: "1.4.2"
  digest: ""               # ⭐ preferred over tag; pin by digest in CI
  pullPolicy: IfNotPresent
  pullSecrets: []

scaling:
  replicas: 3              # ⭐ always emitted; 0 is valid (§6 task 4.5)
  strategy:
    type: RollingUpdate
    maxUnavailable: 0      # zero-downtime
    maxSurge: 1
  autoscaling:
    enabled: false         # when true, `replicas` is ignored by the HPA
    minReplicas: 3
    maxReplicas: 20
    targetCPUUtilization: 70

resources:
  requests: { cpu: 500m, memory: 1Gi }
  limits:   { cpu: "2",  memory: 3Gi }

service:
  type: ClusterIP
  port: 8080

ingress:
  enabled: false
  className: nginx

metrics:
  enabled: true
```

**Two things nesting makes possible that flat could not do:**

**① Pass a whole group to a helper in one action.**

```yaml
# ⛔ impossible with flat keys — you must enumerate and re-shape every field:
          resources:
            limits:
              cpu: {{ .Values.resourcesLimitsCpu }}
              memory: {{ .Values.resourcesLimitsMemory }}
            requests:
              cpu: {{ .Values.resourcesRequestsCpu }}
              memory: {{ .Values.resourcesRequestsMemory }}
#   four lines, four chances to mismatch the manifest schema, and adding a new
#   resource dimension (ephemeral-storage, hugepages) requires editing the template

# ✅ one line, and it passes through ANY keys Kubernetes adds in future:
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

Same for every optional block:
```yaml
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
```
⭐ `with` gives you the **emptiness check and the rebind in one construct** ([`04`](04-GO-TEMPLATE-SYNTAX-FROM-ZERO.md) §8). With flat keys there is no group to test for emptiness, so you need a separate `enabled` boolean per optional block — which is where `security.enabled: false` anti-patterns come from (§6.9).

**② Address a subchart, and scope `global`.**

```yaml
# ⛔ impossible flat — there is no namespace to address
postgresqlAuthUsername: shop

# ✅ the subchart's own key structure, overridden from the parent
postgresql:
  auth:
    username: shop
    database: shop
  primary:
    persistence: { size: 20Gi }
```

Flat keys cannot express "these belong to the postgresql subchart", so a flat chart **cannot have subcharts with configurable values** — which rules out bundling PostgreSQL, Redis, or a shared library chart. That alone makes nesting non-optional for any chart with dependencies ([`09-SUBCHARTS-DEPENDENCIES-LIBRARY-CHARTS.md`](09-SUBCHARTS-DEPENDENCIES-LIBRARY-CHARTS.md)).

⭐ **A third, softer benefit:** discovery. `helm show values | grep -A8 '^image:'` answers "everything about the image" in one read. With 22 flat keys you scan the whole file and mentally regroup it — every single time.

**6.8** Three files, and the proof.

```yaml
# chart/values.yaml — ⭐ a COMPLETE, WORKING config for dev (§10 rule 1).
# Deploying with this file alone must produce a running dev environment.
image:
  repository: ghcr.io/3558bhk/shop-api
  digest: ""
  tag: "dev"
  pullPolicy: Always
scaling:
  replicas: 1
  autoscaling: { enabled: false }
resources:
  requests: { cpu: 100m, memory: 512Mi }
  limits:   { cpu: 500m, memory: 1Gi }
ingress:  { enabled: false }
metrics:  { enabled: true }
config:   { springProfilesActive: dev, logLevel: DEBUG }
```

```yaml
# environments/values-staging.yaml — ONLY the differences (§10 rule 2)
scaling:
  replicas: 2
  autoscaling: { enabled: true, minReplicas: 2, maxReplicas: 6 }
resources:
  requests: { cpu: 250m, memory: 1Gi }
  limits:   { cpu: "1",  memory: 2Gi }
ingress:
  enabled: true
  className: nginx
  hosts: [{ host: shop-api.staging.internal, paths: [{ path: /, pathType: Prefix }] }]
config: { springProfilesActive: staging, logLevel: INFO }
```

```yaml
# environments/values-production.yaml — ⭐ the COMPLETE list for every list-typed value
scaling:
  replicas: 6
  autoscaling: { enabled: true, minReplicas: 6, maxReplicas: 30 }
  strategy: { type: RollingUpdate, maxUnavailable: 0, maxSurge: 1 }   # restated in full
resources:
  requests: { cpu: "1", memory: 2Gi }
  limits:   { cpu: "4",  memory: 6Gi }
image:
  pullPolicy: IfNotPresent        # ⭐ not Always — digest-pinned, immutable
ingress:
  enabled: true
  className: nginx
  hosts: [{ host: api.shop.example.com, paths: [{ path: /, pathType: Prefix }] }]
  tls:   [{ secretName: shop-api-tls, hosts: [api.shop.example.com] }]
config: { springProfilesActive: production, logLevel: INFO }
podDisruptionBudget: { enabled: true, minAvailable: 4 }   # ⭐ < replicas (6)
networkPolicy: { enabled: true, allowedNamespaces: [shop-production, monitoring] }
secrets: { existingSecret: shop-api-secrets }             # ⛔ never plaintext here
```

**Prove the only differences are intended:**

```bash
render() {
  helm template shop-api ./chart -f ./chart/values.yaml -f "$1" \
    --set-string image.digest="$2"
}

render environments/values-production.yaml sha256:aaaa > /tmp/prod.yaml
render environments/values-staging.yaml      sha256:aaaa > /tmp/stag.yaml
render /dev/null                             sha256:aaaa > /tmp/dev.yaml

# ⭐ structural diff — ignores ordering and formatting noise
diff <(yq -P 'sort_keys(..)' /tmp/dev.yaml)  <(yq -P 'sort_keys(..)' /tmp/stag.yaml)
diff <(yq -P 'sort_keys(..)' /tmp/stag.yaml) <(yq -P 'sort_keys(..)' /tmp/prod.yaml)

# and the count, so you can eyeball whether it is plausible
diff <(yq -P /tmp/dev.yaml) <(yq -P /tmp/prod.yaml) | grep -c '^[<>]'
```

⭐ **Two things make this proof real rather than decorative:**

1. **`--set-string image.digest` is passed identically to all three.** The digest changes on every deploy, so if you leave it to differ between renders, *every* diff line is the digest and you learn nothing. Holding it constant isolates the environment differences. (`--set-string`, not `--set` — §5.)
2. **`yq -P 'sort_keys(..)'` normalises before diffing.** Raw `helm template` output ordering can vary with map iteration ([`04`](04-GO-TEMPLATE-SYNTAX-FROM-ZERO.md) task 4.4), producing diff lines that are not real differences. Sorting removes that noise so every remaining line is a genuine change.

**Then the check that catches the list trap (§4.2):**

```bash
for f in values-staging values-production; do
  echo "── $f ──"
  helm template shop-api ./chart -f ./chart/values.yaml -f environments/$f.yaml \
    | yq -r '.. | select(tag=="!!seq") | length' | paste -sd, -
done
```
Compare list lengths against what you intended. If production's `tolerations` has 1 entry where the base had 3, you have found a silent replacement before it reached a cluster.

⭐ **Make this a CI job.** It is five lines of shell and it catches the two most common layering bugs — unintended divergence and list truncation — before review.

**6.9** ⭐⭐ The full chain of consequences.

**The setup:**
```yaml
# templates/deployment.yaml
    spec:
      {{- if .Values.security.enabled }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      {{- end }}
      containers:
        - name: app
          {{- if .Values.security.enabled }}
          securityContext:
            {{- toYaml .Values.containerSecurityContext | nindent 12 }}
          {{- end }}
```
```yaml
# values.yaml             →  security: { enabled: true }
# values-production.yaml  →  security: { enabled: false }   "the app needs to write to the filesystem"
```

**Consequence 1 — production runs with no security context at all.** Not a weakened one: **absent**. Which means Kubernetes defaults apply, and the defaults are permissive:

| Field | Value when the block is absent |
|---|---|
| `runAsNonRoot` | unset → **the image's USER decides**; a `FROM` with no `USER` runs as **root (UID 0)** |
| `readOnlyRootFilesystem` | **false** |
| `allowPrivilegeEscalation` | **true** |
| `capabilities.drop` | **nothing dropped** → the container keeps the **default capability set**, including `NET_RAW` |
| `seccompProfile` | `Unconfined` on many runtimes unless the Pod Security Standard sets it |

⭐ So the reason given — "the app needs to write to the filesystem" — is addressed by disabling `readOnlyRootFilesystem`, and the *actual effect* is that the container also becomes **root, privilege-escalating, capability-rich and unconfined**. **One boolean controlled five unrelated controls, and flipping it for one reason silently changed all five.** That is the core defect.

**Consequence 2 — a container escape becomes plausible.** Root in the container + `allowPrivilegeEscalation: true` + no dropped capabilities + a writable root filesystem is the standard precondition set for escaping to the node. Combined with `automountServiceAccountToken: true` (also often gated behind the same boolean), an attacker who lands in that pod has a ServiceAccount token and the kernel surface to try an escape. The blast radius stops being "one pod".

**Consequence 3 — the divergence is invisible in every review surface.** `values.yaml` is secure; `git diff` on the chart shows no change; the chart README says "hardened by default". The only place the truth appears is the **rendered production manifest**, which nobody reads.

**What Checkov would and would not have caught:**

| Scan | Result | Why |
|---|---|---|
| `checkov -d chart/ --framework helm` | ✅ **PASS** | ⛔ Scans with **default values**, where `security.enabled: true`. The insecure branch is never rendered |
| `checkov -f <(helm template … -f values.yaml)` | ✅ **PASS** | same reason |
| ⭐ `checkov -f <(helm template … -f values.yaml -f values-production.yaml)` | ⛔ **FAIL** — `CKV_K8S_20` (runAsNonRoot), `CKV_K8S_22` (readOnlyRootFilesystem), `CKV_K8S_1` (allowPrivilegeEscalation), `CKV_K8S_25/37` (capabilities), `CKV_K8S_29/30/31` (securityContext/seccomp) | The rendered production output has no `securityContext` at all |

⭐⭐ **So the honest answer is: Checkov would have caught it — but only if you scanned the rendered production output.** This is precisely the demonstration in [`../security-tools/checkov/00-INSTALL-AND-FUNDAMENTALS.md`](../security-tools/checkov/00-INSTALL-AND-FUNDAMENTALS.md) task 0.4, and the rule it establishes: **scan every environment's rendered values, never the chart defaults alone.** A chart is not secure or insecure; a chart *plus a values file* is.

**The redesign — three changes, in order of importance:**

**① Delete the boolean. Make the controls unconditional.**

```yaml
# templates/deployment.yaml
    spec:
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
        - name: app
          securityContext:
            {{- toYaml .Values.containerSecurityContext | nindent 12 }}
```

There is now no values file that can produce a pod without a security context. ⭐ **A control that cannot be disabled does not need to be audited.**

**② Solve the actual problem — writable paths — instead of disabling the control.**

The stated reason was "the app needs to write to the filesystem". That is a request for **specific writable directories**, not for a writable root filesystem:

```yaml
# values.yaml
containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true          # ⭐ STAYS TRUE
  runAsNonRoot: true
  runAsUser: 10001
  capabilities: { drop: [ALL] }
  seccompProfile: { type: RuntimeDefault }

# ⭐ the real fix: declare the writable paths
extraVolumes:
  - { name: tmp,     emptyDir: {} }
  - { name: runtime, emptyDir: {} }
extraVolumeMounts:
  - { name: tmp,     mountPath: /tmp }
  - { name: runtime, mountPath: /app/runtime }
```

For a Spring Boot app the usual culprits are `/tmp` (Tomcat work dir), the JVM's own temp files, and a log directory — all of which are `emptyDir` mounts, or better, **stdout logging** so nothing writes to disk at all. ⭐ `readOnlyRootFilesystem: true` plus two `emptyDir` mounts is *more* secure than the original configuration **and** solves the problem that was used to justify disabling it.

**③ If a genuine escape hatch is required, make it narrow, loud and reviewed.**

```yaml
# values.yaml
containerSecurityContext:
  readOnlyRootFilesystem: true
  # ⛔ There is deliberately NO `security.enabled` switch.
  #    To run privileged you must override individual fields below AND
  #    remove the guard in templates/_validate.tpl — a two-file change
  #    that cannot happen by accident and shows up in review.

# values-production.yaml  →  contains NO security overrides at all
```

```yaml
{{/* templates/_validate.tpl — the guard */}}
{{- if not .Values.containerSecurityContext.runAsNonRoot }}
  {{- fail "containerSecurityContext.runAsNonRoot must be true. If you genuinely need root, see docs/exceptions.md and open a ticket." }}
{{- end }}
{{- if not .Values.containerSecurityContext.readOnlyRootFilesystem }}
  {{- fail "readOnlyRootFilesystem must be true. Add an emptyDir mount to extraVolumeMounts instead." }}
{{- end }}
```

⭐ `fail` at render time means the chart **refuses to produce** an insecure manifest — the error appears on the operator's screen with a sentence telling them what to do instead. That is categorically different from a boolean that quietly permits it.

**The generalisable principle:** ⛔ **never let one value gate multiple unrelated controls.** `security.enabled` is the archetypal example — it sounds tidy and it means that flipping it for *any* reason changes *all* of them, and the person flipping it has no idea how many that is. Model each control as its own value with a safe default, and make the unsafe value unreachable or loud.

**6.10** ⭐⭐ Recovery, with no change to what is running.

**The situation:** a live release whose configuration exists **only** in Helm's stored release Secret, created by flags nobody recorded. The goal: get it into git, without touching the running workload.

---

**Step 0 — freeze the deploy path.** Tell everyone, and disable the pipeline trigger if you can. ⛔ The one thing that must not happen mid-recovery is another `helm upgrade`, which would reset the values again (§6) and destroy the evidence you are about to extract.

**Step 1 — capture the ground truth, three ways.**

```bash
RELEASE=r; NS=production; OUT=./recovery-$(date +%F)
mkdir -p "$OUT"

# (a) what Helm stored as USER-SUPPLIED values — ⭐ the flags someone typed
helm get values  $RELEASE -n $NS        > $OUT/values-user.yaml

# (b) the FULL merged set the templates actually saw
helm get values  $RELEASE -n $NS --all  > $OUT/values-all.yaml

# (c) ⭐⭐ the rendered manifest — the arbiter of what is really in the cluster
helm get manifest $RELEASE -n $NS       > $OUT/manifest.yaml

# plus the metadata you will need for the audit trail
helm history  $RELEASE -n $NS           > $OUT/history.txt
helm get notes $RELEASE -n $NS          > $OUT/notes.txt
helm get all     $RELEASE -n $NS        > $OUT/get-all.yaml
helm list -n $NS -o json | jq '.[] | select(.name=="'"$RELEASE"'")' > $OUT/release.json
```

```bash
# and the cluster's own view, which is what actually runs
kubectl -n $NS get deploy,svc,ingress,cm,secret,hpa,pdb,sa -o yaml > $OUT/live-objects.yaml
```

⭐ **Why (c) matters as much as (a) and (b):** values can lie. A `--set` from three revisions ago, a renamed key, a chart upgrade that changed a default — all produce a `values-all.yaml` that does not fully explain the running manifest. **`helm get manifest` cannot lie**; it is the bytes Helm last applied. Diffing (c) against what your new files render is the verification step (§Step 5).

**Step 2 — separate the values into three buckets.**

```bash
# what did the user actually supply?
cat $OUT/values-user.yaml
```
```yaml
USER-SUPPLIED VALUES:
db:
  password: s3cr3t          # ⛔ bucket C — a secret, in Helm's storage
image:
  tag: "2.1"                # bucket B — but ⚠️ --set-string was used, so it's text
replicaCount: 7             # bucket A — legitimate configuration
```

| Bucket | Contents | Destination |
|---|---|---|
| **A — legitimate config** | `replicaCount: 7` | `environments/values-production.yaml`, **with a comment explaining why 7** |
| **B — config that needs correcting** | `image.tag: "2.1"` | ⭐ convert to `image.digest` — a tag is mutable and cannot be reproduced. Look up the digest of what is *actually running* |
| **C — ⛔ secrets** | `db.password` | **out of values entirely** → a Kubernetes Secret / ExternalSecrets / SealedSecret, referenced by `existingSecret` |

```bash
# Bucket B: find the digest of the image that is REALLY running
kubectl -n $NS get deploy $RELEASE -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl -n $NS get pods -l app=$RELEASE \
  -o jsonpath='{range .items[*]}{.status.containerStatuses[0].imageID}{"\n"}{end}' | sort -u
# → ghcr.io/3558bhk/shop-api@sha256:<64hex>   ⭐ THIS is the artifact contract
```

⭐ **This step is not pedantry.** `image.tag: "2.1"` in a recovered values file means "whatever `2.1` points at *next time*" — so the recovery itself introduces a change. The digest is the only reference that reproduces what is running. Same rule as everywhere in [`../cicd-learning-path/`](../cicd-learning-path/README.md): **the artifact is identified by digest.**

**Step 3 — write the files.**

```yaml
# environments/values-production.yaml
# ⭐ RECOVERED 2026-09-17 from `helm get values r -n production`.
#    Prior history: set by hand via --set; no record existed. See recovery-2026-09-17/.
scaling:
  replicas: 7          # recovered. ⚠️ WHY 7 is unknown — confirm with the team,
                       #    then replace this comment with the reason.
resources:
  requests: { cpu: "1", memory: 2Gi }     # measured from live usage, not guessed
  limits:   { cpu: "2", memory: 4Gi }
```

```bash
# measure the resource numbers from the running pods rather than inventing them
kubectl -n $NS top pod -l app=$RELEASE --containers
```

```yaml
# chart/values.yaml — the secret becomes a REFERENCE
secrets:
  existingSecret: shop-api-secrets      # keys: db-password, …
```

```bash
# create the Secret out-of-band (or as an ExternalSecret / SealedSecret)
kubectl -n $NS create secret generic shop-api-secrets \
  --from-literal=db-password='s3cr3t'
```

⭐ **And rotate it.** That password has been sitting in a Helm release Secret — base64, not encrypted — readable by anyone with `get` on secrets in that namespace, and it is now also in your `recovery-*/values-user.yaml`. ⛔ **Treat the recovery as the moment the credential was exposed, not as the moment it was protected.** Rotate, then delete the captured file:

```bash
shred -u $OUT/values-user.yaml 2>/dev/null || rm -P $OUT/values-user.yaml
# ⛔ and confirm it never reached git:
git log --all --oneline -- '*values-user.yaml'
```

**Step 4 — verify the new files reproduce the running state, WITHOUT applying.**

```bash
# ⭐ the whole point of the exercise
helm template $RELEASE ./chart \
  -f chart/values.yaml -f environments/values-production.yaml \
  --set-string image.digest="sha256:<from step 2>" \
  > $OUT/manifest-new.yaml

# the diff must be EMPTY apart from known, intended changes
diff <(yq -P 'sort_keys(..)' $OUT/manifest.yaml) \
     <(yq -P 'sort_keys(..)' $OUT/manifest-new.yaml)
```

Expected remaining differences, each of which you must be able to explain:

| Difference | Acceptable? |
|---|---|
| `env` entries moved from inline to `envFrom.secretRef` | ✅ intended (bucket C) |
| `image:` now a digest instead of `repo:2.1` | ✅ intended (bucket B) |
| `helm.sh/chart` annotation shows a new chart version | ✅ expected |
| ⛔ `replicas`, `resources`, ports, selectors, probes differ | ⛔ **STOP** — you have mis-recovered something |

⭐ **`selector` differences are the ones to fear most.** Deployment selectors are **immutable**; a changed selector means the upgrade will be **rejected** by the API server, or (if the resource is recreated) will orphan every running pod.

**Step 5 — ⛔⛔ THE STEP WHERE A MISTAKE CAUSES AN OUTAGE: adopt the release without re-applying it.**

You now have correct files, but Helm's stored release still has `USER-SUPPLIED VALUES: replicaCount: 7, image.tag: 2.1, db.password: s3cr3t`. If you simply run `helm upgrade … -f <new files>`, Helm computes a **new manifest from your files** and applies it — and **any difference between that manifest and what is running becomes a live change, right now, at the moment of your choosing to be careless.**

The safe adoption procedure:

```bash
# ① Diff against the LIVE release, not against your files
helm diff upgrade $RELEASE ./chart \
  -f chart/values.yaml -f environments/values-production.yaml \
  --set-string image.digest="sha256:<digest>" \
  -n $NS | tee $OUT/adoption-diff.txt
wc -l $OUT/adoption-diff.txt

# ② READ EVERY LINE. Each must be an intended change from Step 4's table.
#    ⛔ If there is anything you cannot explain, STOP. Do not proceed.

# ③ Validate against the API server without applying anything
kubectl apply --dry-run=server -f $OUT/manifest-new.yaml

# ④ Confirm the immutable fields are untouched
for f in 'spec.selector' 'spec.template.spec.containers[0].name'; do
  echo "$f:"
  diff <(kubectl -n $NS get deploy $RELEASE -o jsonpath="{.$f}") \
       <(yq -r ".spec.template.spec | \"$f\"" $OUT/manifest-new.yaml) && echo "  ✅ same"
done

# ⑤ Only now, in a change window, with --wait --atomic so a failure self-reverts:
helm upgrade $RELEASE ./chart \
  --version <pinned> \
  -f chart/values.yaml -f environments/values-production.yaml \
  --set-string image.digest="sha256:<digest>" \
  -n $NS --wait --atomic --timeout 10m

# ⑥ Verify
helm get values $RELEASE -n $NS          # ← must now show YOUR files, not the old flags
kubectl -n $NS rollout status deploy/$RELEASE
kubectl -n $NS get pods -l app=$RELEASE  # ← same pods, no restart, unless intended
```

**Why step ⑤ is the outage risk, and what specifically goes wrong:**

- ⛔ **`replicas` mismatch.** If you recovered `replicaCount: 7` into a *flat* key but the chart reads `scaling.replicas`, your new file's `replicas` never lands — and the chart default (1 or 3) applies. **Production scales from 7 to 1 during the adoption command.** This is the exact `--reuse-values` stray-key failure from §6.5, arriving through a different door. Step ① catches it; step ② is where you actually read it.
- ⛔ **`resources` shrink.** If you guessed requests/limits rather than measuring (§Step 3), pods can be evicted or throttled on the next scheduling event.
- ⛔ **Selector immutability.** A changed `selector.matchLabels` makes the upgrade **fail** — and without `--atomic` you are left with a release in `pending-upgrade` state that **blocks every subsequent Helm operation** until someone manually patches the release Secret ([`15-TROUBLESHOOTING-PRODUCTION.md`](15-TROUBLESHOOTING-PRODUCTION.md)).
- ⛔ **The secret vanishes.** If `db.password` was consumed as an inline env var and your new chart uses `envFrom.secretRef`, but the Secret `shop-api-secrets` was never created, the pods restart and **crash on a missing credential**. Step 3's `kubectl create secret` must precede step ⑤ — and you must verify it exists:
  ```bash
  kubectl -n $NS get secret shop-api-secrets -o jsonpath='{.data}' | jq keys
  ```

⭐ **The meta-lesson:** the danger is not that the files are wrong — step 4 proves them. The danger is that **the adoption command is the first moment those files become real**, and it applies *every* difference at once. So the discipline is: diff against the live release (①), read every line (②), server-side validate (③), check immutables (④), then apply with `--wait --atomic` in a window (⑤), and verify the values landed (⑥). ⛔ Skipping ① and ② — "the files are correct, just run it" — is how a documentation exercise becomes an incident.

**Step 6 — close the loop so it cannot recur.**

- Commit `recovery-*/` (minus the secret) with the audit trail: from-values, to-files, date, operator, diff.
- ⛔ **Ban bare `helm upgrade` and `--set` in the pipeline.** Every deploy passes explicit `-f` files and `--version`. Encode it: a CI lint that fails if the deploy command contains `--set` or lacks `-f`.
- Add `values.schema.json` with `additionalProperties: false` so a stray key (`replicaCount` when the chart wants `scaling.replicas`) **fails at render** instead of silently doing nothing ([`11-TESTING-LINTING-SCHEMA-VALIDATION.md`](11-TESTING-LINTING-SCHEMA-VALIDATION.md)).
- Make the pipeline **fail if `helm get values` on the live release does not match the committed files** — a drift check that catches the next person who runs `--set` in production:
  ```bash
  diff <(helm get values $RELEASE -n $NS) <(yq '. | pick(["scaling","resources","image"])' environments/values-production.yaml)
  ```
- Rotate any credential that lived in a release Secret, and put a **note in the runbook** that release Secrets are base64 and readable by anyone with `get secrets` in the namespace.

</details>

---

## ➡️ Next

**[`07-HELPERS-NAMED-TEMPLATES.md`](07-HELPERS-NAMED-TEMPLATES.md)** — `_helpers.tpl` in depth: the standard label set, naming and the 63-character rule, building your own reusable helpers, and the `dict`-passing idiom for helpers that need more than the root context.

**Then:** [`08-BUILD-A-REAL-CHART-FROM-SCRATCH.md`](08-BUILD-A-REAL-CHART-FROM-SCRATCH.md) — ⭐⭐ build the complete `shop-api` chart: Deployment, Service, Ingress, ConfigMap, Secret reference, ServiceAccount, NetworkPolicy, PDB, HPA, ServiceMonitor, test pod and `NOTES.txt`.

**Read alongside:** [`../prometheus-in-kubernetes/04-INSTALL-KUBE-PROMETHEUS-STACK.md`](../prometheus-in-kubernetes/04-INSTALL-KUBE-PROMETHEUS-STACK.md) — a 9,000-line `values.yaml` in the wild, and §4.2's list-replacement trap causing a real alerting incident.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
