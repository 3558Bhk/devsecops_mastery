# ⎈ Helm 04 · Go Template Syntax From Zero
### The template language, properly: the dot and its scope, variables, pipelines, whitespace control, `if`/`range`/`with`, and `define` vs `template` vs `include` — with the debugging loop that makes any broken YAML readable in seconds.

> **WHAT this file is:** the language. Helm charts are Go templates that produce YAML, and almost every confusing Helm behaviour is a template behaviour. This file teaches the language from nothing.
>
> **WHY it matters more than any other file in this folder:** because you cannot debug what you cannot read. When `helm upgrade` fails with *"error converting YAML to JSON: yaml: line 42: did not find expected key"*, the answer is never in the YAML — it is in the template that produced the YAML. People who can read templates fix it in a minute; people who cannot give up and delete the release.
>
> **TARGET:** you can read any chart's `templates/` directory and explain what it renders, write your own without whitespace surprises, and diagnose a rendering failure without guessing.
>
> **Prerequisite:** you have run `helm create` and looked at what it produced. If not, do [`03-CHART-ANATOMY.md`](03-CHART-ANATOMY.md) first — it takes twenty minutes.
>
> **Time:** 4 hours. Work through every example; templates are not a reading subject.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1--what-helm-actually-does-with-a-template) | What Helm actually does with a template |
| [2](#2---the-dot--and-the-root-context) | ⭐⭐ **The dot (`.`)** and the root context |
| [3](#3--variables-and-escaping-scope-with-) | Variables, and escaping scope with `$` |
| [4](#4--pipelines-and-functions) | Pipelines and functions |
| [5](#5---whitespace-control--the-source-of-most-broken-yaml) | ⭐⭐ **Whitespace control** — the source of most broken YAML |
| [6](#6--if--else-and-the-falsy-rules) | `if` / `else` and **the falsy rules** |
| [7](#7--range--lists-maps-and-the-else-branch) | `range` — lists, maps, and the `else` branch |
| [8](#8--with--rebinding-the-dot-and-its-trap) | `with` — rebinding the dot (and its trap) |
| [9](#9---define--template--include--why-include-almost-always-wins) | ⭐⭐ `define` / `template` / `include` — **why `include` almost always wins** |
| [10](#10--the-toyaml--nindent-pattern) | The `toYaml` + `nindent` pattern |
| [11](#11--comments-built-in-objects-and-files) | Comments, built-in objects, and `.Files` |
| [12](#12---the-debugging-loop) | ⭐⭐ **The debugging loop** |
| [13](#13--the-fifteen-mistakes-everyone-makes) | The fifteen mistakes everyone makes |
| [14](#14---tasks) | 🔨 Tasks — **answers at the END** |

---

## 1 · What Helm actually does with a template

```
   Chart directory                          What Helm produces
   ┌────────────────────────┐
   │ Chart.yaml             │  name, version, appVersion, apiVersion: v2
   │ values.yaml            │  ─────────────┐
   │ values-prod.yaml (-f)  │  ─────────────┤  MERGED into ONE .Values object
   │ --set image.tag=1.4.2  │  ─────────────┘  (precedence: file 06)
   │                        │
   │ templates/             │
   │   deployment.yaml  ────┼──▶  Go template engine  ──▶  rendered YAML  ─┐
   │   service.yaml     ────┼──▶  (text/template +      ──▶  rendered YAML  │
   │   _helpers.tpl     ────┼──▶   the Sprig library)    ──▶  (no output;   │
   │   NOTES.txt        ────┼──▶                        ──▶   definitions) │
   │   tests/test.yaml  ────┼──▶                        ──▶  rendered YAML  │
   └────────────────────────┘                                              │
                                                                           ▼
                                                          ┌────────────────────────┐
                                                          │  kubectl-apply-able    │
                                                          │  YAML documents, sent  │
                                                          │  to the API server     │
                                                          └────────────────────────┘
```

⭐ **Three facts that reframe everything:**

1. **Helm has no idea you are writing Kubernetes YAML.** To the template engine, `deployment.yaml` is **text**. It does not parse it, validate it, or know what a `Deployment` is. Every "YAML error" you get is Helm handing a string to the API server and the API server complaining. **The template engine is YAML-agnostic**, which is why whitespace mistakes are so easy and so invisible.
2. **`_helpers.tpl` produces no output.** A leading underscore means "not a manifest" — Helm renders it for its `define` blocks but emits nothing. Same for `NOTES.txt` (printed to *you*, not applied) and `tests/` (only run by `helm test`).
3. **The merge happens before rendering.** All your values files and `--set` flags become **one** `.Values` object, and the template sees only the merged result. ⭐ That is why you can never tell from a template *which* file set a value — and why `helm get values` exists.

### The three commands you will live in

```bash
helm template RELEASE ./chart -f values.yaml            # render, print, apply nothing ⭐
helm template RELEASE ./chart -f values.yaml --debug    # render + show computed values
helm template RELEASE ./chart --show-only templates/deployment.yaml
helm lint ./chart                                       # render + basic YAML validation
helm install RELEASE ./chart --dry-run --debug          # render AND talk to the cluster
```

⭐ **`helm template` is your REPL.** It renders locally, needs no cluster, and shows you the exact bytes that would be applied. Use it after every change. `--dry-run` additionally validates against the API server (so it catches "this field does not exist on this Kubernetes version") but needs a cluster and, since Helm 3, does not persist anything.

---

## 2 · ⭐⭐ The dot (`.`) and the root context

**This is the single most important concept in the file.** Get this and the rest is syntax.

`{{ }}` delimits an *action*. Inside it, `.` is **the current scope** — the data object the action operates on. At the top of a template file, `.` is the **root context**, and it contains:

| Object | What it is | Examples |
|---|---|---|
| **`.Values`** | ⭐ the **merged** values — `values.yaml` + `-f` files + `--set` | `.Values.replicaCount`, `.Values.image.tag` |
| **`.Release`** | facts about **this release** | `.Release.Name`, `.Release.Namespace`, `.Release.Service` (`"Helm"`), `.Release.Revision`, `.Release.IsUpgrade`, `.Release.IsInstall` |
| **`.Chart`** | the contents of **`Chart.yaml`** | `.Chart.Name`, `.Chart.Version`, `.Chart.AppVersion`, `.Chart.Type`, `.Chart.Annotations`, `.Chart.KubeVersion` |
| **`.Capabilities`** | what **the cluster** supports | `.Capabilities.KubeVersion.Version`, `.Capabilities.APIVersions.Has "apps/v1"` |
| **`.Files`** | non-template files in the chart | `.Files.Get "config.ini"`, `.Files.Glob "conf/*"` |
| **`.Template`** | the file being rendered | `.Template.Name`, `.Template.BasePath` |

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-{{ .Chart.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
    helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
```

```bash
helm template shop ./demo --set-string 'image.tag=1.4.2'
```
```yaml
metadata:
  name: shop-demo
  namespace: default
  labels:
    app.kubernetes.io/version: "1.4.2"
    helm.sh/chart: demo-0.1.0
```

### ⭐⭐ The thing that confuses everyone: `.` changes

**`.` is not a global.** It is the *current* scope, and `range` and `with` **rebind it**. This is the source of the most common beginner error in Helm:

```yaml
# ⛔ BROKEN — and the error will be baffling
{{- range .Values.env }}
  - name: {{ .name }}
    value: {{ .Values.defaults.fallback }}     # ⛔ .Values does not exist here!
{{- end }}
```

Inside `range .Values.env`, **`.` is now one element of the `env` list** — a map with a `name` key. It is *not* the root context. So `.Values` resolves against the *list element*, which has no `Values` field, and you get:

```
error calling include: template: demo/templates/deployment.yaml:14:20:
executing "demo/templates/deployment.yaml" at <.Values.defaults.fallback>:
nil pointer evaluating interface {}.defaults
```

⭐ **`nil pointer evaluating interface {}` is almost always "you used `.Something` inside a `range` or `with` where `.` had been rebound."** Read that error as *"the current dot does not have this field"*, not as *"my values are wrong."*

**The fix — `$` always means the root:**

```yaml
{{- range .Values.env }}
  - name: {{ .name }}
    value: {{ $.Values.defaults.fallback }}    # ✅ $ is ALWAYS the root context
{{- end }}
```

> ⭐⭐ **Memorise this rule: `.` is "where I am now"; `$` is "where I started".** Anywhere inside a `range` or `with`, use `$` to reach `.Values`, `.Release` or `.Chart`. It costs nothing and prevents the whole class of error. Experienced chart authors write `$.Values` inside blocks by reflex.

### Nested field access, and the missing-key behaviour

```yaml
{{ .Values.image.repository }}          # → ghcr.io/3558bhk/shop-api
{{ .Values.a.b.c.d }}                   # → deep nesting works
```

⭐ **Accessing a key that does not exist yields the zero value — `<no value>` — not an error.** That is a *feature* for optional values and a **hazard** for required ones:

```yaml
image: {{ .Values.image.tag }}
```
```yaml
# if image.tag is unset:
image: <no value>          # ⛔ Helm renders this LITERAL STRING into your YAML
```

`<no value>` is not a placeholder — it is text, and Kubernetes will try to pull an image called `<no value>`. Two defences:

```yaml
# ① default
image: {{ .Values.image.tag | default .Chart.AppVersion | quote }}

# ② ⭐ required — fail the render with a message a human can act on
image: {{ required "image.tag must be set (or rely on .Chart.AppVersion)" .Values.image.tag | quote }}
```

⭐ **Use `required` for anything that must not be guessed.** A chart that renders `<no value>` produces a Deployment that fails at *pull* time, minutes later, in a cluster, with a confusing event. A chart that fails at *render* time produces one line on your laptop. **Fail as early and as loudly as possible.**

---

## 3 · Variables, and escaping scope with `$`

```yaml
{{- $name := .Values.nameOverride | default .Chart.Name -}}
{{- $fullName := printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}

metadata:
  name: {{ $fullName }}
```

| Syntax | Meaning |
|---|---|
| `$x := value` | declare and assign |
| `$x = value` | ⭐ **reassign** an existing variable (no colon) |
| `$` | ⭐⭐ **the root context, always** |
| `$x.field` | field access on a variable |

**Variables are scoped to the block where they are declared.** A `$x` declared inside a `range` does not exist outside it — the same trap as `.`, with the same fix (declare outside, or use `$`).

⭐ **Why variables exist at all:** they let you compute a value **once** and reuse it, which matters when the computation has side-effect-like behaviour (`trunc`, `printf`) or when you must guarantee two places get the *same* string. The standard labels helper in `_helpers.tpl` is exactly this pattern.

---

## 4 · Pipelines and functions

```yaml
{{- .Values.image.tag | default .Chart.AppVersion | quote -}}
```

A pipeline passes the result of each stage as the **last argument** of the next — like a shell pipe. So the above is `quote(default(.Values.image.tag, .Chart.AppVersion))`.

⚠️ **`default` takes the default first and the value second** — which reads backwards in pipeline form. `x | default y` means *"if x is empty, use y"*. Correct, and confusing the first ten times.

### The functions you will actually use

| Function | What it does | Example |
|---|---|---|
| `quote` / `squote` | wrap in `"` / `'` | `{{ .Values.image.tag \| quote }}` → `"1.4.2"` |
| `default` | fallback when empty | `{{ .Values.x \| default "y" }}` |
| `required` | ⭐ fail the render with a message | `{{ required "msg" .Values.x }}` |
| `toYaml` | ⭐⭐ render a map/list as YAML | `{{ toYaml .Values.resources \| nindent 12 }}` |
| `nindent` | **newline + indent** N spaces | see §10 |
| `indent` | indent N spaces, **no leading newline** | ⛔ see §13 mistake 2 |
| `printf` | format a string | `{{ printf "%s-%s" .Release.Name .Chart.Name }}` |
| `trunc` / `trimSuffix` | trim to length / remove suffix | ⭐ the 63-char DNS label rule |
| `ternary` | conditional value | `{{ ternary "a" "b" .Values.flag }}` |
| `coalesce` | first non-empty of several | `{{ coalesce .Values.a .Values.b "fallback" }}` |
| `empty` | is it falsy? | `{{ if not (empty .Values.list) }}` |
| `regexMatch` | pattern test | `{{ if regexMatch "^[0-9]+\\.[0-9]+$" .Values.tag }}` |
| `semverCompare` | ⭐ version logic | `{{ if semverCompare ">=1.21-0" .Capabilities.KubeVersion.Version }}` |
| `b64enc` / `b64dec` | base64 | `{{ .Values.password \| b64enc }}` for a Secret |
| `sha256sum` | ⭐ hash — the config-change trigger | `{{ include (print $.Template.BasePath "/configmap.yaml") . \| sha256sum }}` |
| `toJson` / `fromJson` | JSON round-trip | |
| `fromYaml` | parse a YAML **string** into a map | ⭐ for values that hold YAML as text |
| `list` / `dict` / `set` / `get` / `hasKey` | collections | `{{ if hasKey .Values "featureFlags" }}` |
| `keys` / `values` / `merge` / `deepCopy` | map ops | |
| `tpl` | ⭐ **render a value as a template** | `{{ tpl .Values.configTemplate . }}` |
| `fail` | abort with a message | `{{ fail "production requires 3 replicas" }}` |
| `include` | ⭐⭐ call a named template **as a function** | see §9 |

### ⛔ The functions you must never use in a manifest

```yaml
password: {{ randAlphaNum 16 | b64enc }}     # ⛔⛔
name:   {{ printf "%s-%s" .Release.Name (uuidv4) }}   # ⛔
date:   {{ now | date "2006-01-02" }}        # ⛔
```

**Why:** these are **non-deterministic**. Every `helm template`, every `helm upgrade`, every `helm diff` produces different output for the same inputs.

The consequences are severe and non-obvious:

1. ⛔ **Every upgrade looks like a change** — so `helm diff` is permanently noisy and stops being useful as a review tool.
2. ⛔ **`--atomic` rollback cannot restore the old value**, because re-rendering produces a *third* value.
3. ⛔⛔ **A random password regenerated on upgrade breaks every client using the old one.** This is a real, common production incident.
4. ⛔ **Reproducibility is gone.** You cannot prove what was deployed, because you cannot re-render it.

**The correct patterns:**

```yaml
# password: generate ONCE, outside the chart, into a Secret
# (kubectl create secret / ExternalSecrets / SealedSecrets / Vault)

# a stable random-looking suffix: derive it from something deterministic
checksum: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}

# today's date: pass it in as a value
builtOn: {{ .Values.buildDate | quote }}
```

⭐ **The general rule: a template must be a pure function of its inputs.** `.Values`, `.Release`, `.Chart` and `.Capabilities` are inputs. The clock and the RNG are not. Anything that reads them belongs outside the chart.

The same reasoning makes **`lookup` dangerous**:

```yaml
{{- $existing := lookup "v1" "Secret" .Release.Namespace "my-secret" }}
```

`lookup` queries **the cluster** at render time. It makes rendering depend on cluster state, so:
- ⛔ `helm template` **always returns empty** for `lookup` (there is no cluster), so your local render lies to you;
- ⛔ rendering is no longer reproducible — the same chart + values produce different output on different clusters;
- ⛔ `helm diff` becomes meaningless.

Use it only when you genuinely need existing cluster state and you accept those costs (the classic case: preserving a generated password across upgrades — for which an `immutable` Secret or an external secret store is still better).

---

## 5 · ⭐⭐ Whitespace control — the source of most broken YAML

**YAML is whitespace-sensitive. Go templates emit whitespace by default. The combination is why your first chart does not render.**

### The rules

| Syntax | Effect |
|---|---|
| `{{` … `}}` | emits the action's output, **plus** any literal whitespace around it in the file |
| `{{-` | ⭐ **trim all whitespace immediately BEFORE** the action, **including the newline** |
| `-}}` | ⭐ **trim all whitespace immediately AFTER** the action, **including the newline** |

### Watch it happen

Given:

```yaml
# values.yaml
features:
  metrics: true
```

```yaml
# templates/deployment.yaml — ⛔ NO trimming
spec:
  containers:
    - name: app
{{ if .Values.features.metrics }}
      ports:
        - containerPort: 9090
{{ end }}
      image: x
```

renders as:

```yaml
spec:
  containers:
    - name: app

      ports:
        - containerPort: 9090

      image: x
```

Two **blank lines**. In this case YAML tolerates it. Now change the condition to false:

```yaml
spec:
  containers:
    - name: app


      image: x
```

Still tolerable — but move that `{{ if }}` inside an indented block and the blank line lands at the **wrong indentation level**, and YAML fails:

```
Error: YAML parse error on demo/templates/deployment.yaml:
error converting YAML to JSON: yaml: line 14: did not find expected key
```

### ⭐ The fix — trim both sides of a block control

```yaml
spec:
  containers:
    - name: app
      {{- if .Values.features.metrics }}
      ports:
        - containerPort: 9090
      {{- end }}
      image: x
```

- `{{- if …}}` — the `-` eats the newline **before** it, so the previous line's newline is not doubled
- `{{- end }}` — same
- **No `-}}`** on either — you *want* the newline after `}}` so the next line starts fresh

Renders correctly in both cases:

```yaml
# metrics: true
spec:
  containers:
    - name: app
      ports:
        - containerPort: 9090
      image: x

# metrics: false
spec:
  containers:
    - name: app
      image: x
```

### ⭐⭐ The rule of thumb that gets you 90% of the way

> **Put `{{-` on the left of every block action (`if`, `range`, `with`, `end`, `else`, `define`, `template`, `include`), and leave the right side alone.**
>
> `{{- if …}}` … `{{- end }}`
>
> Then **look at the rendered output** and add `-}}` only where you can see a problem. Do not sprinkle `-}}` defensively — over-trimming collapses lines together and produces *worse* errors than under-trimming, because it silently joins two YAML keys onto one line.

**Over-trimming example:**

```yaml
metadata:
  name: {{- .Release.Name -}}
  labels: {}
```
```yaml
metadata:
  name:shop          # ⛔⛔ the -}} ate the newline AND the indentation
  labels: {}
```

`name:shop` is not a key-value pair — it is a scalar string. The API server rejects it, and the error message points at a line number that does not obviously correspond to your mistake. ⛔ **Never use `-}}` on a value you are emitting onto its own line unless you mean to join lines.**

---

## 6 · `if` / `else` and **the falsy rules**

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
…
{{- else if .Values.ingress.legacy }}
…
{{- else }}
# nothing
{{- end }}
```

### ⭐ What counts as false

Go templates use Go's truth rules. **False** is:

| Value | Falsy? |
|---|---|
| `false` | ✅ yes |
| `0` (any numeric zero — int, float) | ✅ yes |
| `""` (empty string) | ✅ yes |
| `nil` / a missing key | ✅ yes |
| ⭐ **an empty list, map, or slice** | ✅ **yes** |
| everything else | ❌ truthy |

### ⭐⭐ The two traps this creates

**Trap 1 — `0` is falsy, so you cannot test "is this set?"**

```yaml
# values.yaml
replicaCount: 0        # ⭐ a legitimate value: scale to zero

{{- if .Values.replicaCount }}
  replicas: {{ .Values.replicaCount }}
{{- end }}
```

With `replicaCount: 0` the block is **skipped entirely**, so `replicas` is never emitted and Kubernetes defaults it to **1**. ⛔ You asked for zero replicas and got one — and the rendered YAML gives you no clue why.

**The fix — test for presence, not truthiness:**

```yaml
{{- if not (kindIs "invalid" .Values.replicaCount) }}
  replicas: {{ .Values.replicaCount }}
{{- end }}

# or, more commonly and more readably, use `hasKey`:
{{- if hasKey .Values "replicaCount" }}
  replicas: {{ .Values.replicaCount }}
{{- end }}

# or, simplest: always emit it and make the default explicit in values.yaml
  replicas: {{ .Values.replicaCount }}
```

⭐ **The general lesson:** `if` tests *truthiness*, and truthiness conflates "absent" with "zero" with "empty". When the distinction matters — and for numbers it always does — test for the thing you mean.

**Trap 2 — an empty list is falsy, which is usually what you want but sometimes isn't**

```yaml
{{- if .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml .Values.nodeSelector | nindent 8 }}
{{- end }}
```

`nodeSelector: {}` → falsy → block skipped → no `nodeSelector` key at all. ✅ **Correct**, and this is the idiomatic pattern for optional maps. But if you *need* the key to exist (rare — some controllers check presence), this silently omits it.

### `and` / `or` / `not`

```yaml
{{- if and .Values.ingress.enabled .Values.ingress.tls }}
{{- if or (eq .Values.env "prod") (eq .Values.env "staging") }}
{{- if not .Values.debug }}
{{- if eq .Values.mode "strict" }}        # eq, ne, lt, le, gt, ge
```

⭐ **`and` and `or` do NOT short-circuit** in older Go template versions. `{{ if and .Values.a .Values.a.b }}` can panic on the second operand even when the first is false. Write it as nested `if`s when the second operand depends on the first:

```yaml
{{- if .Values.a }}
  {{- if .Values.a.b }}
```

---

## 7 · `range` — lists, maps, and the `else` branch

### Over a list

```yaml
# values.yaml
ports:
  - { name: http,    containerPort: 8080 }
  - { name: metrics, containerPort: 9090 }
```

```yaml
      ports:
        {{- range .Values.ports }}
        - name: {{ .name }}
          containerPort: {{ .containerPort }}
          protocol: TCP
        {{- end }}
```

⭐ Inside the `range`, **`.` is the current element.** `.name` is the element's `name`. To reach values outside, use `$` (§2).

```yaml
        {{- range .Values.ports }}
        - name: {{ .name }}
          containerPort: {{ .containerPort }}
          image: {{ $.Values.image.repository }}      # ✅ $ escapes the range
        {{- end }}
```

### Over a map — with index and value

```yaml
# values.yaml
env:
  LOG_LEVEL: info
  REGION: ap-south-1
```

```yaml
          env:
            {{- range $key, $value := .Values.env }}
            - name: {{ $key }}
              value: {{ $value | quote }}
            {{- end }}
```

⭐ **`range $k, $v := map`** gives you both. Without the variables, `.` is the *value* and you have no access to the key.

⚠️ **Map iteration order is not guaranteed.** Go randomises it. So the rendered `env:` list can come out in a different order on each render — which makes `helm diff` noisy for reasons that are not real changes. **Fix it by sorting:**

```yaml
            {{- range $key, $value := .Values.env | toYaml | fromYaml }}
```
or, properly:
```yaml
            {{- range $key := keys .Values.env | sortAlpha }}
            - name: {{ $key }}
              value: {{ index $.Values.env $key | quote }}
            {{- end }}
```

⭐ **Deterministic output is a correctness property, not tidiness** — same reason as §4's ban on `randAlphaNum`. Non-deterministic rendering breaks diffing, breaks `--atomic` rollback, and makes you unable to prove what you deployed.

### The `else` branch — for empty collections

```yaml
        {{- range .Values.extraVolumes }}
        - {{ toYaml . | nindent 10 }}
        {{- else }}
        # no extra volumes configured
        {{- end }}
```

`{{- else }}` inside a `range` runs **only if the collection is empty**. Useful for emitting a placeholder comment, or for failing loudly:

```yaml
        {{- range .Values.endpoints }}
        …
        {{- else }}
        {{- fail "at least one endpoint must be configured" }}
        {{- end }}
```

---

## 8 · `with` — rebinding the dot (and its trap)

```yaml
{{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
{{- end }}
```

`with` sets `.` to the given value **for the duration of the block**, and **skips the block entirely if the value is falsy**. So this renders `resources:` only if `.Values.resources` is non-empty — a convenient two-in-one.

### ⛔ The trap

Inside `with`, `.` is the *bound value*, so `.Values` is gone:

```yaml
{{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          image: {{ .Values.image.repository }}     # ⛔ nil pointer
{{- end }}
```

Same fix: `$.Values.image.repository`.

⭐ **When to prefer `with` over `if`:** when you need both the emptiness check *and* the rebind — the `resources`, `nodeSelector`, `affinity`, `tolerations` and `podSecurityContext` blocks. It is the standard idiom in the charts `helm create` generates, so you will read it constantly.

**When to prefer `if`:** when you want the check without changing scope, or when you need `else` (a `with` block can have `{{- else }}`, but it runs when the value is *falsy*, which is a different meaning from `if`'s `else` and confuses readers).

---

## 9 · ⭐⭐ `define` / `template` / `include` — why `include` almost always wins

### `define` — declare a named template

Conventionally in `templates/_helpers.tpl` (leading `_` → renders no output):

```yaml
{{/* templates/_helpers.tpl */}}

{{- define "demo.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "demo.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "demo.labels" -}}
helm.sh/chart: {{ include "demo.chart" . }}
{{ include "demo.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "demo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "demo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
```

⭐ **Note the convention:** names are prefixed with the chart name (`demo.`). Named templates are **global across the whole render** — including subcharts — so unprefixed names like `"name"` or `"labels"` collide with subcharts' helpers. ⛔ That collision produces baffling output where your labels come from someone else's chart. **Always prefix.**

### `template` — invoke it (an *action*)

```yaml
metadata:
  name: {{ template "demo.fullname" . }}
```

### ⭐⭐ `include` — invoke it (a *function*)

```yaml
metadata:
  name: {{ include "demo.fullname" . }}
  labels:
    {{- include "demo.labels" . | nindent 4 }}
```

### Why `include` wins — the one reason that matters

**`template` is an action; `include` is a function.** Only functions can be **piped**.

```yaml
# ⛔ IMPOSSIBLE with template
{{ template "demo.labels" . | nindent 4 }}
#   → error: unexpected "|" in command

# ✅ works with include
{{- include "demo.labels" . | nindent 4 }}
```

Since **almost every** multi-line helper needs `nindent` (or `quote`, or `toYaml`), `include` is what you want essentially always. ⛔ `template` survives in old charts and in `NOTES.txt` where no piping is needed; in new code, use `include`.

### Passing the dot — the argument is explicit

```yaml
{{ include "demo.fullname" . }}
```

That trailing `.` is **the argument**. Named templates receive whatever you pass as *their* `.`. If you forget it, the helper's `.` is empty and every `.Values` inside it is nil:

```yaml
{{ include "demo.fullname" }}      # ⛔ the helper gets no context
#   → nil pointer evaluating interface {}.Values
```

⭐ **`nil pointer evaluating interface {}.Values` inside a helper almost always means you forgot the `.`** at the call site — not that the helper is wrong.

### Passing a dict — when the helper needs more than the root

```yaml
{{- include "demo.image" (dict "image" .Values.api.image "root" $) }}
```
```yaml
{{- define "demo.image" -}}
{{- $img := .image -}}
{{ printf "%s:%s" $img.repository (.tag | default .root.Chart.AppVersion) }}
{{- end -}}
```

⭐ **The `"root" $` convention** is how you hand a helper access to the root context alongside its specific arguments — the same `$` escape as §2, passed explicitly.

---

## 10 · The `toYaml` + `nindent` pattern

The most-used two lines in all of Helm:

```yaml
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

### What each part does

1. **`toYaml .Values.resources`** — converts the map into a multi-line YAML **string**:
   ```
   limits:
     cpu: "2"
     memory: 4Gi
   requests:
     cpu: 500m
     memory: 1Gi
   ```
2. **`nindent 12`** — emits a **newline**, then indents **every** line by 12 spaces.

Result:

```yaml
          resources:
            limits:
              cpu: "2"
              memory: 4Gi
            requests:
              cpu: 500m
              memory: 1Gi
```

### ⭐ Why `nindent` and not `indent`

`indent N` indents every line **but does not emit a leading newline**. So:

```yaml
          resources:
            {{ toYaml .Values.resources | indent 12 }}
```
```yaml
          resources:
                        limits:            # ⛔ 12 spaces for the newline YOU wrote
              cpu: "2"                     #    plus 12 more from indent
```

The first line gets your literal indentation **plus** `indent`'s 12; subsequent lines get only 12. The result is misaligned and YAML fails.

**`nindent N` = `"\n" + indent N`** — it starts a fresh line, so the first line is indented exactly N and every following line matches. ⭐ **Use `nindent` unless you are deliberately joining onto the current line**, which is rare.

### ⭐⭐ How to choose N — count, don't guess

`N` is the **column the content should start at**, counted from column 0 of the rendered file — *not* the indentation of the `{{` in your template.

```yaml
spec:
  template:
    spec:
      containers:
        - name: app
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
#           ↑
#   count the spaces before this: "resources:" is at column 10,
#   so its CHILDREN go at column 12.  → nindent 12
```

**The reliable method:** put the block in with a wrong number, run `helm template`, look at the output, and fix it. Do not try to compute it in your head — everyone is off by two at least once a day.

### The `{{-` on the left matters here

`{{- toYaml … | nindent 12 }}` — the `{{-` trims the newline *before* the action, and `nindent` supplies its own newline. Without the `{{-` you get a blank line:

```yaml
          resources:

            limits:
```

Usually harmless in YAML, occasionally not (a blank line inside a block can end it). ⭐ **Always `{{-` before a `nindent` pipeline.**

---

## 11 · Comments, built-in objects, and `.Files`

### Comments — three kinds, and only one is safe

```yaml
{{/* a template comment — REMOVED from the output */}}

# a YAML comment — PASSES THROUGH into the rendered manifest

{{- /* a trimmed template comment */ -}}
```

⭐ **Use `{{/* */}}` for anything you do not want in the cluster.** `#` comments appear in the applied YAML and in `kubectl get … -o yaml`. That is usually fine and often helpful — but never put a secret, a ticket URL, or a rude note about a teammate in a `#` comment. It becomes a ConfigMap-visible artifact.

### Multi-line template comments

```yaml
{{/*
This block is conditional because the controller rejects an empty
nodeSelector in Kubernetes < 1.24. See issue #1234.
*/}}
```

### `.Files` — pulling non-template files into a manifest

```yaml
# chart/
#   config/app.properties
#   config/log4j2.xml

apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "demo.fullname" . }}-config
data:
  app.properties: |-
    {{- .Files.Get "config/app.properties" | nindent 4 }}

# or every file in a glob, as ConfigMap keys:
data:
{{- range $path, $_ := .Files.Glob "config/**" }}
  {{ base $path }}: |-
    {{- $.Files.Get $path | nindent 4 }}
{{- end }}
```

And into a Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "demo.fullname" . }}-files
type: Opaque
data:
{{ (.Files.Glob "secrets/*").AsSecrets | indent 2 }}
```

⚠️ **`.Files` cannot read outside the chart directory**, cannot read `templates/`, and cannot read files excluded by `.helmignore`. ⛔ And never put real secrets in the chart — `.Files.AsSecrets` base64-encodes, which is **encoding, not encryption**. Use an external secret store.

### `.Capabilities` — writing charts that work across versions

```yaml
{{- if .Capabilities.APIVersions.Has "autoscaling/v2" }}
apiVersion: autoscaling/v2
{{- else }}
apiVersion: autoscaling/v2beta2
{{- end }}
kind: HorizontalPodAutoscaler
```

```yaml
{{- if semverCompare ">=1.25-0" .Capabilities.KubeVersion.Version }}
# PodDisruptionBudget is policy/v1 from 1.21; batch/v1 CronJob from 1.21
{{- end }}
```

⭐ **`.Capabilities` reflects the cluster Helm is talking to** — which is real during `helm install --dry-run` and **synthetic during `helm template`** (it uses `--kube-version`, defaulting to a built-in guess). So a `helm template` render can differ from what the cluster would accept. Always `--dry-run` before you trust version-conditional logic:

```bash
helm template demo ./chart --kube-version 1.28.0
helm install demo ./chart --dry-run          # uses the real cluster's capabilities
```

---

## 12 · ⭐⭐ The debugging loop

**Memorise this. It turns template debugging from guesswork into a two-minute exercise.**

```
   ┌──────────────────────────────────────────────────────────────────┐
   │  SYMPTOM: helm upgrade / install fails, or the manifest is wrong │
   └───────────────────────────────┬──────────────────────────────────┘
                                   ▼
   ①  helm lint ./chart                       → catches structural problems first
                                   ▼
   ②  helm template r ./chart --debug         → ⭐ the computed .Values, printed
                                   ▼
   ③  helm template r ./chart \
        --show-only templates/deployment.yaml → ONLY the file you care about
                                   ▼
   ④  helm template r ./chart --show-only … | yamllint -    → is it valid YAML?
                                   ▼
   ⑤  Read the RENDERED output, not the template.
      ⭐ The bug is in what came out, and the template only tells you why.
                                   ▼
   ⑥  Still stuck? Bisect: comment out half the template with {{/* */}}
      and re-render. Two or three iterations finds any action.
                                   ▼
   ⑦  helm install r ./chart --dry-run --debug → validates against the API server
```

### The commands, with what each one tells you

```bash
# ① structural lint — missing Chart.yaml fields, bad YAML, unknown template funcs
helm lint ./chart
helm lint ./chart --strict          # ⭐ also fails on warnings
helm lint ./chart --set replicaCount=abc --values values-prod.yaml
```
```
==> Linting ./chart
[INFO] Chart.yaml: icon is recommended
Error: 1 chart(s) linted, 1 chart(s) failed
```

```bash
# ② ⭐⭐ see the VALUES the engine actually got — this is the command that
#    ends most "why is my value being ignored" mysteries
helm template r ./chart --debug 2>&1 | sed -n '/COMPUTED VALUES/,/HOOKS/p'
```

If your value is not in `COMPUTED VALUES`, the problem is **not in the template** — it is in your values file, your `--set` syntax, or your key path. ⭐ **Check here before reading a single line of template.**

```bash
# ③ render one file only
helm template r ./chart --show-only templates/deployment.yaml

# ④ validate the YAML is YAML
helm template r ./chart --show-only templates/deployment.yaml | yamllint -
helm template r ./chart | yq eval-all '.kind' -        # does every doc parse?

# ⑤ the schema check, if the chart has values.schema.json
helm template r ./chart -f values.yaml                  # fails on schema violation

# ⑦ against the real cluster
helm install r ./chart --dry-run --debug
kubectl apply --dry-run=server -f <(helm template r ./chart)   # ⭐ API-server validation
```

### ⭐ Reading the error message — it tells you more than you think

```
Error: YAML parse error on demo/templates/deployment.yaml:
error converting YAML to JSON: yaml: line 42: did not find expected key
```

| Part | What it means |
|---|---|
| `YAML parse error on demo/templates/deployment.yaml` | which **template file** — but the line number is in the **rendered** output, not the template |
| `line 42` | ⭐ **line 42 of the rendered YAML.** Pipe `helm template … --show-only` through `nl -ba` and go to line 42 |
| `did not find expected key` | almost always **indentation** — a `nindent` count is wrong, or a `{{-`/`-}}` joined two lines |

```bash
# the move that resolves it every time
helm template r ./chart --show-only templates/deployment.yaml | nl -ba | sed -n '35,50p'
```

Common messages and what they mean:

| Error | Real cause |
|---|---|
| `did not find expected key` | indentation — wrong `nindent`, or over-trimmed whitespace joining lines |
| `mapping values are not allowed in this context` | a `:` appeared where YAML did not expect one — usually an unquoted string containing a colon (`{{ .Values.url }}` → `http://x`). ⭐ **Fix: `quote`** |
| `nil pointer evaluating interface {}.X` | ⭐ you used `.X` where `.` had been rebound by `range`/`with`, or forgot the `.` argument to `include` |
| `function "foo" not defined` | a Sprig function misspelled, or a `define` block name that does not exist (typo, or the helper file is not `_helpers.tpl` and was not rendered) |
| `unexpected "}" in operand` | unbalanced `{{ }}`, or a `}` inside a string in the action |
| `error converting YAML to JSON: yaml: … found character that cannot start any token` | ⭐ a **tab** character. YAML forbids tabs. Templates that came from a copy-paste often contain them |

---

## 13 · The fifteen mistakes everyone makes

| # | Mistake | Symptom | Fix |
|---|---|---|---|
| **1** | Using `.Values` inside `range`/`with` | `nil pointer evaluating interface {}.Values` | ⭐ use `$.Values` |
| **2** | `indent` instead of `nindent` | first line over-indented, YAML parse error | `nindent` (§10) |
| **3** | Wrong `nindent` count | `did not find expected key` | render, `nl -ba`, count (§12) |
| **4** | Forgetting the `.` argument to `include` | `nil pointer … .Values` inside the helper | `{{ include "x" . }}` |
| **5** | `template` when you need to pipe | `unexpected "\|" in command` | ⭐ `include` (§9) |
| **6** | Unprefixed `define` names | your labels come from a subchart | prefix with the chart name |
| **7** | `randAlphaNum` / `uuidv4` / `now` | diff is always dirty; rollback breaks; passwords rotate on upgrade | ⛔ never — generate outside the chart (§4) |
| **8** | Not quoting a value that contains `:` | `mapping values are not allowed in this context` | `{{ .Values.url \| quote }}` |
| **9** | `if .Values.count` where `count: 0` is valid | block silently skipped, K8s default applies | `hasKey` / `kindIs "invalid"` (§6) |
| **10** | Iterating a map without sorting | ⭐ diff noise — order changes every render | `keys … \| sortAlpha` (§7) |
| **11** | Missing `{{-` before `nindent` | blank lines in output | `{{- toYaml … \| nindent N }}` |
| **12** | Over-trimming with `-}}` | two YAML keys joined onto one line | remove the `-}}` (§5) |
| **13** | A tab character anywhere | `found character that cannot start any token` | spaces only, always |
| **14** | Trusting `helm template` for version-conditional logic | works locally, fails on the cluster | `--dry-run` / `--kube-version` (§11) |
| **15** | `<no value>` in the rendered output | image named `<no value>`, pull fails minutes later | `default` or ⭐ `required` (§2) |

⭐ **Notice that 1–6, 9, 11, 12 and 15 are all the same underlying problem:** the template engine is YAML-agnostic and gives you no feedback until the API server rejects the result. That is why §12's loop — render locally, read the *output* — is the skill, and the table above is just its index.

---

## 14 · 🔨 Tasks

> **4.1** Run `helm create demo` and read `templates/deployment.yaml`, `templates/_helpers.tpl` and `templates/service.yaml`. For every `{{ }}` action in `deployment.yaml`, write one sentence saying what it evaluates to. Then change `nameOverride` in `values.yaml` and explain, from the helpers, exactly how the rendered `metadata.name` changed.

> **4.2** Reproduce the `nil pointer evaluating interface {}.Values` error deliberately, in two different ways. Fix both, and state the single rule that covers both fixes.

> **4.3** Build a template that renders a `resources:` block, and get the `nindent` count wrong on purpose. Report the exact error message and line number, then use the §12 loop to find and fix it. Describe what the line number referred to — the template or the output?

> **4.4** Write a helper `demo.env` that renders `.Values.env` (a map) as a Kubernetes `env:` list. Make the output deterministic, and prove it is by rendering ten times and diffing.

> **4.5** Demonstrate the `replicaCount: 0` trap end to end: a template, a values file, the rendered output, and the Deployment Kubernetes actually creates. Then fix it two different ways and say which you would ship and why.

> **4.6** Write a chart fragment that produces **different output on two consecutive renders** using only built-in functions. Explain each of the three concrete production problems that causes, then rewrite it deterministically.

> **4.7** Convert a `{{ template … }}` call into a piped `{{ include … | nindent N }}`. Explain precisely why the first form cannot be piped, in terms of what the two constructs are.

> **4.8** Use `.Files.Glob` to build a ConfigMap from every file in a `config/` directory in your chart. Then make it fail in a specific way by adding a file that `.helmignore` excludes, and explain the failure.

> **4.9** Write a version-conditional template using `.Capabilities.APIVersions.Has`. Render it with `--kube-version 1.20.0` and with `--kube-version 1.29.0`, and report the difference. Then explain why `helm template` alone is not sufficient evidence that it will work on your cluster.

> **4.10** ⭐⭐ A teammate's chart renders this, and the API server rejects it:
> ```yaml
> spec:
>   template:
>     spec:
>       containers:
>         - name: app
>           env:
>             - name: API_URL
>           value: http://shop-api:8080
>           image: <no value>
> ```
> Diagnose **all four** distinct defects from this output alone, name the template mistake behind each, and write the corrected template.

<details>
<summary>👉 Answers</summary>

**4.1** `helm create demo` produces a chart whose `deployment.yaml` contains, in order:

| Action | Evaluates to |
|---|---|
| `{{- include "demo.name" . }}` | the helper from `_helpers.tpl`: `default .Chart.Name .Values.nameOverride \| trunc 63 \| trimSuffix "-"` → `"demo"` unless `nameOverride` is set |
| `{{- include "demo.fullname" . }}` | `printf "%s-%s" .Release.Name $name \| trunc 63 \| trimSuffix "-"` → `"myrel-demo"` |
| `{{- include "demo.labels" . \| nindent 4 }}` | the standard label set (chart, selectorLabels, version, managed-by), indented 4 |
| `{{- .Values.replicaCount \| default 1 }}` | the replica count |
| `{{- include "demo.selectorLabels" . \| nindent 6 }}` | `app.kubernetes.io/name` + `app.kubernetes.io/instance` — ⭐ the labels the Service selects on |
| `{{- with .Values.image }}` … `{{- end }}` | binds `.` to the image map; skipped if empty |
| `{{ .repository }}:{{ .tag \| default $.Chart.AppVersion }}` | ⭐ note the `$.` — inside `with`, `.` is the image map, so `.Chart` would be nil |
| `{{- toYaml . \| nindent 12 }}` for resources/nodeSelector/affinity/tolerations | the optional blocks |
| `{{- if .Values.serviceAccount.create }}` | whether to emit `serviceAccountName` |

**How `nameOverride` flows to `metadata.name`:**

```
Values.nameOverride = "shopapi"
        │
        ▼
define "demo.name"   →  default .Chart.Name .Values.nameOverride
                     →  "shopapi"            (default returns the FIRST non-empty,
                     →                        and .Values.nameOverride is non-empty)
                     →  trunc 63 | trimSuffix "-"  →  "shopapi"
        │
        ▼
define "demo.fullname" →  fullnameOverride is empty, so the else branch:
                       →  $name = "shopapi"
                       →  printf "%s-%s" .Release.Name $name  →  "myrel-shopapi"
                       →  trunc 63 | trimSuffix "-"           →  "myrel-shopapi"
        │
        ▼
metadata.name: myrel-shopapi
        │
        ▼  (and, separately)
define "demo.selectorLabels" →  app.kubernetes.io/name: shopapi
                              →  app.kubernetes.io/instance: myrel
```

⭐ **Three things worth noticing, because they are the design.**

1. **`trunc 63 | trimSuffix "-"` appears in both helpers** and is not decoration. Kubernetes names that become DNS labels are limited to **63 characters**, and `trunc` can leave a trailing hyphen — which is **invalid** in a DNS label. So the pair is the standard guard. A release named `my-very-long-environment-name` plus a chart named `my-very-long-service-chart` will hit it, and without the guard you get an API-server rejection at install time rather than a truncation.
2. **`nameOverride` changes the *name* label; `fullnameOverride` replaces the *whole* fullname.** So `nameOverride` still gets the release prefix (multi-instance safe), while `fullnameOverride` gives you exact control (needed when something external must reference a fixed name — a Service that another team's Ingress points at, for instance).
3. ⛔ **Changing `nameOverride` on an existing release changes `selectorLabels`, and Deployment selectors are IMMUTABLE.** The upgrade fails with `field is immutable`. That is a real production incident from a "harmless" values change, and it is covered in [`13-UPGRADE-PATTERNS-ZERO-DOWNTIME.md`](13-UPGRADE-PATTERNS-ZERO-DOWNTIME.md). The short version: **choose `nameOverride` before the first install and never change it.**

**4.2** Two independent ways to produce the same error.

**Way 1 — `.` rebound by `range`:**

```yaml
# values.yaml
env:
  - { name: LOG_LEVEL, value: info }
defaults:
  region: ap-south-1
```
```yaml
# templates/deployment.yaml
          env:
            {{- range .Values.env }}
            - name: {{ .name }}
              value: {{ .value }}
              region: {{ .Values.defaults.region }}      # ⛔
            {{- end }}
```
```bash
helm template r ./demo
# Error: … executing "demo/templates/deployment.yaml" at <.Values.defaults.region>:
#        nil pointer evaluating interface {}.defaults
```

**Why:** inside `range .Values.env`, `.` is the current **list element** — `{name: LOG_LEVEL, value: info}`. That map has no `Values` key, so `.Values` is nil, and `.Values.defaults` dereferences nil. ⭐ Note the error says `interface {}.defaults` — it names the **field that failed on the nil**, not the field that was nil. Reading it as *"my `defaults` value is wrong"* sends you into `values.yaml` when the bug is in the template.

**Fix:** `{{ $.Values.defaults.region }}`

**Way 2 — `.` rebound by `with`:**

```yaml
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          image: {{ .Values.image.repository }}          # ⛔ same error, different block
          {{- end }}
```

**Why:** `with` binds `.` to `.Values.resources` for the whole block. Same mechanism, different action.

**Fix:** `{{ $.Values.image.repository }}`

**(And a third, closely related, way — the one that produces the identical message with a different cause):**

```yaml
{{ include "demo.labels" }}        # ⛔ missing the trailing "."
```
The helper receives an **empty** context, so `.Values` inside it is nil → the same error, but pointing at a line in `_helpers.tpl`. ⭐ Check the file path in the error message: if it names `_helpers.tpl`, the bug is at the **call site** (a missing `.`), not in the helper.

**The single rule that covers all three:**

> ⭐⭐ **`.` is the current scope, not the root. `$` is always the root. Any action that creates a scope — `range`, `with`, or a `define`/`include` call — separates the two, and every reference to `.Values`, `.Release`, `.Chart` or `.Capabilities` from inside that scope must use `$`.**

And its corollary for `include`: **the root context is not inherited, it is passed.** `{{ include "x" . }}` — that `.` is an explicit argument, and forgetting it hands the helper nothing.

**4.3**

```yaml
# templates/deployment.yaml — deliberately wrong nindent
spec:
  template:
    spec:
      containers:
        - name: app
          resources:
            {{- toYaml .Values.resources | nindent 8 }}      # ⛔ should be 12
```

```bash
helm template r ./demo --show-only templates/deployment.yaml | nl -ba | sed -n '28,40p'
```
```
    28        containers:
    29        - name: app
    30          resources:
    31        limits:
    32          cpu: "2"
    33          memory: 4Gi
```

`limits:` is at column 8, but it is a **child of `resources:`** (column 10), so it must be at column 12. YAML therefore reads line 31 as ending the `containers` list item, and the following `cpu:` becomes an unexpected key at the wrong level:

```
Error: YAML parse error on demo/templates/deployment.yaml:
error converting YAML to JSON: yaml: line 31: did not find expected key
```

**The §12 loop that finds it:**

```bash
# ① is the chart structurally sound?
helm lint ./demo                       # passes — lint does NOT deeply validate rendered YAML

# ② are the values what I think?
helm template r ./demo --debug 2>&1 | sed -n '/COMPUTED VALUES/,/HOOKS/p' | grep -A5 resources

# ③④ render the one file and validate it
helm template r ./demo --show-only templates/deployment.yaml | yamllint -
#   31:9  error  wrong indentation: expected 12 but found 8  (indentation)

# ⑤ ⭐ read the OUTPUT with line numbers — the error's line 31 is here
helm template r ./demo --show-only templates/deployment.yaml | nl -ba | sed -n '31p'
```

Fix: `nindent 12`.

**What the line number referred to — and this is the point of the task:**

⭐ **`line 31` is a line number in the RENDERED OUTPUT, not in your template file.** The template's `nindent` is on its own line (say line 14 of `deployment.yaml`); the error names line 31 of the *result*. The API server never sees your template — it sees the rendered string — so every line number in every Helm YAML error refers to output.

That is why step ⑤ pipes through `nl -ba`: **you must number the rendered document to use the error at all.** People who grep their template for "line 31" find nothing, conclude the error is meaningless, and start editing at random. `yamllint` is the shortcut because it reports the same thing plus the *expected* indentation, which is the number you need.

**4.4** The helper, deterministic:

```yaml
{{/* templates/_helpers.tpl */}}
{{- define "demo.env" -}}
{{- range $key := keys .Values.env | sortAlpha }}
- name: {{ $key }}
  value: {{ index $.Values.env $key | quote }}
{{- end }}
{{- end -}}
```

```yaml
# templates/deployment.yaml
          env:
            {{- include "demo.env" . | nindent 12 }}
```

**Three deliberate choices:**

1. ⭐ **`keys … | sortAlpha` instead of `range $k, $v := .Values.env`.** Go **randomises map iteration order**, so ranging a map directly produces a different `env:` order on each render. Sorting makes the output a pure function of the input.
2. ⭐ **`$.Values.env` inside the range.** `.` is rebound to the loop variable's context; `$` reaches the root (§2). Note that with `range $key := …` the loop variable *is* `$key`, but `$` is still needed for anything outside.
3. ⭐ **`| quote` on the value.** Without it, `LOG_LEVEL: info` is fine but `API_URL: http://shop-api:8080` produces `mapping values are not allowed in this context` (§13 mistake 8), and `PORT: 8080` becomes an integer where Kubernetes requires a string. **Always quote env values.**

**Proving determinism:**

```bash
for i in $(seq 1 10); do
  helm template r ./demo --show-only templates/deployment.yaml | sha256sum
done | sort -u | wc -l
# → 1     ✅ ten renders, one distinct hash

# and the negative control — remove | sortAlpha and repeat:
# → 3 or more distinct hashes across ten renders  ⛔ non-deterministic
```

⭐ **Run the negative control.** It is what proves the test is actually testing something: with the sort removed, the same command yields several distinct hashes. A determinism check you have never seen fail is not a check.

**Why this matters beyond tidiness** — three concrete costs of a non-deterministic render:

- ⛔ **`helm diff` is permanently dirty.** You cannot use it to review an upgrade, because it always shows a change. That removes your main safety net on a large chart ([`13-UPGRADE-PATTERNS-ZERO-DOWNTIME.md`](13-UPGRADE-PATTERNS-ZERO-DOWNTIME.md)).
- ⛔ **GitOps drift detection fires forever.** Argo CD compares desired (rendered) to live. A render that changes every time means the app is **permanently `OutOfSync`**, so teams disable auto-sync — and then real drift goes unnoticed.
- ⛔ **Reproducibility is gone.** You cannot prove what you deployed, because re-rendering the same commit + values does not reproduce it.

**4.5** The trap, end to end.

```yaml
# templates/deployment.yaml
spec:
  {{- if .Values.replicaCount }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
```

```yaml
# values.yaml
replicaCount: 0
```

```bash
helm template r ./demo --show-only templates/deployment.yaml | grep -n replicas
# (no output)          ⛔ the key is ABSENT from the rendered manifest
```

```bash
kubectl apply -f <(helm template r ./demo) --dry-run=server -o yaml | grep -A3 '^spec:' 
# or, after a real apply:
kubectl get deployment demo -o jsonpath='{.spec.replicas}{"\n"}'
# → 1                  ⛔⛔ Kubernetes defaulted it
```

**Why, mechanically:** `if` uses Go truth rules, and **`0` is falsy** (§6). So the block is skipped and `replicas:` is never emitted. Kubernetes then applies the API default for `Deployment.spec.replicas`, which is **1**. You asked for zero and got one — with no error, no warning, and nothing in the rendered YAML to indicate anything was dropped.

**Fix 1 — test for presence, not truthiness:**

```yaml
spec:
  {{- if hasKey .Values "replicaCount" }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
```

**Fix 2 — always emit, and make the default explicit in `values.yaml`:**

```yaml
# values.yaml
replicaCount: 1        # ⭐ the default lives in values, where it is visible
```
```yaml
spec:
  replicas: {{ .Values.replicaCount }}
```

**Fix 3 — `required`, if there is no sensible default:**

```yaml
spec:
  replicas: {{ required "replicaCount must be set explicitly" .Values.replicaCount }}
```

⭐ **Which I would ship: Fix 2.** Reasons, in order of importance:

1. **It has no conditional, so it has no falsy-value bug class at all.** Fixes 1 and 3 are correct, but they leave a `{{- if }}` in the file — and the next person to add `{{- if .Values.somethingNumeric }}` repeats the mistake. Removing the conditional removes the possibility.
2. **The default becomes visible and reviewable.** With Fix 2, "what happens if I don't set this?" is answered by reading `values.yaml`. With Fix 1, the answer is "the Kubernetes API default", which requires knowing the API — and which is exactly the behaviour that just surprised us.
3. **It renders identically for every input**, so diffs are meaningful.

⭐ **Fix 3 (`required`) is right when there is genuinely no safe default** — a `storageClassName` in a production chart, an `image.digest`, a database host. The rule: **`required` for values where a guess is dangerous; an explicit default in `values.yaml` for values where a guess is fine.** `replicaCount` is the second kind; `image.digest` is the first.

**4.6** Non-deterministic fragment, three ways:

```yaml
# ① random suffix
metadata:
  name: {{ .Release.Name }}-{{ randAlphaNum 5 | lower }}

# ② timestamp
  annotations:
    deployed-at: {{ now | date "2006-01-02T15:04:05Z" | quote }}

# ③ UUID
    correlation-id: {{ uuidv4 | quote }}
```

```bash
helm template r ./demo --show-only templates/deployment.yaml | sha256sum
helm template r ./demo --show-only templates/deployment.yaml | sha256sum
# → two different hashes, same chart, same values   ⛔
```

**The three concrete production problems:**

**① Rollback cannot restore the previous state.** ⭐ This is the worst one. `helm rollback` **re-renders** the chart at the stored revision's values and applies the result. Re-rendering `randAlphaNum 5` produces a *third* value — neither the current one nor the one you are rolling back to. So the rollback creates a Deployment with a **new name**, which means: a new ReplicaSet, new pods, a new set of PVC bindings if there are any, and the Service selector may no longer match anything. ⛔ **Your rollback, the thing that exists for the emergency, silently deploys something nobody has ever seen.** The same applies to `--atomic`, which is an automatic rollback on failure.

**② Every upgrade is a change to every dependent object.** If the name or a checksum feeds anything else — a Service selector, an Ingress backend, a `checksum/config` annotation used to trigger pod restarts — then every `helm upgrade` mutates it, causing **rolling restarts of workloads you did not intend to touch**. A `deployed-at: {{ now }}` annotation on a pod template is the classic: it changes every upgrade, so the pod template hash changes, so **every pod restarts on every deploy**, which turns a config tweak into an outage window.

**③ You cannot prove what you deployed.** Reproducibility is the basis of auditability. Given the chart commit and the values, you should be able to re-render and get byte-identical output to what is in the cluster. With any of these three, re-rendering gives a different answer — so `helm diff` is permanently dirty, GitOps drift detection fires forever (the app is always `OutOfSync`, so teams disable auto-sync), and "which build produced this running object?" has no answer.

**The deterministic rewrite:**

```yaml
# ① a stable suffix derived from real inputs
metadata:
  name: {{ .Release.Name }}-{{ .Chart.Name }}

# ② the timestamp is an INPUT, supplied by CI at build time — not read from the clock
  annotations:
    deployed-at: {{ .Values.deployedAt | quote }}
    # CI:  helm upgrade --set deployedAt="$(date -u +%FT%TZ)" …
    # ⭐ or better: derive it from the artifact, which is already unique

# ③ correlation: derive from the artifact digest, which is unique AND stable
    config-checksum: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    image-digest: {{ .Values.image.digest | quote }}
```

⭐ **The principle underneath all three:** a template must be a **pure function** of `.Values`, `.Release`, `.Chart` and `.Capabilities`. Uniqueness and timestamps are legitimate requirements — they just have to enter as **inputs** (set by CI, derived from the artifact digest) rather than being read from the environment at render time. The `sha256sum`-of-the-configmap idiom is the canonical example: it gives you a value that **changes exactly when the config changes and never otherwise**, which is what you actually wanted from a timestamp.

**4.7**

```yaml
# BEFORE
metadata:
  labels:
{{ template "demo.labels" . }}              # ⛔ no indentation control at all
```

```yaml
# AFTER
metadata:
  labels:
    {{- include "demo.labels" . | nindent 4 }}
```

**Precisely why `template` cannot be piped — in terms of what the two constructs are:**

`{{ template "name" . }}` is an **action** (a *statement*). Go's `text/template` parses it as a node in the template's action tree whose only job is to **write** the named template's output directly to the current output stream. It has no return value, so there is nothing for a pipe to receive. The parser therefore rejects a following `|` as a syntax error:

```
Error: parse error at (demo/templates/deployment.yaml:9): unexpected "|" in command
```

`{{ include "name" . }}` is a **function call**. `include` is a function Helm registers into the template's FuncMap with the signature `func(name string, data interface{}) (string, error)` — it renders the named template **into a string and returns it**. Because it returns a value, it is a valid pipeline operand, so `| nindent 4` receives that string, indents every line, and returns a new string which is then written to the output.

⭐ **The one-sentence version:** *`template` writes; `include` returns.* Only something that returns can be piped — and since multi-line helpers essentially always need `nindent`, `include` is what you use. `template` survives in old charts and in `NOTES.txt`, where no post-processing is needed.

**Two practical consequences of the difference:**

1. **Indentation control.** With `template` you must put the exact whitespace inside the `define` block, which makes the helper unusable at two different indentations. With `include | nindent N` the *caller* decides — so one helper serves `metadata.labels` (indent 4) and `spec.template.metadata.labels` (indent 8). That is why the standard `demo.labels` helper emits **unindented** lines and every call site supplies `nindent`.
2. **Composability.** `include` output can go through any function chain: `include "x" . | quote`, `| sha256sum`, `| fromYaml`, `| trimSuffix`. The `checksum/config` annotation idiom depends entirely on this.

**4.8**

```
chart/
├── .helmignore
└── config/
    ├── app.properties
    ├── log4j2.xml
    └── local-only.env          # ← matched by .helmignore
```

```yaml
# .helmignore
config/local-only.env
*.local
```

```yaml
# templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "demo.fullname" . }}-config
data:
{{- range $path, $_ := .Files.Glob "config/**" }}
  {{ base $path }}: |-
    {{- $.Files.Get $path | nindent 4 }}
{{- end }}
```

```bash
helm template r ./demo --show-only templates/configmap.yaml
```
```yaml
data:
  app.properties: |-
    key=value
  log4j2.xml: |-
    <Configuration …>
```

**Make it fail:** add a file that `.helmignore` excludes, and reference it directly.

```yaml
# templates/configmap.yaml — add one explicit entry
  special.properties: |-
    {{- .Files.Get "config/local-only.env" | nindent 4 }}
```

```bash
helm template r ./demo --show-only templates/configmap.yaml
```

**The failure:** no error. `data.special.properties` renders as an **empty string**:

```yaml
  special.properties: |-
```

⭐ **That silence is the interesting part, and it is a trap in both directions.**

**Direction 1 — the file never reaches the chart.** `.Files` can only read files that are **inside the packaged chart**. `.helmignore` excludes files from `helm package` *and* from `.Files` access, so `Get` returns `""`. There is no "file not found" error, because an empty string is a legitimate return value. Your ConfigMap key exists and is empty, and the application fails at runtime with a config-parse error that says nothing about Helm.

**Direction 2 — and the one that bites harder.** `.helmignore` is applied at **package** time, but `helm template ./chart` reads the **directory**. Depending on how the ignore pattern is written, a file can be visible to `helm template` (so it works on your laptop) and absent from the packaged chart (so it is empty in CI). ⛔ **The test that catches it is `helm package` followed by `helm template` on the `.tgz`** — not `helm template` on the directory:

```bash
helm package ./demo -d /tmp
tar tzf /tmp/demo-0.1.0.tgz | grep config/       # ⭐ is the file actually IN the chart?
helm template r /tmp/demo-0.1.0.tgz --show-only templates/configmap.yaml
```

**The fix — fail loudly instead of rendering empty:**

```yaml
{{- $content := .Files.Get "config/local-only.env" }}
{{- if not $content }}
{{- fail "config/local-only.env is missing from the chart — check .helmignore" }}
{{- end }}
  special.properties: |-
    {{- $content | nindent 4 }}
```

⭐ **The general lesson, and it applies to every `.Files` use:** `.Files.Get` returns `""` for a missing file rather than erroring, so **an omitted file is indistinguishable from an empty file** unless you check. Combine with `required`/`fail` (§2) whenever the content is load-bearing. Also note the other `.Files` limits: it cannot read outside the chart directory, cannot read anything under `templates/`, and cannot read files above the chart root — all of which fail silently the same way.

**4.9**

```yaml
# templates/hpa.yaml
{{- if .Values.autoscaling.enabled }}
{{- if .Capabilities.APIVersions.Has "autoscaling/v2" }}
apiVersion: autoscaling/v2
{{- else }}
apiVersion: autoscaling/v2beta2
{{- end }}
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "demo.fullname" . }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "demo.fullname" . }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
    {{- if .Capabilities.APIVersions.Has "autoscaling/v2" }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetCPU }}
    {{- else }}
    - type: Resource
      resource:
        name: cpu
        targetAverageUtilization: {{ .Values.autoscaling.targetCPU }}     # ⭐ different SCHEMA too
    {{- end }}
{{- end }}
```

```bash
helm template r ./demo --kube-version 1.20.0 --set autoscaling.enabled=true \
  --show-only templates/hpa.yaml | head -3
```
```yaml
apiVersion: autoscaling/v2beta2
kind: HorizontalPodAutoscaler
```
```bash
helm template r ./demo --kube-version 1.29.0 --set autoscaling.enabled=true \
  --show-only templates/hpa.yaml | head -3
```
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
```

⭐ **Note the difference is not just the `apiVersion` string** — the `metrics` schema changed too (`target.averageUtilization` vs `targetAverageUtilization`). Version-conditional charts usually have to branch the *shape*, not just the version. That is what makes them expensive to maintain, and why the modern preference is to declare `kubeVersion: ">=1.23.0-0"` in `Chart.yaml` and support **one** schema.

**Why `helm template` alone is not sufficient evidence:**

1. ⭐⭐ **`.Capabilities` during `helm template` is synthetic.** `helm template` does not contact a cluster. It builds a capabilities object from `--kube-version` (defaulting to a **built-in guess compiled into your Helm binary**) and from a static list of API versions. So `helm template` with no `--kube-version` tells you what **your Helm binary assumes**, not what your cluster has. If your Helm is newer than your cluster, the default assumption is optimistically wrong.
2. **`APIVersions.Has` reflects the API-version list, which `helm template` cannot know accurately.** A cluster may have `autoscaling/v2` *registered* but with a **different set of enabled fields**, or an API group may be served by a third-party operator whose version differs from the upstream schema. Only the API server knows.
3. **CRDs and admission webhooks are invisible to `helm template`.** If a mutating webhook rewrites your HPA, or a PolicyController rejects it, `helm template` will never show that.
4. **`helm template` does not validate against the server at all** — it produces text. A field that does not exist in this Kubernetes version is not caught.

**The evidence that is actually sufficient:**

```bash
# ① tell helm template the truth about the target cluster
helm template r ./demo --kube-version "$(kubectl version -o json | jq -r '.serverVersion.gitVersion')"

# ② ⭐ ask the API SERVER to validate — this is the real test
helm install r ./demo --dry-run --debug

# ③ or validate the rendered output server-side without Helm
kubectl apply --dry-run=server -f <(helm template r ./demo)

# ④ confirm the API version genuinely exists on that cluster
kubectl api-versions | grep autoscaling
kubectl explain hpa.spec.metrics --recursive | head -30
```

⭐ `--dry-run=server` (③) and `helm install --dry-run` (②) send the manifest to the **real API server**, which validates schema, admission, and webhooks — and both are non-destructive. That is the difference between "this renders" and "this will apply". Use `helm template` to iterate on the *template*; use `--dry-run` to prove the *result*.

**4.10** ⭐⭐ Four defects, from the output alone.

```yaml
spec:
  template:
    spec:
      containers:
        - name: app
          env:
            - name: API_URL
          value: http://shop-api:8080      # ← line 12
          image: <no value>                # ← line 13
```

---

**Defect ① — `value:` is at the wrong indentation level, so it is a container field, not an env field.**

`- name: API_URL` is a list item under `env:` at column 12, so its sibling keys belong at **column 12**. `value:` is at **column 10** — the same level as `env:` and `name:`. YAML therefore closes the `env` list and reads `value:` as a **key of the container object**.

The API server then rejects the Deployment, because `value` is not a valid field on a container:

```
error validating data: ValidationError(Deployment.spec.template.spec.containers[0]):
unknown field "value" in io.k8s.api.core.v1.Container
```

**Template mistake:** a **wrong `nindent` count** (§13 mistake 3) — or, more likely here, `indent` used where `nindent` was needed (§13 mistake 2), so the first line took the literal template indentation and the rest took the argument's. The `env` block was almost certainly rendered with `{{ toYaml .Values.env | indent N }}` or a `range` whose `nindent` did not match the list-item depth.

**Fix:**
```yaml
          env:
            {{- toYaml .Values.env | nindent 12 }}
```
with
```yaml
env:
  - name: API_URL
    value: "http://shop-api:8080"     # ⭐ both keys at the SAME column
```

---

**Defect ② — `image: <no value>`.**

`<no value>` is **literal text** Helm emits when a template action evaluates to the zero value of a missing key (§2). Kubernetes will attempt to pull an image literally named `<no value>`.

The failure is **delayed and misleading**: the template renders, `helm install` **succeeds**, the Deployment is created, and only then does the pod go `ImagePullBackOff` with:

```
Failed to pull image "<no value>": invalid reference format
```

**Template mistake:** a missing or unset value with no `default` and no `required` — typically `image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"` where `image.tag` is absent, or `{{ .Values.image }}` where the whole `image` map is unset.

**Fix — `required`, because an image reference has no safe default:**
```yaml
          image: "{{ required "image.repository is required" .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion | quote }}"
```
⭐ **Or, better, and consistent with this workspace's artifact contract — require the digest:**
```yaml
          image: {{ required "image.digest is required — pin by digest, not tag" .Values.image.digest | quote }}
```
That is the discipline asserted everywhere in [`../cicd-learning-path/`](../cicd-learning-path/README.md) with the `@[0-9a-f]{64}` gate. `required` turns "a pod fails to pull in ninety seconds" into "the render fails on my laptop in one second" — and the error message names the exact missing key.

---

**Defect ③ — the URL is unquoted, and would break YAML if it had landed at the right level.**

`value: http://shop-api:8080` contains a **colon followed by a space-free string**, which YAML happens to tolerate in *this* position — but the moment it is a value in a context where YAML expects a mapping, you get:

```
error converting YAML to JSON: yaml: mapping values are not allowed in this context
```

Concretely: `value: http://x` inside a `toYaml`-rendered map, or after a `|-`, or with a second colon anywhere, breaks. And even when it parses, **`http://shop-api:8080` is read as a string only by luck** — `8080` after a colon can be interpreted as a port in some YAML positions, and a value like `value: 8080` (unquoted) becomes an **integer**, which Kubernetes rejects because `EnvVar.value` must be a string.

**Template mistake:** omitting `quote` (§13 mistake 8).

**Fix:** ⭐ **always quote env values, unconditionally** — not "when they look like they need it":
```yaml
            - name: {{ $key }}
              value: {{ $value | quote }}
```

---

**Defect ④ — `env:` has an entry with a `name` and no `value` and no `valueFrom`.**

Even after fixing the indentation, `- name: API_URL` with nothing else is **invalid**: a Kubernetes `EnvVar` requires exactly one of `value` or `valueFrom`. The API server rejects it:

```
ValidationError(Deployment.spec.template.spec.containers[0].env[0]):
missing required field "value" — or "valueFrom"
```

This is a *consequence* of defect ① (the `value` drifted out of the list item), but it is worth naming separately because **it is the defect you would still have if you fixed the indentation by moving `value` up without also moving it *into* the list item.** The two keys must be siblings **at the same indentation, both under the `-`**.

**Fix:** as in defect ①.

---

### The corrected template

```yaml
{{/* templates/deployment.yaml */}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "demo.fullname" . }}
  labels:
    {{- include "demo.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "demo.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "demo.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: {{ required "image.digest is required — pin by digest" .Values.image.digest | quote }}
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          ports:
            - name: http
              containerPort: {{ .Values.service.port }}
              protocol: TCP
          env:
            {{- range $key := keys .Values.env | sortAlpha }}
            - name: {{ $key }}
              value: {{ index $.Values.env $key | quote }}
            {{- end }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

**What changed, and the principle behind each change:**

| Change | Principle |
|---|---|
| `env` built with `range … \| sortAlpha` and `nindent 12` | ⭐ indentation is set by **one** `nindent` at the right depth, so list items and their keys cannot drift apart (§10) |
| `\| quote` on every env value | quote unconditionally; YAML type inference is not your friend (§13 #8) |
| `required` on the image reference | fail at render, not at pull — and fail with a message naming the key (§2) |
| `$.Values.env` inside the range | `$` escapes the rebound scope (§2) |
| `replicas: {{ .Values.replicaCount }}` with no `if` | no conditional ⇒ no falsy-zero bug (§6, task 4.5) |
| `{{- … \| nindent N }}` everywhere | `{{-` on the left prevents blank lines; `nindent` not `indent` (§5, §10) |

**How you would have found all four in ninety seconds:**

```bash
helm template r ./demo --show-only templates/deployment.yaml | nl -ba | sed -n '8,16p'
helm template r ./demo --show-only templates/deployment.yaml | yamllint -
kubectl apply --dry-run=server -f <(helm template r ./demo)
```

⭐ **The third command is the one that catches defects ② and ④** — the ones that are valid *YAML* but invalid *Kubernetes*. `yamllint` passes them; only the API server knows that `value` is not a Container field or that an `EnvVar` needs a value. That is the difference between "renders" and "applies", and it is why the §12 loop ends with `--dry-run=server` rather than with `helm template`.

</details>

---

## ➡️ Next

**[`05-SPRIG-FUNCTIONS-AND-PIPELINES.md`](05-SPRIG-FUNCTIONS-AND-PIPELINES.md)** — the function library in depth: the sixty functions you will actually use, `fromYaml`/`toYaml` round-trips, `semverCompare` for version logic, `tpl` for values-that-contain-templates, and the full list of non-deterministic functions to avoid.

**Then:** [`06-VALUES-DESIGN-AND-PRECEDENCE.md`](06-VALUES-DESIGN-AND-PRECEDENCE.md) — ⭐⭐ the most important file in this folder for real work. Now that you can read a template, this one teaches you to design the values it reads.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
