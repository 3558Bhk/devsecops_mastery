# 🟢 Trivy 00 · Install and Fundamentals
### Install Trivy **and verify its signature**, understand the artifact/target model, know which databases it downloads and why, and get an air-gapped install working — before you ever run a scan in CI.

> **WHAT this file is:** the foundation. Everything in files `01`–`08` assumes you can install Trivy reproducibly, explain what it downloaded, and name the five things it can scan.
>
> **WHY the install comes with a signature check:** because on **19–20 March 2026** an attacker shipped a **malicious Trivy binary as `v0.69.4`** and force-pushed **76 of 77 tags** in `aquasecurity/trivy-action`. Your security scanner is the most privileged tool in your pipeline — it reads every image and every file. Installing it without verification is how the compromise succeeded. Full case study in [`../02-SUPPLY-CHAIN-AND-PINNING.md`](../02-SUPPLY-CHAIN-AND-PINNING.md).
>
> **TARGET:** Trivy installed, pinned, signature-verified, and you can explain the artifact/target/scanner model without notes.
>
> **Time:** 3 hours.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1--version-anchors-and--the-pinning-rule) | Version anchors and ⭐ the pinning rule |
| [2](#2---the-mental-model-artifact--target--scanner) | ⭐⭐ The mental model: **artifact → target → scanner** |
| [3](#3--install-and-verify-on-linux) | Install and **verify** on Linux |
| [4](#4--install-on-macos-windows-and-in-docker) | Install on macOS, Windows, and in Docker |
| [5](#5--the-three-databases-trivy-downloads--where-when-and-how-to-freeze-them) | The three databases Trivy downloads — where, when, and how to freeze them |
| [6](#6--air-gapped-and-offline-installs) | Air-gapped and offline installs |
| [7](#7--your-first-five-scans-and-what-each-proves) | Your first five scans (and what each proves) |
| [8](#8---exit-codes--the-gate-flag-nobody-sets) | ⭐ Exit codes — the gate flag nobody sets |
| [9](#9---tasks) | 🔨 Tasks — **answers at the END** |

---

## 1 · Version anchors and ⭐ the pinning rule

| Component | Version | Verified |
|---|---|---|
| **Trivy** | **v0.74.0** | 2026-08-14 |
| **trivy-operator** | **v0.32.0** | 2026-07-08 |
| **`aquasecurity/trivy-action`** | **v0.35.0** | ⛔ the only uncompromised tag from March 2026 |
| **`aquasecurity/setup-trivy`** | **v0.2.6** | |
| **`trivy-db`** | schema **v3** | updated ~every 6 h from `ghcr.io/aquasecurity/trivy-db` |
| **`trivy-java-db`** | v1 | JARs with no manifest |
| **`trivy-checks`** | separate bundle | Rego policies for misconfig scanning |
| **cosign** | **v3.0.2** | for verification |

### ⭐ The pinning rule — three levels, pick the highest you can afford

| Level | Example | Survives a force-push? | Use when |
|---|---|---|---|
| ⛔ **Mutable tag** | `aquasec/trivy:latest` | **No** | never, in CI |
| ⚠️ **Version tag** | `aquasec/trivy:0.74.0` | **No** — tags can be re-pointed | local dev only |
| ✅ **Digest / commit SHA** | `aquasec/trivy@sha256:…` · `aquasecurity/trivy-action@<sha>` | **Yes** | ⭐ **everything in CI** |

> ⭐⭐ **This is the entire lesson of the March 2026 incident in one table.** The attacker did not invent a new vulnerability — they **moved tags**. 76 of 77 tags in `trivy-action` were force-pushed to malicious commits. Every pipeline pinned to `@v0.34.0` started running attacker code without a single configuration change, and without any new release appearing in a changelog.
>
> `v0.35.0` survived **only** because it was published as a GitHub **immutable release**. That is not a Trivy property — it is a GitHub repository setting. ⭐ Which means your protection came from a checkbox in someone else's repo settings. Do not rely on that. Pin digests.

Getting the digest to pin:

```bash
# for the image
docker buildx imagetools inspect aquasec/trivy:0.74.0 --format '{{json .Manifest}}' | jq -r '.digest'
# or, from the registry directly
crane digest aquasec/trivy:0.74.0        # if you have crane

# for a GitHub Action → the commit SHA behind the tag
git ls-remote https://github.com/aquasecurity/trivy-action refs/tags/v0.35.0
# <sha>  refs/tags/v0.35.0     ← pin THAT sha
```

---

## 2 · ⭐⭐ The mental model: **artifact → target → scanner**

Trivy's command line looks inconsistent until you understand that it has **three independent axes**. Every flag you will ever use belongs to one of them.

```
      ┌─────────────────────────────────────────────────────────────┐
      │  AXIS 1 · ARTIFACT   —  what kind of thing are you pointing at? │
      │                                                             │
      │  trivy image     <registry/repo:tag | repo@sha256:…>         │
      │  trivy fs        <path>          ← lockfiles, IaC, secrets   │
      │  trivy rootfs    <path>          ← an unpacked OS filesystem │
      │  trivy repo      <git-url>       ← clones, then behaves like fs│
      │  trivy sbom      <sbom.json>     ← ⭐ scan a bill of materials│
      │  trivy k8s       [cluster|all]   ← the whole live cluster    │
      │  trivy vm        <ami/disk img>  ← a virtual machine image   │
      │  trivy aws       / trivy azure   ← cloud account misconfig   │
      └─────────────────────────────────────────────────────────────┘
                                ↓
      ┌─────────────────────────────────────────────────────────────┐
      │  AXIS 2 · SCANNER    —  what are you looking for?            │
      │                                                             │
      │  --scanners vuln          ← CVEs (the default)               │
      │  --scanners misconfig     ← IaC problems (Rego policies)     │
      │  --scanners secret        ← hardcoded credentials            │
      │  --scanners license       ← licence obligations              │
      │                                                             │
      │  ⭐ They compose:  --scanners vuln,secret,misconfig          │
      └─────────────────────────────────────────────────────────────┘
                                ↓
      ┌─────────────────────────────────────────────────────────────┐
      │  AXIS 3 · DETECTION  —  within vuln, which package worlds?   │
      │                                                             │
      │  --pkg-types os           ← apk/dpkg/rpm  (distro advisories)│
      │  --pkg-types library      ← npm/pip/maven/go/cargo/nuget…    │
      │                                (GHSA + language advisories)  │
      │  ⭐ both by default. Different fix cadences, different noise │
      └─────────────────────────────────────────────────────────────┘
```

### ⭐ Why the OS / library split is the thing you must internalise first

`trivy image node:24` reports findings from **two completely different worlds**:

| | 🐧 **OS packages** | 📦 **Language packages** |
|---|---|---|
| Examples | `libc`, `openssl`, `curl`, `zlib`, `apk-tools` | `express`, `lodash`, `requests`, `spring-core`, `net/http` deps |
| Source of truth | **the distro's own advisory DB** (Alpine secdb, Debian security tracker, Red Hat OVAL, Ubuntu USN) | **GHSA**, NVD, plus language-specific DBs |
| Severity meaning | ⭐ the **distro's** severity, which is often *lower* than NVD because the distro back-ported a fix | the upstream project's / NVD's |
| Fixed version | usually exists quickly (distro ships a patched build) | depends on the maintainer; may **never** be fixed |
| How you fix it | rebuild on a newer base image, or `apk upgrade` | bump the dependency in your lockfile |
| How you ignore it | ⛔ **do not ignore distro advisories casually** — these are real, patched, and cheap to fix | ⭐ most of your legitimate suppressions live here |

> ⭐⭐ **The consequence that changes how you read every Trivy report:** a `CRITICAL` from NVD on an OS package often shows up as `LOW` or as *"no fixed version available"* from the distro, because the distro back-ported the patch and the CVE list is comparing upstream version numbers. Trivy reports **both** and marks fixability. **This is why `--ignore-unfixed` is the single highest-value flag in Trivy** — it removes the entire class of finding you cannot act on.
>
> Conversely, a `MEDIUM` in a language package that you actually call at runtime, on an exposed endpoint, is more urgent than a `CRITICAL` in a build tool that your multi-stage build already discarded. **Severity is a property of the CVE. Risk is a property of your deployment.** File [`01`](01-FIRST-SCAN-AND-READING-OUTPUT.md) is entirely about closing that gap.

### The target — what Trivy actually inspects inside an image

```
an OCI image
  ├─ image config      → OS family + version, architecture, entrypoint, env, layers
  ├─ layer 1..N        → ⭐ Trivy reads every layer's filesystem
  │     ├─ /etc/os-release, /lib/apk/db/installed, /var/lib/dpkg/status, rpm db
  │     │      → OS packages
  │     ├─ package.json, package-lock.json, node_modules/**
  │     ├─ requirements.txt, poetry.lock, Pipfile.lock, uv.lock
  │     ├─ pom.xml, build.gradle, *.jar  (⭐ JARs with no manifest → trivy-java-db)
  │     ├─ go.mod, go.sum
  │     ├─ Cargo.lock, composer.lock, packages.lock.json, *.csproj
  │     └─ any file → secret scanner runs over all of them
  └─ history           → ⭐ where `--list-all-pkgs` and layer attribution come from
```

⭐ **Two consequences worth knowing before your first scan:**

1. **Multi-stage builds remove findings, not just bytes.** Packages installed only in a discarded build stage are still in the image *history* but **not in the final filesystem** Trivy walks — so they do not appear in the report. That is why the `shop-api` Java image in [`../../docker-learning-path/`](../../docker-learning-path/README.md) goes from ~800 CVEs to ~40 when it moves from a single-stage JDK build to `eclipse-temurin:21-jre-alpine` + a copied JAR.
2. **JARs without a manifest need `trivy-java-db`.** A shaded/fat JAR has no `pom.xml` next to it. Trivy computes the JAR's SHA-1 and looks it up in a **separate, large** database. First Java scan downloads ~1 GB extra. In CI, cache it or the build takes four minutes.

---

## 3 · Install and **verify** on Linux

### 3.1 The pinned-version install script — then verify

```bash
TRIVY_VERSION=v0.74.0
ARCH=Linux-64bit                       # Linux-ARM64 | Linux-32bit | macOS-64bit | macOS-ARM64

mkdir -p /tmp/trivy-install && cd /tmp/trivy-install

# ⭐ Download the artifact AND its signature AND its checksum
curl -sSfLO "https://github.com/aquasecurity/trivy/releases/download/${TRIVY_VERSION}/trivy_${TRIVY_VERSION#v}_${ARCH}.tar.gz"
curl -sSfLO "https://github.com/aquasecurity/trivy/releases/download/${TRIVY_VERSION}/trivy_${TRIVY_VERSION#v}_${ARCH}.tar.gz.sig"
curl -sSfLO "https://github.com/aquasecurity/trivy/releases/download/${TRIVY_VERSION}/trivy_${TRIVY_VERSION#v}_checksums.txt"
```

**Step 1 — checksum (cheap, catches corruption and most tampering):**

```bash
grep "trivy_${TRIVY_VERSION#v}_${ARCH}.tar.gz" trivy_${TRIVY_VERSION#v}_checksums.txt | sha256sum -c -
# trivy_0.74.0_Linux-64bit.tar.gz: OK
```

**Step 2 — ⭐ signature (the step that actually matters):**

```bash
# Trivy releases are signed with cosign. Verify with the public key published
# alongside the release, OR keyless via the Fulcio certificate chain.
#
# ⭐ LIST THE ASSETS FIRST — signing scheme and filenames change between releases,
#    and guessing them produces a verification that silently passes on nothing.
curl -sSfL "https://api.github.com/repos/aquasecurity/trivy/releases/tags/${TRIVY_VERSION}" \
  | jq -r '.assets[].name' | grep -Ei 'sig|cert|cdsig|pem|pub'
```

Then verify using whichever scheme the release actually publishes:

```bash
# (a) key / signature pair
cosign verify-blob trivy_${TRIVY_VERSION#v}_${ARCH}.tar.gz \
  --signature trivy_${TRIVY_VERSION#v}_${ARCH}.tar.gz.sig \
  --key <published-public-key>

# (b) keyless (Fulcio + Rekor) — certificate identity must match the Trivy release workflow
cosign verify-blob trivy_${TRIVY_VERSION#v}_${ARCH}.tar.gz \
  --bundle   trivy_${TRIVY_VERSION#v}_${ARCH}.tar.gz.cdsig \
  --certificate-identity-regexp 'https://github\.com/aquasecurity/trivy/\.github/workflows/.+' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
```

> ⭐⭐ **Why step (b)'s `--certificate-identity-regexp` is the load-bearing flag.** Keyless signing proves *"a GitHub Actions workflow in **this** repository signed this blob."* Without the identity and issuer constraints, **any** keyless signature from **any** GitHub repo verifies — including one the attacker produced from their own fork. The March 2026 attack worked because the *release automation itself* was compromised: the signature was valid, the binary was not. **Signature verification proves provenance, not safety.** It tells you Aqua published it. The digest pin tells you *which* Aqua artifact you accepted. You need both.

**Step 3 — install:**

```bash
tar xzf trivy_${TRIVY_VERSION#v}_${ARCH}.tar.gz
sudo install -m 0755 trivy /usr/local/bin/trivy
trivy --version
```

```
Version: 0.74.0
Vulnerability DB:
  Version: 3
  UpdatedAt: 2026-09-17 …
Java DB:
  Version: 1
  …
```

⭐ **`trivy --version` prints the DB state too.** Read it. A stale DB is the most common cause of "Trivy found nothing" and it is invisible unless you look here.

### 3.2 Package managers — convenient, but check what they pin

```bash
# Debian / Ubuntu — apt repo signed with a GPG key
sudo mkdir -p /etc/apt/keyrings
wget -qO- https://aquasecurity.github.io/trivy-repo/deb/public.key \
  | gpg --dearmor | sudo tee /etc/apt/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" \
  | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update && sudo apt-get install -y trivy

# ⭐ Then pin it so an apt upgrade cannot move you:
sudo apt-mark hold trivy
dpkg -l trivy | tail -1

# RHEL / CentOS / Rocky / Alma
sudo rpm -ivh https://aquasecurity.github.io/trivy-repo/rpm/releases/trivy-repo-2.noarch.rpm
sudo dnf install -y trivy
sudo dnf versionlock add trivy
```

> ⚠️ **Package-manager installs give you convenience and take away the digest pin.** `apt-get install trivy` resolves to whatever the repo publishes today. That is acceptable on a laptop; in CI it is exactly the mutable-tag failure mode from §1. ⭐ In CI, use the pinned binary or the digest-pinned image, not `apt-get`.

### 3.3 Verify your install, three ways

```bash
trivy --version                                   # version + DB freshness
which trivy && file "$(which trivy)"              # ELF, correct arch — ⭐ the exact
                                                  #   check that catches a macOS-built
                                                  #   node_modules binary in an image
sha256sum "$(which trivy)"                        # record it; compare on every runner
```

---

## 4 · Install on macOS, Windows, and in Docker

### macOS

```bash
brew install trivy
brew pin trivy                # ⭐ stop brew upgrade from moving you
trivy --version
```

### Windows

```powershell
# Chocolatey
choco install trivy --version=0.74.0

# Scoop
scoop install trivy

# Or the MSI/ZIP from the pinned GitHub release, then verify the checksum.
Get-FileHash .\trivy_0.74.0_Windows-64bit.zip -Algorithm SHA256
```

⚠️ **On Windows, `trivy image` needs a container runtime reachable.** Trivy talks to the Docker/Podman/containerd socket (or pulls from a registry directly). If you get `unable to inspect the image`, you are scanning a local image and no runtime is available — use `--image-src remote` to pull from the registry instead, or run Trivy inside WSL2.

### ⭐ Docker — the form CI should use

```bash
# Run against a local image (needs the Docker socket — ⛔ read the warning below)
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$HOME/.cache/trivy:/root/.cache/trivy" \
  aquasec/trivy@sha256:<PINNED_DIGEST> image shop-api:1.4.2

# ⭐ Better: scan a remote registry image — no socket needed at all
docker run --rm \
  -v "$HOME/.cache/trivy:/root/.cache/trivy" \
  aquasec/trivy@sha256:<PINNED_DIGEST> image \
  ghcr.io/3558bhk/shop-api@sha256:<IMAGE_DIGEST>
```

> ⛔⛔ **Mounting `/var/run/docker.sock` into a scanner container is a real privilege escalation.** Anything with that socket has root on the host — it can launch a container mounting `/` and escape. You are handing host root to the tool you installed *because you were worried about supply-chain attacks*.
>
> **The three safer options, in order:**
> 1. **`--image-src remote`** and give Trivy registry credentials only. No socket. ⭐ Preferred in CI.
> 2. Scan the **image tarball**: `docker save shop-api:1.4.2 -o img.tar && trivy image --input img.tar`. No socket, works offline.
> 3. Use **trivy-operator** in-cluster (file [`04`](04-KUBERNETES-AND-INFRA.md)) — it reads images via the registry, not via a node socket.
>
> The same reasoning is why [`../../docker-learning-path/`](../../docker-learning-path/README.md) and [`../../cicd-learning-path/09-TOOL-MASTERY/jenkins/`](../../cicd-learning-path/09-TOOL-MASTERY/jenkins/README.md) build with **Kaniko, never a mounted `docker.sock`**.

### The cache volume — why you must mount it

```
/root/.cache/trivy
  ├── db/trivy.db          ← ~600 MB, downloaded every 12 h otherwise
  ├── db/metadata.json     ← ⭐ DB age lives here; Trivy refuses if too old
  ├── java-db/             ← ~1 GB, only if you scan JARs
  └── fanal/               ← layer analysis cache — keyed by layer digest
```

⭐ **The `fanal/` layer cache is the difference between a 90-second scan and a 15-second one.** Image layers are content-addressed, so a layer you scanned yesterday is reused today. In CI, cache `~/.cache/trivy` as an artifact keyed on nothing (it self-invalidates by digest) and your scans drop to seconds. File [`03`](03-CI-CD-INTEGRATION.md) does this for all three CI tools.

---

## 5 · The three databases Trivy downloads — where, when, and how to freeze them

| DB | Contains | Size | Updated | Pulled from |
|---|---|---|---|---|
| **`trivy-db`** | OS advisories (Alpine secdb, Debian, Ubuntu USN, Red Hat OVAL, Amazon ALAS, SUSE…), language advisories (GHSA, NVD, Ruby/PHP/Python/Node/Go/Java/Rust/.NET), plus the `--ignore-unfixed` fixability data | ~600 MB | **every 6 h** upstream; **every 12 h** on your machine by default | `ghcr.io/aquasecurity/trivy-db` |
| **`trivy-java-db`** | SHA-1 → Maven coordinates for JARs with no manifest | ~1 GB | weekly | `ghcr.io/aquasecurity/trivy-java-db` |
| **`trivy-checks`** | The **Rego** misconfiguration policies | ~10 MB | with releases | `ghcr.io/aquasecurity/trivy-checks` |

### Why this matters more than it sounds

**1. Trivy refuses to run against a stale DB — and CI fails in a confusing way.**

```
2026-09-17T… FATAL DB error: the database is older than the allowed age (22h0m0s)
```

That happens when the runner cannot reach `ghcr.io` (no egress, proxy, DNS) and the cached DB is too old. ⭐ **The error mentions neither network nor registry**, so people debug their image instead of their egress.

```bash
trivy image --download-db-only          # force a DB refresh; shows the real network error
trivy image --skip-db-update <img>      # use the cached DB regardless of age
```

**2. Your scan results change every 6 hours without you changing anything.**

A build that passed on Monday can fail on Tuesday because a new CVE was published. ⭐ **This is correct behaviour, not a bug** — but it means "the same commit, the same image digest, different verdicts" is expected, and your team needs to have agreed in advance what happens when it occurs. File [`02`](02-CONFIGURATION-AND-BASELINES.md) covers the two legitimate responses: gate on **new code/new layers** only, or accept that a digest can retroactively become non-compliant.

**3. For reproducibility you may want to *freeze* the DB.**

```bash
# Mirror the DB to your own registry once, pin it, and point Trivy at it
oras pull ghcr.io/aquasecurity/trivy-db:3
oras push registry.internal/security/trivy-db:2026-09-17 ./db

trivy image --db-repository registry.internal/security/trivy-db:2026-09-17 <img>
```

⭐ Now two builds three months apart produce **identical** vulnerability findings, which is what an auditor actually wants when they ask "prove this image was scanned". The trade-off: you are now deliberately not knowing about new CVEs. **Freeze the DB for evidence and reproducibility; keep a separate, unfrozen nightly scan for actual risk.**

### Reading DB state

```bash
trivy --version                                    # DB version + UpdatedAt for both DBs
cat ~/.cache/trivy/db/metadata.json | jq
```

```json
{
  "Version": 3,
  "NextUpdate": "2026-09-17T18:00:00Z",
  "UpdatedAt": "2026-09-17T06:00:00Z",
  "DownloadedAt": "2026-09-17T06:04:12Z"
}
```

⭐ If `NextUpdate` is in the past and `DownloadedAt` is not recent, your runners cannot reach `ghcr.io`. That is a networking problem wearing a scanner costume.

---

## 6 · Air-gapped and offline installs

The pattern is: **prepare online, transfer, run offline.**

```bash
# ── ON A CONNECTED MACHINE ────────────────────────────────────────────────
mkdir -p bundle && cd bundle

trivy image --download-db-only --cache-dir ./cache
trivy image --download-java-db-only --cache-dir ./cache     # only if you scan JARs

# get the binary (verified per §3.1) and the Rego checks bundle
cp /usr/local/bin/trivy .

# ⭐ export the DB as an OCI artifact so it survives the transfer intact
oras pull ghcr.io/aquasecurity/trivy-db:3 --output ./db-oci

tar czf trivy-offline-$(date +%F).tar.gz ./cache ./trivy ./db-oci
sha256sum trivy-offline-*.tar.gz > trivy-offline.sha256

# ── TRANSFER, then ON THE AIR-GAPPED MACHINE ──────────────────────────────
tar xzf trivy-offline-*.tar.gz
sudo install -m 0755 ./trivy /usr/local/bin/trivy
export TRIVY_CACHE_DIR=/opt/trivy/cache       # ⭐ persist it, don't leave it in $HOME

# ⭐ Tell Trivy there is no network, or it will try and time out
trivy image --skip-db-update --skip-java-db-update --offline-scan <image-or-tarball>
```

| Flag | What it does |
|---|---|
| `--skip-db-update` | do not check for or download a new `trivy-db` |
| `--skip-java-db-update` | same for `trivy-java-db` |
| `--offline-scan` | ⭐ **no network calls at all during the scan** — also skips the API calls Trivy would otherwise make for some registry/analytics paths |
| `--cache-dir` | where the DB and layer cache live; set this explicitly on shared runners |
| `--db-repository` | point at your internal mirror |
| `--input img.tar` | scan a tarball instead of pulling — ⭐ no registry access needed either |

⭐ **The air-gapped trap:** `--skip-db-update` plus a DB older than the allowed age still **fails**. You need `--offline-scan` (or a fresh-enough mirrored DB) as well. People set one flag, get the FATAL age error, and conclude Trivy cannot work offline. It can — you just need both.

---

## 7 · Your first five scans (and what each proves)

Run these against the images you already have from [`../../docker-learning-path/`](../../docker-learning-path/README.md). Each one demonstrates a different capability.

```bash
cd ~/shop    # your workspace repo

# ── ① A base image you did not build ─────────────────────────────────────
trivy image --severity CRITICAL,HIGH node:24-alpine
trivy image --severity CRITICAL,HIGH node:24
```

⭐ **Run both.** `node:24-alpine` (musl, ~50 packages) versus `node:24` (Debian, ~350 packages) is the clearest possible demonstration that **base-image choice is a security control, not a size optimisation**. You will typically see an order-of-magnitude difference in OS-package findings.

```bash
# ── ② An image YOU built, with the OS/library split visible ──────────────
trivy image --scanners vuln ghcr.io/3558bhk/shop-api:latest
#   → two tables: "OS Packages" then "Java"

# prove the multi-stage build removed the build toolchain
trivy image --list-all-pkgs ghcr.io/3558bhk/shop-api:latest | grep -icE 'maven|javac|jdk'
#   → 0   ⭐ the JDK is not in the final image, so neither are its CVEs
```

```bash
# ── ③ Misconfiguration — Trivy's IaC scanner ─────────────────────────────
trivy config k8s/
trivy config --severity HIGH,CRITICAL helm-charts/shop-api/
trivy config --format json --output trivy-iac.json k8s/
```

```bash
# ── ④ Secrets — scan the repo, not just the image ────────────────────────
trivy fs --scanners secret .
trivy repo --scanners secret --skip-dirs node_modules,vendor,.git https://github.com/you/shop
```

⭐ **This is the scan that finds the thing that actually gets you breached.** A leaked AWS key in a committed `docker-compose.yml` will not show up in any CVE scan, ever.

```bash
# ── ⑤ Generate an SBOM, then scan the SBOM ───────────────────────────────
trivy image --format cyclonedx --output sbom-shop-api.cdx.json ghcr.io/3558bhk/shop-api:latest
trivy sbom sbom-shop-api.cdx.json
```

> ⭐⭐ **Scan ⑤ is the one that surprises people.** `trivy sbom` finds vulnerabilities **from a bill of materials alone** — no image, no registry access, no build. Two consequences:
> - During a log4j-class event you can answer *"are we affected, anywhere?"* by scanning a folder of SBOMs in seconds, instead of rebuilding and rescanning every image.
> - You can scan a **third-party dependency you never built** if someone gives you its SBOM.
>
> This is why SBOM generation belongs in CI *even if nobody reads it today*. File [`../03-COMPLIANCE-REPORTING-AND-AUDIT.md`](../03-COMPLIANCE-REPORTING-AND-AUDIT.md) covers the attestation side.

---

## 8 · ⭐ Exit codes — the gate flag nobody sets

⛔ **Trivy exits `0` even when it finds 400 CRITICAL vulnerabilities.** This is not a bug — Trivy is a *reporter* by default, not a *gate*. Turning it into a gate is one flag, and forgetting it is the most common reason a Trivy install does nothing.

```bash
trivy image --severity CRITICAL node:24
echo $?
# 0        ← ⛔ 400 CRITICALs and a successful exit
```

```bash
trivy image --severity CRITICAL --exit-code 1 node:24
echo $?
# 1        ← ✅ now it fails
```

### The gate combination you actually want

```bash
trivy image \
  --scanners vuln,secret \
  --severity CRITICAL,HIGH \
  --ignore-unfixed \
  --exit-code 1 \
  --no-progress \
  --format sarif \
  --output trivy-results.sarif \
  --timeout 10m \
  --cache-dir .trivycache \
  ghcr.io/3558bhk/shop-api@sha256:<digest>
```

| Flag | Why |
|---|---|
| `--exit-code 1` | ⭐ **the gate.** Without it, nothing you do here matters |
| `--severity CRITICAL,HIGH` | fail on what is serious; still *report* MEDIUM/LOW if you also emit a non-gating report |
| `--ignore-unfixed` | ⭐⭐ **remove findings you cannot act on.** A CRITICAL with no patched version available is not something a developer can fix in this PR. Gate on fixable, track unfixable separately |
| `--no-progress` | clean CI logs (the progress bar renders as thousands of junk lines) |
| `--format sarif --output …` | ⭐ gets findings into GitHub code scanning / Azure DevOps as PR comments, in front of the person who wrote the code — instead of dying in a build log |
| `--timeout 10m` | default is 5 m; a large image on a cold cache exceeds it |
| `--cache-dir` | persist between runs (§4) |
| `@sha256:<digest>` | ⭐ **scan the digest, not the tag.** The artifact your pipeline published is identified by digest — the same contract used everywhere in [`../../cicd-learning-path/`](../../cicd-learning-path/README.md) |

### ⭐ The two-report pattern

One report gates, one informs. Same scan, two outputs:

```bash
# GATE — fixable CRITICAL/HIGH only. Fails the build.
trivy image --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 \
  --format sarif --output gate.sarif "$IMAGE_DIGEST"

# INFORM — everything, including unfixable. Never fails. Becomes a trend line.
trivy image --severity CRITICAL,HIGH,MEDIUM,LOW \
  --format json --output full-report.json "$IMAGE_DIGEST" || true
```

⭐ **Why both.** A gate that includes unfixable findings gets disabled within a month, and then you have no gate at all. A report with no gate gets ignored, and then you have no visibility. Running both gives you an enforcing gate that developers can actually satisfy, plus the full picture for risk reporting. This is the same ratchet as SonarQube's "Clean as You Code" ([`../sonarqube/02-CONFIGURATION-AND-BASELINES.md`](../sonarqube/02-CONFIGURATION-AND-BASELINES.md)) and Checkov's baselines ([`../checkov/02-CONFIGURATION-AND-BASELINES.md`](../checkov/02-CONFIGURATION-AND-BASELINES.md)) — **the single most important pattern in this entire folder.**

---

## 9 · 🔨 Tasks

> **0.1** Install Trivy v0.74.0 on your machine using the **verified** method from §3.1 — checksum *and* signature. Record the `sha256sum` of your installed binary. Then explain, in one sentence each, what the checksum proves and what the signature proves, and why neither proves the binary is safe.

> **0.2** Produce the pinned references you would use in CI for: the Trivy Docker image, and `aquasecurity/trivy-action@v0.35.0`. Show the commands that give you the digest and the commit SHA, and explain why `@v0.35.0` alone is insufficient.

> **0.3** Scan `node:24` and `node:24-alpine` with identical flags. Report the OS-package finding counts for each, and explain *mechanically* why they differ — name the thing in the image that Trivy reads to produce each number.

> **0.4** Prove that Trivy exits `0` on a failing scan, then build the gate command from §8 and prove it now exits `1`. Finally, produce a scan that finds CRITICALs but still exits `0` — *legitimately* — and explain when you would want that.

> **0.5** Generate a CycloneDX SBOM for one of your images and scan **the SBOM**. Confirm the finding count is close to the image scan. Then find one finding that appears in the image scan but not the SBOM scan, and explain why.

> **0.6** Make Trivy fail with the *"database is older than the allowed age"* error on purpose. Then fix it three different ways and explain which one is appropriate for CI, which for air-gapped, and which for never.

> **0.7** Set up a local Trivy cache and measure the wall-clock difference between a cold scan and a warm scan of the same image. Report both numbers and explain what, exactly, was reused.

> **0.8** ⭐⭐ Your team has Trivy in CI with `--exit-code 1` and `--severity CRITICAL,HIGH`. After two weeks, three developers have added the same four CVEs to `.trivyignore` in three separate PRs, and one of them ignored a `CRITICAL` in `openssl`. Diagnose what is wrong with the *configuration*, not the developers, and specify the exact flag set you would replace it with.

> **0.9** ⭐⭐ Design the Trivy layer of a scanning programme for a 40-repo organisation with no security team: which artifact(s) get scanned, at which pipeline stage, with which flags, what gates, what is reported, who owns a suppression, and what happens to a digest that becomes non-compliant three months after it shipped. Keep it under one page.

<details>
<summary>👉 Answers</summary>

**0.1** The install, fully:

```bash
TRIVY_VERSION=v0.74.0; ARCH=Linux-64bit; cd /tmp && mkdir trivy-install && cd trivy-install
for ext in tar.gz tar.gz.sig; do
  curl -sSfLO "https://github.com/aquasecurity/trivy/releases/download/${TRIVY_VERSION}/trivy_${TRIVY_VERSION#v}_${ARCH}.${ext}"
done
curl -sSfLO "https://github.com/aquasecurity/trivy/releases/download/${TRIVY_VERSION}/trivy_${TRIVY_VERSION#v}_checksums.txt"

sha256sum -c <(grep "trivy_${TRIVY_VERSION#v}_${ARCH}.tar.gz\$" trivy_${TRIVY_VERSION#v}_checksums.txt)
cosign verify-blob trivy_${TRIVY_VERSION#v}_${ARCH}.tar.gz \
  --bundle trivy_${TRIVY_VERSION#v}_${ARCH}.tar.gz.cdsig \
  --certificate-identity-regexp 'https://github\.com/aquasecurity/trivy/\.github/workflows/.+' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
tar xzf *.tar.gz && sudo install -m 0755 trivy /usr/local/bin/trivy
sha256sum "$(which trivy)"     # ← record this
```

**What each proves — and the limits:**

| Mechanism | Proves | Does **not** prove |
|---|---|---|
| **SHA-256 checksum** | the file you have is byte-identical to the file the checksum was computed over — so it was **not corrupted or altered in transit** | ⛔ nothing about *who* produced it. The checksum file is published **in the same place, by the same account** as the binary. An attacker who controls the release controls both, and simply publishes a matching checksum. This is transport integrity, not authenticity |
| **cosign signature** | the artifact was signed by a key/certificate you can attribute — e.g. *"the GitHub Actions release workflow in `aquasecurity/trivy`, authenticated by GitHub's OIDC issuer, signed this blob."* That is **authenticity + provenance** | ⛔ **that the artifact is safe.** In March 2026 the *release automation itself* was compromised: the `aqua-bot` service account triggered the pipeline that published `v0.69.4`, so the malicious binary carried a **valid signature from the legitimate workflow**. Verification succeeded; the binary was still malware |

⭐ **The one-sentence version:** the checksum proves it did not change on the way to you; the signature proves which pipeline claims to have produced it; **neither proves the pipeline was not already compromised.** The defences against *that* are different and complementary — pinning a **digest** so a tag move cannot reach you (mutable-tag attacks fail), watching for **anomalous releases and tag force-pushes** (GitHub's push-protection and immutable releases; the reason `v0.35.0` survived), **egress control** on your runners (the payload exfiltrated to `…raw.icp0.io`, which a locked-down runner could not reach), and **least privilege for the scanner itself**. Full treatment in [`../02-SUPPLY-CHAIN-AND-PINNING.md`](../02-SUPPLY-CHAIN-AND-PINNING.md).

**0.2**

```bash
# ── Docker image → digest ─────────────────────────────────────────────────
docker buildx imagetools inspect aquasec/trivy:0.74.0 --format '{{json .Manifest}}' \
  | jq -r '.digest'
# sha256:<64 hex>

# ⚠️ for a MULTI-ARCH image the manifest-list digest and the per-platform
#    digests differ. Pin the MANIFEST LIST digest so every architecture
#    resolves reproducibly:
docker buildx imagetools inspect aquasec/trivy:0.74.0 \
  --format '{{json .Image}}' | jq '.manifest'
```
```yaml
# the reference you commit:
image: aquasec/trivy@sha256:<MANIFEST_LIST_DIGEST>
```

```bash
# ── GitHub Action → commit SHA behind the tag ─────────────────────────────
git ls-remote https://github.com/aquasecurity/trivy-action refs/tags/v0.35.0
# <40-hex-sha>  refs/tags/v0.35.0
```
```yaml
# the reference you commit:
- uses: aquasecurity/trivy-action@<40-hex-sha>   # v0.35.0  ← human-readable comment
```

**Why `@v0.35.0` alone is insufficient:** a tag is a **mutable pointer**. On 19 March 2026 the attacker force-pushed 76 of 77 tags in that exact repository — so `uses: aquasecurity/trivy-action@v0.34.0` resolved to a *different commit* on 20 March than it did on 18 March, with no change to your workflow file, no new release published, and nothing in your diff. A commit SHA is **immutable**: `@<sha>` can only ever mean one tree of files.

⭐ **Three refinements that make the pin actually robust:**
1. **Keep the tag as a comment** (`# v0.35.0`). A bare SHA is unreadable and unmaintainable, so people "clean it up" back to a tag at the first opportunity.
2. **Automate the bump** with Dependabot/Renovate configured for SHA pins, so staying current does not require a human to remember.
3. ⛔ **Do not rely on the tag being immutable just because it survived last time.** `v0.35.0` survived only because that repository had GitHub **immutable releases** enabled — a *setting in Aqua's repo*, not a property of Trivy. They could turn it off, and a future maintainer change could reintroduce the exposure. Your SHA pin is the only control that is yours.

**0.3**

```bash
for base in node:24 node:24-alpine; do
  printf '%-18s ' "$base"
  trivy image --severity CRITICAL,HIGH,MEDIUM,LOW --format json --output - "$base" 2>/dev/null \
    | jq '[.Results[]? | select(.Type=="alpine" or .Type=="debian") | .Vulnerabilities // [] | length] | add // 0'
done
```

Realistic result on a fresh DB: **`node:24` (Debian) ≈ 200–400** OS-package findings; **`node:24-alpine` ≈ 5–30**. Same Node version, same JavaScript, same application risk — the difference is entirely the **OS layer underneath**.

**Mechanically, why:** Trivy does not guess the OS. It reads **the distro's own package database** out of the image filesystem:

| Base | File Trivy reads | Package count |
|---|---|---|
| `node:24` (Debian) | `/var/lib/dpkg/status` (+ `/etc/os-release` → `debian 13`) | ~350 packages: `libc6`, `openssl`, `curl`, `zlib1g`, `apt`, `perl`, `python3-minimal`, `ca-certificates`, `krb5`, `systemd` libs, … |
| `node:24-alpine` | `/lib/apk/db/installed` (+ `/etc/os-release` → `alpine 3.22`) | ~15–50 packages: `musl`, `busybox`, `apk-tools`, `zlib`, `libcrypto`, `ca-certificates` |

Then, for **each package name + version**, it looks up the **distro's advisory feed** — Debian Security Tracker / Ubuntu USN for the first, Alpine **secdb** for the second — and reports the CVEs the distro has acknowledged for that exact version. **More packages ⇒ more advisory lookups ⇒ more findings.** The Node runtime and your JavaScript are identical in both, and contribute zero to that difference.

⭐ **Two second-order effects worth naming:**

1. **Alpine findings also *get fixed* faster in the report.** musl-based images have a small surface, so `apk upgrade` in a rebuilt base clears nearly everything. Debian images carry a long tail of `MEDIUM` in packages nobody patches because they are not worth a release. This is why `--ignore-unfixed` disproportionately shrinks the Debian report.
2. **The severity can differ for the same CVE.** Trivy reports the **distro's** severity for OS packages, not NVD's. Debian frequently downgrades a NVD `CRITICAL` to `LOW` because it back-ported the fix while keeping the upstream version number — so the version string still "matches" the CVE. ⛔ **This is the number-one cause of "Trivy says CRITICAL but it's fine" arguments**, and the resolution is always the same: read whether the distro lists a fixed version, and prefer the distro's assessment for distro packages.

**The engineering conclusion:** choosing `-alpine` (or `distroless`, or `scratch`) is a **security control with a measurable effect on scan output**, not a vanity size optimisation. It is also why the Dockerfile work in [`../../docker-learning-path/`](../../docker-learning-path/README.md) matters here: a multi-stage build that discards the build toolchain removes those packages from the final filesystem, and their CVEs disappear from the report for the same mechanical reason.

**0.4**

```bash
# 1. prove the default is a non-gate
trivy image --severity CRITICAL node:24 > /dev/null; echo "exit=$?"
# exit=0            ⛔ hundreds of CRITICALs, successful exit

# 2. build the gate, prove it fails
trivy image --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 node:24 > /dev/null
echo "exit=$?"
# exit=1            ✅

# 3. a scan that finds CRITICALs and legitimately exits 0
trivy image --severity CRITICAL,HIGH --exit-code 1 \
            --scanners vuln --ignore-unfixed \
            --ignorefile .trivyignore \
            node:24; echo "exit=$?"
# exit=0, but the report still LISTS the ignored CRITICALs
```

**When you want "finds CRITICAL, exits 0" — four legitimate cases:**

1. ⭐ **The INFORM half of the two-report pattern (§8).** You gate on *fixable* findings and separately produce a complete report for risk trending. Making that second scan fail would break the pipeline on things nobody can fix this sprint.
2. **A baseline/audit run.** Your first scan of a legacy repo finds 900 CRITICALs. If that gates, the pipeline is red on day one and gets disabled by day three. You run it non-gating, record the baseline, then gate on *new* findings above it (`--exit-code 1` combined with a comparison step). Same ratchet as Checkov baselines and SonarQube's "Clean as You Code".
3. **`--soft-fail`-equivalent for a rollout.** Rolling Trivy out to 40 repos: run in report-only mode for two weeks, show teams their numbers, *then* flip `--exit-code 1`. Adoption beats enforcement in the first month.
4. **A scan whose findings are already suppressed with an audited reason.** `.trivyignore` (or the structured `.trivyignore.yaml`) removes them from the *gate* while keeping them in the *report* — the suppression is a recorded decision, not a blind spot.

⛔ **When you never want it:** the scan that runs on the artifact you are about to ship to production. If it cannot fail the build, it is a report generator, and reports that cannot fail anything get read by nobody.

**0.5**

```bash
IMAGE=ghcr.io/3558bhk/shop-api@sha256:<digest>

trivy image --format cyclonedx --output sbom.cdx.json "$IMAGE"
trivy image --format json --output image-report.json "$IMAGE"
trivy sbom  --format json --output sbom-report.json  sbom.cdx.json

for f in image-report sbom-report; do
  printf '%-14s ' "$f"
  jq '[.Results[]?.Vulnerabilities // [] | length] | add // 0' "$f.json"
done
```

Counts come out close — usually within a few percent — because both are resolving the same package inventory against the same advisory DBs.

⭐ **The finding that appears in the image scan but not the SBOM scan: an OS-package vulnerability** — typically something like `CVE-20xx-xxxx` in `libc6` / `musl` / `openssl` reported under `"Type": "debian"` or `"alpine"`.

**Why.** A CycloneDX SBOM produced by `trivy image` is built from the **language-package manifests** it found (`package-lock.json`, `pom.xml`, `go.sum`, `requirements.txt`, …) plus, depending on your Trivy version and flags, OS packages. Two things go wrong for the OS side:

1. **`trivy sbom` re-resolves from SBOM component metadata**, and OS packages in an SBOM often lack the **distro context** (`"Type": "debian"`, OS name + version) that Trivy needs to pick the right advisory feed. Without it, either the component is not matched at all or it is matched against the wrong source.
2. Some CycloneDX producers emit OS packages with a **PURL** that omits the distro qualifier (`pkg:deb/debian/openssl@3.0.11` vs `pkg:deb/openssl@3.0.11`), and the unqualified form cannot be resolved to a specific advisory stream.

```bash
# prove which components are present in each
jq -r '.Results[]?.Type' image-report.json | sort -u      # debian, jar, gobinary, …
jq -r '.Results[]?.Type' sbom-report.json  | sort -u      # often only the language ones
jq '[.components[].purl] | map(select(startswith("pkg:deb") or startswith("pkg:apk"))) | length' sbom.cdx.json
```

⭐ **The practical consequence — and it is the reason to keep both:** an SBOM scan is **fast, offline and portable** (it answers "are we affected?" across a thousand artifacts in seconds, with no registry access), but it is **less complete** than scanning the image. So: **scan the image in CI for the gate**, and **keep the SBOM as the artifact for incident response and audit**. Never replace the first with the second, and never throw away the second — during a log4j-class event the SBOM folder is the only thing that gets you an answer before the next standup.

**0.6**

```bash
# ── CAUSE IT ──────────────────────────────────────────────────────────────
# Make the cached DB look old, and block the update.
mv ~/.cache/trivy/db/metadata.json ~/.cache/trivy/db/metadata.json.bak
cat > ~/.cache/trivy/db/metadata.json <<'EOF'
{"Version":3,"NextUpdate":"2025-01-01T00:00:00Z","UpdatedAt":"2024-12-31T00:00:00Z","DownloadedAt":"2024-12-31T00:00:01Z"}
EOF
# now block egress to the DB registry so it cannot refresh
sudo iptables -A OUTPUT -d $(dig +short ghcr.io | tail -1) -j REJECT   # or just drop network
trivy image node:24-alpine
# FATAL  DB error: the database is older than the allowed age
```

**Three fixes:**

```bash
# FIX A — let it update (restore egress, refresh the DB)
sudo iptables -D OUTPUT …            # undo the block
trivy image --download-db-only       # ⭐ shows the REAL error: DNS/proxy/auth
trivy image node:24-alpine
```
✅ **Appropriate for CI.** This is the normal, correct path: your runners have scoped egress to `ghcr.io` (and your internal mirror), the DB stays fresh, and results reflect today's advisories. ⭐ The corollary is that **runner egress policy must explicitly allow the DB registry** — and the error message names neither network nor registry, so this is diagnosed wrongly about half the time.

```bash
# FIX B — skip the age check and use what you have
trivy image --skip-db-update node:24-alpine
```
✅ **Appropriate for air-gapped.** You have deliberately transferred a DB snapshot (§6), you know its age, and there is no network to refresh from. ⚠️ But record the DB's `UpdatedAt` in your evidence — an air-gapped scan against a nine-month-old DB is *a scan as of nine months ago*, and saying so is the difference between evidence and a false attestation.

```bash
# FIX C — offline mode
trivy image --skip-db-update --offline-scan node:24-alpine
```
⛔ **Appropriate for never as a routine CI setting.** `--offline-scan` also suppresses other network paths, so you lose the ability to enrich findings and you will not notice when the DB has gone stale — the scan keeps succeeding with increasingly old data, silently. It exists for genuinely isolated environments, not as a way to make an annoying CI error go away.

⭐ **The meta-point:** this error is a **networking failure wearing a scanner costume**. The debugging move is always `--download-db-only`, which turns a FATAL age error into the actual DNS/proxy/TLS/auth error underneath.

**0.7**

```bash
IMAGE=ghcr.io/3558bhk/shop-api@sha256:<digest>
rm -rf ./.trivycache

echo "── cold ──"; time trivy image --cache-dir ./.trivycache --no-progress "$IMAGE" > /dev/null
echo "── warm ──"; time trivy image --cache-dir ./.trivycache --no-progress "$IMAGE" > /dev/null
du -sh ./.trivycache/*
```

Realistic numbers on a ~250 MB Java image with a warm DB:

| | Cold | Warm |
|---|---|---|
| **Wall clock** | **~45–90 s** | **~4–12 s** |
| DB download | yes (if >12 h old) | no |
| Layer pull + analysis | yes, all layers | ⭐ **no** |
| Advisory matching | yes | yes |

**What was reused, exactly:**

```
.trivycache/
├── db/          ← trivy-db. Reused if younger than 12 h. (not what makes this fast)
├── java-db/     ← trivy-java-db, if JARs present
└── fanal/       ← ⭐ THE WIN. Layer analysis cache
```

The `fanal` cache is keyed on **layer digest**. For each layer Trivy stores the *extracted package inventory* — the parsed `dpkg/status`, `apk/db/installed`, `package-lock.json`, `pom.xml`, JAR SHA-1s, etc. On a warm run it looks up each layer digest, gets a hit for every unchanged layer, and skips extraction entirely; only the advisory matching runs.

⭐ **Why that is a big deal in CI, and what follows from it:**

- Images share **base layers**. Your 40 services all use `eclipse-temurin:21-jre-alpine` or `node:24-alpine`, so after the first scan of the first service, every subsequent service's base layers are cache hits. A warm monorepo CI run scans 40 images in roughly the time it takes to scan 4 cold.
- A cache keyed on layer digest is **self-invalidating and always correct**. Rebuilding changes your app layers' digests; unchanged layers keep their digests. ⛔ So do **not** key your CI cache on the git commit SHA — you would invalidate a perfectly good layer cache on every commit and gain nothing. Key it on nothing (or on a fixed name) and let content-addressing do the work.
- The DB is the *other* half: cache `~/.cache/trivy/db` too, or every job spends 30 s re-downloading 600 MB.

File [`03`](03-CI-CD-INTEGRATION.md) writes this out for GitHub Actions, Jenkins and Azure DevOps.

**0.8** ⭐⭐ **Diagnosis: the configuration is gating on the wrong axis.** Nothing is wrong with the developers — they are rationally suppressing findings they cannot fix, because the gate demands they fix findings that have no fix. Three specific defects:

**Defect 1 — no `--ignore-unfixed`.** This is the root cause of everything downstream. A `CRITICAL` in a package with **no patched version available** is not actionable by a developer in a PR: they cannot bump to a fix that does not exist, and they usually cannot remove the dependency either. The gate is asking for the impossible, so the only satisfying move is suppression. ⛔ Every one of those four repeated CVEs is almost certainly unfixable — and the fact that three developers independently ignored the *same four* is the signature: they all hit the same wall.

**Defect 2 — gating the whole image, not new exposure.** The gate fires on every finding in every layer, including base-image OS packages nobody on the team introduced. A developer changing one line of Java is being blocked by a Debian `openssl` advisory. That mismatch between **who is accountable** and **who is blocked** is what turns a security control into an obstacle people route around.

**Defect 3 — `.trivyignore` is unstructured and unowned.** A plain `.trivyignore` is a list of CVE IDs with no reason, no owner, no expiry and no review. Three PRs adding the same four entries means: (a) it is not merged/centralised, so each team re-discovers the same suppressions; (b) there is no record of *why*, so nobody can tell a considered decision from a panic; (c) there is no expiry, so a suppression made for a good reason in 2026 is still silently active in 2029 when a real fix finally ships.

**Defect 4 — and the `openssl` one is the dangerous case.** Someone ignored a `CRITICAL` in `openssl`. If that was an *unfixed* advisory, the ignore is defensible-but-unrecorded. If it was **fixable**, they suppressed a real, patchable TLS vulnerability to get a PR merged — and with a bare `.trivyignore` nobody will ever know which. ⛔ **That ambiguity is the actual incident.**

**The replacement flag set:**

```bash
# ── GATE: actionable findings only ────────────────────────────────────────
trivy image \
  --scanners vuln,secret \
  --severity CRITICAL,HIGH \
  --ignore-unfixed \                      # ⭐ THE FIX. Gate only on what can be fixed
  --exit-code 1 \
  --format sarif --output gate.sarif \
  --ignorefile .trivyignore.yaml \        # ⭐ structured, owned, expiring
  --timeout 10m --cache-dir .trivycache --no-progress \
  "$IMAGE_DIGEST"

# ── INFORM: everything, never gates ───────────────────────────────────────
trivy image --format json --output full-report.json "$IMAGE_DIGEST" || true
```

Plus four configuration changes that matter more than any flag:

1. **Replace `.trivyignore` with `.trivyignore.yaml`** — every suppression carries an owner, a reason, an issue link and an **expiry**:
   ```yaml
   vulnerabilities:
     - id: CVE-2026-xxxxx
       statement: "No fixed version published by Debian; openssl used only for
                   outbound TLS to internal services. Compensating control:
                   egress NetworkPolicy restricts to the mesh."
       issue: https://github.com/yourorg/shop/issues/4412
       expired_at: 2026-12-31          # ⭐ forces re-review; Trivy fails when it expires
   ```
2. **One central suppression file per repo, code-owned, reviewed like code** — not per-developer, not per-PR. Three PRs adding the same entries means there was no shared place to put them.
3. **Move the gate to where accountability lives.** Scan the **base image** on its own schedule (nightly, its own ticket queue, owned by platform). Scan the **application image** in the PR pipeline. A developer is then gated on findings their change can actually influence.
4. **Treat an expired or unowned suppression as a build failure.** That converts `.trivyignore` from a junk drawer into a decision register — which is also what [`../03-COMPLIANCE-REPORTING-AND-AUDIT.md`](../03-COMPLIANCE-REPORTING-AND-AUDIT.md) needs to produce for an auditor.

⭐ **The meta-lesson:** when developers suppress findings in a loop, **the gate is misconfigured, not the developers.** A gate that cannot be satisfied teaches people that the way to ship is to disable the control. `--ignore-unfixed` plus structured, expiring suppressions turns "route around it" back into "fix it or record why you can't".

**0.9** ⭐⭐ One page.

---

### Trivy scanning standard — 40 repos, no security team

**Ownership model.** ⭐ There is no security team, so **the team that owns the repo owns its findings.** Platform owns the *tooling, the pinned version, the shared config and the base images*. Nobody owns a central triage queue — because a queue nobody staffs is where findings go to die. Every rule below exists to make findings land on an owner automatically.

**What gets scanned, where, with what:**

| Stage | Artifact | Scanners | Gate | Who sees it |
|---|---|---|---|---|
| **PR** | source tree (`trivy fs`) | `secret` | ⛔ **fail on any secret** — non-negotiable, zero tolerance | PR author, as a SARIF comment on the changed lines |
| **PR** | the image the PR builds | `vuln` (CRITICAL,HIGH) + `misconfig` (HIGH,CRITICAL) | ✅ **fail, but `--ignore-unfixed`** and **new-findings-only** vs the base branch | PR author, SARIF PR comment |
| **Merge to `main`** | published image **by digest** | `vuln`, `secret`, `misconfig`, `license` | ✅ fail → blocks the release train | repo owners' channel |
| **Nightly** | every published digest from the last 90 days | `vuln` (all severities) | ⚠️ **report only** | a single dashboard + a weekly digest issue per repo |
| **Nightly** | base images (`node:24-alpine`, `temurin:21-jre-alpine`, `nginx:1.29-alpine`, `mongo@sha256:…`) | `vuln` | ⚠️ report → **platform** owns the bump | platform team |
| **Weekly** | the live cluster (`trivy k8s` / trivy-operator) | everything | ⚠️ report | platform + repo owners |

**The exact gate command** (identical in all 40 repos — one shared config, not forty):

```bash
trivy image --scanners vuln,misconfig,secret \
  --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 \
  --ignorefile .trivyignore.yaml \
  --format sarif --output gate.sarif \
  --timeout 10m --cache-dir .trivycache --no-progress \
  "$IMAGE_REF"          # ⭐ always a DIGEST, never a tag
```

**Distribution:** a shared reusable workflow / shared-library job / template YAML — **not** copy-paste per repo. One place to change the version pin, one place to change thresholds. Repos inherit; they may make the gate **stricter**, never weaker, and a weaker override requires a recorded exception with an expiry.

**Pinning.** Trivy pinned by **digest**; `trivy-action` by **commit SHA** with the tag as a comment; Renovate bumps both and the bump PR is auto-approved if only the digest changed. ⛔ No `latest`, no bare tags, anywhere. (`../02-SUPPLY-CHAIN-AND-PINNING.md`)

**Baselines and the ratchet.** Legacy repos start with a recorded baseline (the finding set on day one) and gate on **new findings only**. Baselines are visible, dated and **burn down at a fixed rate** — e.g. 10% per quarter — with the remaining count on the team's dashboard. ⭐ A baseline that never shrinks is a permanent exemption; put the number where the team can see it.

**Suppression.** Only `.trivyignore.yaml`, only in the repo root, only with **all four** fields: `statement` (why), `issue` (link), `expired_at` (date), and a CODEOWNERS-required reviewer. **An expired suppression fails the build** — that is what makes the expiry real. ⛔ A bare `.trivyignore` with a list of CVE IDs is rejected in review.

**Reporting.** SARIF → GitHub code scanning (findings appear on the PR diff, in front of the author). JSON → a nightly aggregate into one dashboard: findings per repo, age of oldest fixable CRITICAL, baseline remaining, suppression count and expiry dates. ⭐ **Those four numbers are the whole programme.** Not total CVE count — that number only ever goes up and teaches everyone to ignore it.

**⭐ A digest that becomes non-compliant three months after shipping.** This *will* happen — the DB updates every 6 hours, so an image that passed on 1 June can fail on 2 June with no change on your side. Handling it:

1. **Do not retroactively fail the release that shipped it.** The nightly scan detects it; the *deploy* pipeline does not re-litigate history. Blocking a past decision creates noise and teaches people to distrust the gate.
2. **It opens an issue against the owning team**, with severity → SLA:
   - fixable **CRITICAL** on a **running** workload → **7 days**
   - fixable **HIGH** on a running workload → **30 days**
   - unfixable → **compensating control required**, recorded, with an owner and a review date
   - not running (an old tag nobody deploys) → **stop publishing it**; delete or mark deprecated
3. **The fix is a rebuild, not a patch.** Because images are immutable, remediation means: bump the base image or the dependency → rebuild → **new digest** → normal pipeline. ⭐ Which is why the *base-image nightly scan* exists — most retroactive findings come from a shared base, so platform fixes it once and 40 repos inherit the bump.
4. **If you cannot rebuild in the SLA**, record a compensating control (NetworkPolicy, no public exposure, WAF rule) with an expiry, exactly like a suppression — a decision, not a gap.

**The one rule that holds it together:** ⭐ **every finding has exactly one owner, and every exception has an expiry.** With no security team, those two properties are the entire control environment. Everything else — the pinned digests, the two-report pattern, `--ignore-unfixed`, SARIF on the PR — exists to make those two things true at 40-repo scale without anyone having to remember.

</details>

---

## ➡️ Next

**[`01-FIRST-SCAN-AND-READING-OUTPUT.md`](01-FIRST-SCAN-AND-READING-OUTPUT.md)** — your first real scan, and how to read it: severity vs fixability vs reachability, the ten output formats, and how to turn 400 findings into the 6 that matter.

**Or jump straight to CI:** [`03-CI-CD-INTEGRATION.md`](03-CI-CD-INTEGRATION.md) — GitHub Actions, Jenkins and Azure DevOps with digest pinning, DB caching, and SARIF PR comments.

**Read alongside:** [`../02-SUPPLY-CHAIN-AND-PINNING.md`](../02-SUPPLY-CHAIN-AND-PINNING.md) — the March 2026 Trivy compromise as a full case study.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
