# 14 · DevSecOps & Security

Increasingly a first-class loop (DevSecOps roles) and a mandatory component of every senior DevOps/Platform interview. The differentiator is **threat modelling, supply-chain thinking, and knowing where each control actually holds.**

---

## 🟢 Basic

### 1. What is DevSecOps, really? Not "add a scanner to CI."
**Shifting security left is a slogan; the substance is: security decisions and enforcement happen inside the normal development and delivery workflow, at the point where changing your mind is cheap, with feedback fast enough that developers act on it.**

Concretely, security is embedded at five points:
| Point | Controls |
|---|---|
| **Design** | Threat modelling (STRIDE/attack trees), abuse-case reviews, data classification, architecture review for high-risk changes |
| **Code** | SAST, secrets scanning, dependency/SCA, licence checks, secure coding standards, IDE plugins (feedback in seconds) |
| **Build** | Reproducible builds, pinned dependencies, signed artifacts, SBOM, provenance, hardened base images, image scanning |
| **Deploy** | Policy-as-code at admission, config scanning (CSPM/KSPM), signed-image verification, least-privilege workload identity, secrets injection at runtime |
| **Run** | Runtime threat detection, vulnerability management, WAF/DDoS, audit logging, incident response, continuous compliance evidence |

**The three things that make it work (and that most teams miss):**
1. **Feedback speed.** A finding in the IDE in 5 seconds changes behaviour; the same finding in a weekly security report gets ignored. **Gate at the point of lowest friction.**
2. **Actionability.** A report of 4,000 CVEs is noise. "3 reachable, fixable, critical CVEs in code you own, with the upgrade command" is work. **Triage by reachability and exploitability, not CVSS score alone.**
3. **Ownership.** Security teams that *find* problems and hand them over create resentment and backlog. Security teams that *build the guardrail and the paved road* so the secure option is the default option scale. **"Enable, don't gate"** — a gate with no alternative gets routed around.

**The mature framing:** "DevSecOps isn't a toolchain, it's a delivery model: the platform team owns the guardrails (policies, hardened images, modules, scanners with tuned rules, break-glass), application teams own their risk within those guardrails, and the security team owns the standards, the detection of the unknown, and the incident response. That division is what lets it scale past ~20 teams. A central security team that must approve everything becomes the bottleneck and gets bypassed; a security team that only writes policies nobody enforces becomes decoration."

### 2. Threat modelling — STRIDE and how to actually run one
**STRIDE** (per element/interaction in a data-flow diagram):
| Threat | Violates | Question to ask | Example |
|---|---|---|---|
| **S**poofing | Authentication | Can someone pretend to be another identity? | Stolen API key, missing mTLS, a pod impersonating another's ServiceAccount |
| **T**ampering | Integrity | Can data/config be modified in transit or at rest? | Unsigned images, writable ConfigMap, MITM, a mutable tag |
| **R**epudiation | Non-repudiation | Can an actor deny what they did? | No audit logs, shared credentials, logs an attacker can delete |
| **I**nformation disclosure | Confidentiality | Can secrets/PII leak? | Public S3 bucket, plaintext state file, verbose errors, log leakage |
| **D**enial of service | Availability | Can the service be made unavailable? | Unbounded resource use, no rate limit, a fork bomb, connection exhaustion |
| **E**levation of privilege | Authorisation | Can a low-privilege actor gain more? | Container escape, `privileged: true`, cluster-admin SA token in every pod, a wildcard IAM policy |

**How to run one (a repeatable 90-minute session):**
1. **Draw the data flow**: external entities, processes, data stores, trust boundaries. **Trust boundaries are where the threats live** — every crossing deserves a question.
2. **Enumerate assets**: what's worth stealing or breaking (credentials, PII, payment data, signing keys, availability of a revenue path)?
3. **Apply STRIDE to each element and each flow.** Write down threats, not solutions yet.
4. **Rank** by likelihood × impact (or use **DREAD**, or just "would this be a P1?").
5. **Map mitigations**: existing controls (what already defends this?), gaps, and new controls. **Recording existing controls matters** — otherwise you re-invent mitigations you already have.
6. **Produce action items with owners**, and re-run on major architecture changes.

**Practical alternatives/additions:**
- **Attack trees** — root node = goal ("exfiltrate the customer database"), branches = paths. Better for a focused adversary question.
- **Abuse cases / misuser stories** — "as an authenticated tenant, I want to read another tenant's data" alongside the user stories. **Cheap, and developers engage with it more readily than STRIDE tables.**
- **CAPEC/MITRE ATT&CK** for mapping to known techniques, especially for runtime/cloud (ATT&CK for Containers, for Cloud, for IaaS).
- **Threat modelling as code**: keep the DFD and the threat register in the repo, versioned with the architecture. Otherwise it's a document nobody re-reads.

**The line that scores:** "Threat modelling's real value isn't the list of threats — it's that it forces the team to articulate **trust boundaries** and **what's worth protecting**, which usually reveals an assumption nobody had said out loud ('oh, we assumed the internal network was trusted'). That assumption is the vulnerability."

### 3. OWASP Top 10 (2021) — and the infra-relevant ones
1. **Broken Access Control** — by far the most common. IDOR (referencing objects by guessable IDs without an ownership check), missing function-level auth (the admin endpoint that's only hidden in the UI), path traversal, forced browsing, CORS misconfiguration, **JWT `alg: none` / unverified signatures**, IDOR in GraphQL/APIs. **Prevention: deny by default, authorise on every request server-side, use indirect references, test authorisation as thoroughly as functionality.**
2. **Cryptographic Failures** — sensitive data in transit or at rest unprotected; weak algorithms (MD5/SHA1 for signatures, DES, RC4); hardcoded keys; poor key management; **TLS misconfiguration** (old protocols, weak ciphers, missing HSTS); sensitive data in URLs/logs/backups.
3. **Injection** — SQL, NoSQL, LDAP, OS command, **template injection**, **expression-language injection** (Log4Shell was JNDI/EL injection), **Kubernetes YAML/Helm template injection**, IaC injection. **Prevention: parameterised queries/prepared statements, allowlist validation, escaping for the *specific* interpreter, and least privilege on the executing identity.**
4. **Insecure Design** — a *category*, not a bug class: missing rate limits on password reset, a business-logic flaw allowing unlimited coupons, no idempotency on payment. **Cannot be fixed by secure coding — it needs threat modelling at design time. This is why OWASP added it.**
5. **Security Misconfiguration** — default credentials, unnecessary features/ports/services enabled, verbose errors in production, **missing security headers**, **public cloud storage**, unpatched systems, **`privileged: true` containers**, permissive RBAC, missing NetworkPolicy. **This is the category that dominates cloud and Kubernetes breaches.**
6. **Vulnerable and Outdated Components** — using a library with a known CVE, not knowing what you use (hence SBOM), not patching.
7. **Identification and Authentication Failures** — credential stuffing (no rate limiting/MFA), weak passwords, session IDs in URLs, session fixation, sessions that don't expire or don't rotate on privilege change, **long-lived static keys**.
8. **Software and Data Integrity Failures** — **the supply-chain category**: unsigned/unverified updates, insecure CI/CD pipelines, **deserialisation of untrusted data**, unsigned container images, dependency confusion, typosquatting. **This is the category that grew most and the one DevSecOps roles care about most.**
9. **Security Logging and Monitoring Failures** — no audit log, logs not reviewed, no alerting on suspicious activity, logs an attacker can tamper with. **Directly the observability topic — and the reason breaches average ~200+ days to detect.**
10. **Server-Side Request Forgery (SSRF)** — the server fetches an attacker-supplied URL → reaches internal services or **the cloud metadata endpoint (169.254.169.254)** → credential theft. **The Capital One breach.** Prevention: allowlist destinations, block private/link-local ranges and IMDS at the network layer, **enforce IMDSv2/hop-limit 1**, disable unnecessary URL-fetching features, and use egress filtering.

**The infra-specific additions worth naming:** **CI/CD pipeline compromise** (the highest-value target — see [`08-CI-CD-and-GitOps`](../08-CI-CD-and-GitOps/README.md#7-pipeline-security--because-cicd-is-the-highest-value-target)), ** IaC misconfiguration** (Terraform/CloudFormation/Helm as an attack surface — a public S3 bucket is a one-line typo), **container/Kubernetes escape and misconfiguration**, and **cloud identity/permission sprawl**.

### 4. The CIA triad and the security properties you'll be asked to define
- **Confidentiality** — only authorised principals can read it. Controls: encryption (at rest, in transit, ideally in use), access control, secret management, data classification, DLP, network segmentation.
- **Integrity** — it hasn't been modified by an unauthorised party (or in an unauthorised way). Controls: hashing/signing (code signing, image signing, commit signing), checksums, WORM/immutable storage, version control, admission verification, audit trails, TLS.
- **Availability** — authorised users can use it when needed. Controls: redundancy, autoscaling, rate limiting, load shedding, DDoS protection, backups + tested restores, chaos testing, capacity planning.
- **Plus the ones that come up in infra interviews:**
  - **Authentication** (who are you) vs **Authorisation** (what may you do) vs **Accounting/Audit** (what did you do) — the AAA model.
  - **Non-repudiation** — you can't deny having done it (requires signed, tamper-evident, timestamped audit records).
  - **Defence in depth** — layered controls so a single failure isn't a compromise.
  - **Least privilege** — the minimum permission for the minimum time for the minimum scope.
  - **Zero trust** — never trust the network location; verify every request; assume breach. **Concretely: strong identity per request, mutual TLS or per-request auth, micro-segmentation, no implicit internal trust, continuous verification, and least-privilege short-lived credentials.** The useful test: "would this architecture still work if an attacker had a foothold on the internal network?" If yes, you have some zero trust; if no, you have a perimeter.
  - **Assume breach** — design so a compromise yields minimal value and loud detection (short-lived creds, no lateral paths, egress filtering, runtime detection, immutable audit logs shipped off-box).

### 5. Encryption in practice — TLS, at rest, key management
**TLS:**
- **TLS 1.2 minimum, 1.3 preferred** (1.3 removes obsolete cipher suites, does 1-RTT handshakes with 0-RTT resumption, and encrypts more metadata). Disable SSLv3/TLS 1.0/1.1.
- **Cipher suites**: prefer AEAD (`AES-GCM`, `ChaCha20-Poly1305`) with ECDHE key exchange. **Disable static RSA key exchange — it breaks forward secrecy.**
- **Forward secrecy (PFS)**: the session key is derived from an ephemeral DH/ECDHE exchange, so **compromising the server's long-term private key does not let an attacker decrypt previously captured traffic.** This matters for anything with long-term confidentiality value (health, financial, legal, personal messages).
- **mTLS**: both sides present certificates → mutual authentication. **The basis of service-mesh security and zero-trust service-to-service auth.** Requires a CA and automated rotation (cert-manager + a short-lived cert policy, SPIFFE/SPIRE for workload identity).
- **Certificate lifecycle**: ACME/Let's Encrypt automation (cert-manager), **monitor expiry** (a classic total-outage cause — including intermediate CA expiry and, famously, chain-validation breakages), correct SAN/CN, OCSP stapling, HSTS, and **don't forget internal certificates** (they expire too and nobody watches them).
- **Certificate pinning** for clients (mobile/CLI): stronger, but **a rotation mistake becomes an unrecoverable outage** — pin to an intermediate or keep backup pins.

**At rest:**
- **Encryption everywhere by default**: disks (EBS/Persistent Disk/Managed Disks), object storage (SSE-KMS/customer-managed keys), databases (TDE), backups, snapshots, and **Terraform state** (see [`09-IaC-Terraform`](../09-IaC-Terraform/README.md#14-how-do-you-manage-secrets-with-terraform-very-commonly-asked-theres-a-right-answer)).
- **Envelope encryption**: a **data key** encrypts the data; a **key-encryption key (KEK)** in an HSM/KMS encrypts the data key. You get HSM-grade protection of the root key without sending all your data through the HSM. **Knowing envelope encryption and why it exists (performance + blast radius) is a strong signal.**
- **Key management discipline**: separate keys per environment/tenant/workload (blast radius), **key rotation** (with re-encryption or versioned keys), **least-privilege key policies**, **CloudTrail/audit logging of key use** (an unused key being used is an alert), **deletion protection / waiting periods** on key deletion (deleting a KMS key destroys the data irrecoverably), and **custody separation** (the team that uses the key shouldn't be able to export or delete it).
- **HSM-backed / FIPS 140-2 Level 3** where compliance requires it.
- **In use**: confidential computing (SGX/TDX/SEV, confidential GKE/Azure confidential containers) for genuinely sensitive multi-tenant compute — niche but increasingly asked about.

### 6. Secrets management — the hierarchy of answers
From worst to best:
1. **Hardcoded in source** ❌ (in Git history forever; rotate, don't just delete)
2. **In a `.env` committed to the repo** ❌
3. **In CI/CD variables with broad scope** ⚠️ (leaks via logs, forks, compromised pipelines)
4. **In Kubernetes Secrets** ⚠️ (base64, not encrypted by default — needs etcd encryption-at-rest + tight RBAC; better than env vars since it's a tmpfs mount)
5. **In a cloud secret manager** (Secrets Manager / Key Vault / Secret Manager) ✅ — with IAM-scoped access, audit logging, and rotation
6. **Synced into Kubernetes by External Secrets Operator** ✅ — cloud is the source of truth, K8s Secret is a projection
7. **Sealed Secrets / SOPS+age** ✅ for GitOps — encrypted values committed to Git, decrypted in-cluster
8. **Dynamic, short-lived credentials generated on demand** ✅✅ — **Vault dynamic secrets** (a database user created for this workload with a 1-hour TTL, revoked automatically), **cloud workload identity** (OIDC/IRSA/managed identity → STS token, no secret at all)
9. **No secret at all** ✅✅✅ — workload identity federation, mTLS with SPIFFE-issued short-lived certs, Kerberos-style tickets. **The best secret is the one that doesn't exist.**

**Rotation:** automated (secret managers with rotation Lambdas/functions, Vault dynamic secrets), or scheduled with overlap (two valid versions during rotation, so nothing breaks). **Manual rotation is why secrets live for years and why a leaked key from 2023 still works.**

**Detection:** secrets scanning in pre-commit and CI (gitleaks, trufflehog — **trufflehog verifies whether a found credential is still live**, which massively improves triage), push protection, and **a process for what to do when one is found: rotate first, investigate second, delete third.**

**The interview line:** "My rule is: prefer identity over secrets; prefer short-lived over long-lived; prefer generated over stored; and never let a secret be readable by more principals than need it. Every step down that list is a real reduction in blast radius, and most teams are two or three steps below where they could be with a week of work."

---

## 🔵 Advanced

### 7. Software supply chain security — the modern core of DevSecOps
**Threat model:** your software is assembled from hundreds of third-party components, built by a pipeline with cloud credentials, distributed through registries, and deployed by an agent with cluster-admin. **Every one of those is an attack surface, and attacking the pipeline is more efficient than attacking the product** (one compromise → every customer).

**Real incidents to be able to reference:** SolarWinds/SUNBURST (build system), Codecov (a CI bash script modified in a Docker build), event-stream (npm package ownership transfer + malicious dependency), ua-parser-js / coa / rc (npm credential theft → mining packages), Log4Shell (a transitive dependency in *everything*), Travis CI (secret exposure across customers), 3CX (a compromised upstream vendor → supply chain of a supply chain), xz-utils backdoor (a social-engineering maintainer takeover targeting SSH). **The pattern: trust is transitive, and transitive trust is the vulnerability.**

**The control set (map to SLSA):**
| Layer | Control | Tooling |
|---|---|---|
| **Source** | Signed commits, branch protection, required reviews, CODEOWNERS, no force-push, 2FA/hardware keys for maintainers | GitHub/GitLab native, Sigstore/GPG |
| **Dependencies** | Lockfiles committed, pinned versions, **pinned by digest/commit SHA**, private registry mirror/proxy (so you're not at the mercy of a public registry outage or a mutation), dependency review on additions, **typosquat/dependency-confusion detection** | Renovate/Dependabot, npm/Gemnasium proxies, Artifactory/Nexus, Socket.dev, `pip --index-url` internal |
| **Build** | **Isolated, ephemeral, hermetic builds**; no ambient credentials; **OIDC federation for cloud access**; reproducible builds (`SOURCE_DATE_EPOCH`); no interactive access to build machines | BuildKit, Bazel/Nix (hermeticity), GitHub Actions with `permissions: {}` |
| **Provenance** | **SLSA provenance attestation**: what source, what builder, what parameters produced this artifact | `buildx --provenance`, SLSA GitHub generator, in-toto, Sigstore |
| **Signing** | Sign images/artifacts; **keyless signing** via Sigstore Fulcio (identity-based) + Rekor (transparency log) removes long-lived signing keys | cosign, Notation, Sigstore |
| **SBOM** | Generate SPDX/CycloneDX at build time, store with the artifact, **use it for CVE→affected-service lookup** | syft, `docker sbom`, `buildx --sbom`, Anchore |
| **Scanning** | SAST, SCA, container image, IaC, secrets — with **reachability-based triage** | semgrep/CodeQL, Trivy/Grype/Dependabot, checkov/tfsec, gitleaks |
| **Distribution** | Immutable tags, **deploy by digest**, registry access control, garbage collection, replication | ECR/GCR/ACR/Harbor |
| **Verification at deploy** | **Admission control that verifies the signature and provenance before the workload runs** — the control that actually enforces everything above | **Kyverno**, Connaisseur, policy-controller, **Binary Authorization (GKE)**, Sigstore policy-controller |
| **Runtime** | Read-only rootfs, dropped capabilities, seccomp/AppArmor, **user namespaces**, no privileged, egress filtering, runtime threat detection | PSA `restricted`, Falco/Tetragon |

**SLSA levels (know the shape, not the memorised detail):** a framework for build integrity. **L1** = provenance exists; **L2** = provenance is signed and hosted, tamper-resistant; **L3** = hardened, isolated builds with non-falsifiable provenance (the practical target); **L4** (in older versions) = reproducible two-person-reviewed builds. **SLSA v1.0** restructured into tracks (Build L1–L3, plus Verification and Source tracks). **The point to make:** "SLSA gives you a vocabulary for 'how much can I trust this artifact?' and a maturity ladder — and the level you need depends on your threat model. For most internal services, L2 with signed provenance and admission verification is a proportionate target; L3 for anything distributed to customers or running untrusted code."

**VEX (Vulnerability Exploitability eXchange):** the missing piece of vulnerability management. A CVE in a dependency isn't automatically a problem: is the vulnerable code **reachable** in your build? VEX lets a supplier (or you) assert status — `not_affected`, `affected`, `fixed`, `under_investigation` — with justification. **This is what turns "4,000 CVEs" into "3 things to do", and it's the answer to "how do you handle scanner noise?"**

### 8. Kubernetes security in depth
**The layered model (work inward):**
1. **Cluster hardening**: managed control plane, restricted apiserver exposure (private endpoints only, or with authorised networks), etcd encryption at rest, current version (patch cadence — **Kubernetes supports only 3 minor versions, so you must upgrade ~3×/year**), audit logging enabled and shipped off-box, `NodeRestriction` admission plugin (prevents a kubelet impersonating others).
2. **Authentication/authorisation**: no anonymous access, OIDC-federated humans, short-lived projected SA tokens, `automountServiceAccountToken: false` by default, **RBAC least privilege with `resourceNames`**, and a policy that flags cluster-admin grants.
3. **Admission control**: **Pod Security Admission** at `restricted` for app namespaces (`privileged`/`baseline` only for infra with justification), **Kyverno/Gatekeeper/VAP** for org-specific invariants: approved registries only, no `latest`, required labels/annotations, resource requests mandatory, no hostPath/hostNetwork/hostPID/privileged, image signature verification, allowed `runAsUser` ranges.
4. **Pod hardening**: non-root, read-only rootfs, drop ALL capabilities (+ `NET_BIND_SERVICE` only if needed), `allowPrivilegeEscalation: false`, seccomp `RuntimeDefault`, AppArmor/SELinux profile, **user namespaces (`hostUsers: false`, GA in 1.36)** — the strongest escape mitigation, resource requests+limits, `pids` limits.
5. **Network**: default-deny NetworkPolicy per namespace with explicit allows, DNS allowed, **egress to the cloud metadata endpoint blocked for untrusted workloads**, network segmentation between tiers, and a CNI that actually enforces policy (verify with a test).
6. **Secrets**: no secrets in Git or images; External Secrets / Vault / CSI secret driver; etcd encryption; RBAC on `secrets` treated as a crown-jewel permission (reading secrets ≈ cluster admin).
7. **Runtime detection**: **Falco** (syscall rules: shell spawned in a container, sensitive file writes, unexpected outbound connections, k8s API anomalies) or **Tetragon** (eBPF, kernel-level, enforce-and-alert). **Assume a workload gets compromised; the question is how fast you see it and how far it gets.**
8. **Supply chain**: signed images verified at admission, SBOMs, provenance, immutable digests, scanned base images on a rebuild cadence.
9. **Multi-tenancy**: namespaces + RBAC + quotas + PSA + NetworkPolicy for soft tenancy; **+ RuntimeClass (gVisor/Kata) + user namespaces + dedicated node pools** for hard tenancy (see [`07-Kubernetes`](../07-Kubernetes/README.md#18-multi-tenancy--how-much-isolation-can-kubernetes-actually-give)).
10. **Audit & response**: K8s audit logs (policy: Metadata by default, RequestResponse for sensitive resources) → central SIEM; **know how to investigate a compromised pod**: isolate (NetworkPolicy/`kubectl cordon` + delete), preserve (logs, `kubectl cp` of evidence, container snapshot), revoke (rotate SA tokens, cloud credentials the pod had, secrets it could read), and re-build rather than clean.

**The two Kubernetes-specific insights worth stating:**
- **"The cluster is only as secure as its weakest workload."** With runc, a kernel LPE from any pod can reach the node. So pod-level hardening and node-level isolation aren't optional extras; they're the containment model.
- **RBAC on `pods/exec`, `secrets`, and `ClusterRoleBinding create` are effectively cluster-admin.** Audit those three grants first.

### 9. Vulnerability management — a process, not a scanner
**The lifecycle:**
1. **Inventory** — you cannot patch what you don't know exists. Assets: hosts, containers/images, packages, libraries, cloud resources, SaaS, and **transitive dependencies** (SBOM). **Shadow IT and forgotten environments are where breaches live.**
2. **Detect** — continuous scanning: images at build and in registries (running images drift from the scanned build), hosts/agents, dependencies (Dependabot/Renovate PRs), IaC, cloud config (CSPM), and **threat intel + CISA KEV** (Known Exploited Vulnerabilities — the single best prioritisation input available).
3. **Prioritise** — the hard part, and where teams fail. Rank by:
   - **Exploited in the wild?** (KEV, EPSS score) — orders of magnitude more important than CVSS.
   - **Reachable?** (Is the vulnerable code path exercised? VEX, reachability analysis, runtime SBOM correlation.)
   - **Exposure** (internet-facing? internal? behind auth?)
   - **Impact** (what does the asset do — does it hold credentials, PII, or control production?)
   - **Compensating controls** (WAF rule, network segmentation, no egress, read-only fs)
   - **CVSS base score** — the *least* useful input alone. **A CVSS 9.8 in an unreachable dev-only dependency is below a CVSS 6.5 in an internet-facing auth service.**
4. **Remediate** — the paved road matters more than the SLA: automated dependency-update PRs with test results and a changelog summary; base-image rebuilds on a schedule (nightly) so fixes flow without code changes; OS patching via immutable images + rolling replacement (not in-place patching); and **a fix path that takes minutes, not a ticket queue**.
5. **Verify** — rescan, confirm the finding is gone, and confirm you didn't break anything (the rollback risk is real).
6. **Report & improve** — MTTR by severity, % internet-facing criticals open, backlog age, exception/risk-acceptance rate with expiry dates, and **slip trends**. Report *outcomes*, not scan counts.

**SLAs that are realistic (and enforceable):** internet-facing exploitable critical → 24–72 hours; internal critical → 7–14 days; high → 30 days; medium → 90 days; low → best-effort/backlog. **And a risk-acceptance process with an owner, a justification, a compensating control, and an expiry date** — otherwise exceptions are permanent.

**The framing:** "Vulnerability management fails on prioritisation and on the fix path, never on detection. Everyone has scanners. The teams that are actually secure have (a) a prioritisation model driven by exploitation and reachability rather than CVSS, and (b) an automated remediation pipeline so that applying a fix is cheaper than filing an exception. If patching takes a sprint, the backlog is inevitable and the SLA is fiction."

### 10. Zero trust architecture — what it means operationally
**The principles (NIST SP 800-207 shape):**
1. All data sources and compute are treated as resources, regardless of location.
2. **All communication is secured regardless of network location** — no implicit trust for "inside the network".
3. Access is granted **per session**, based on identity + device posture + context, not on network position.
4. Access is **dynamic and continuously evaluated** (risk signals can revoke mid-session).
5. **Least privilege** with just-in-time, scoped credentials.
6. The enterprise monitors and measures the integrity and security posture of all owned and associated assets.
7. All authentication and authorisation are dynamic and strictly enforced before access is granted — a **continuous** loop (obtain access → scan/assess → trust → verify → grant/deny).
8. The enterprise collects telemetry (asset state, network, access requests) to improve policy.

**What it looks like in a real platform:**
| Plane | Implementation |
|---|---|
| **Identity** | Central IdP, MFA (phishing-resistant: FIDO2/passkeys), Conditional Access (device compliance, location, risk), short-lived tokens, **no long-lived static credentials anywhere** |
| **Workload identity** | SPIFFE/SPIRE or cloud workload identity; mTLS between services with auto-rotated short-lived certs (cert-manager + SPIRE, or a service mesh) |
| **Network** | Micro-segmentation (NetworkPolicy, security groups per role), **no broad internal RFC1918 trust**, egress default-deny with an allowlisting proxy, private endpoints for cloud services, no management-plane exposure to the internet |
| **Device** | Managed, encrypted, EDR-equipped, posture-checked before access; **unmanaged devices get browser-only, restricted access** |
| **Application** | Authorisation on every request server-side, per-tenant data isolation enforced in code *and* tested, rate limiting, input validation |
| **Data** | Classification, encryption with customer-managed keys, access logging, DLP, **least-privilege data access with just-in-time elevation** |
| **Verification** | Continuous: runtime detection (Falco/Tetragon/EDR), CSPM/KSPM, audit log analysis, anomaly detection, **assume-breach exercises** |

**The honest caveats (which make the answer credible):**
- **Zero trust is an architecture direction, not a product.** Vendors sell "zero trust" as a SKU; the real work is identity hygiene, segmentation, and telemetry.
- **It's incremental.** You cannot big-bang it. The pragmatic order: **kill long-lived credentials → MFA/phishing-resistant auth → workload mTLS → micro-segmentation → device posture → continuous verification.** Each step is independently valuable.
- **It shifts risk to the IdP and the policy engine**, which then become the highest-value assets and the biggest single points of failure. **An IdP compromise is worse than a network perimeter breach** — so the IdP needs the strongest controls you have.
- **Legacy systems will not comply**, so you need explicit, documented, time-bound exceptions with compensating controls (a gateway that authenticates on their behalf).
- **The measurable outcome**: "would an attacker with a foothold on a workstation or inside a pod be able to reach the customer database?" If the answer is yes, your zero-trust work isn't done — and that's a testable question, which is much better than a maturity score.

### 11. Compliance as code — SOC 2, ISO 27001, PCI DSS, HIPAA, GDPR
| Framework | Scope | What it demands of engineering |
|---|---|---|
| **SOC 2** | Trust Services Criteria: Security (mandatory), Availability, Processing Integrity, Confidentiality, Privacy | Access reviews, change management evidence, logging/monitoring, vendor management, incident response, **continuous control monitoring** (Type II = over a period, usually 3–12 months) |
| **ISO 27001** | ISMS: risk assessment, Statement of Applicability, Annex A controls | A documented management system, internal audits, management review; **process-heavy** |
| **PCI DSS 4.0** | Cardholder data environment (CDE) | **Reduce scope** (tokenisation, don't touch PANs), network segmentation, MFA everywhere in the CDE, quarterly ASV scans, annual pentest, key management, logging with 12-month retention (3 months immediately available), **continuous compliance from 2025** |
| **HIPAA** | PHI (US health) | Administrative/physical/technical safeguards, BAAs with vendors, audit controls, encryption, access management |
| **GDPR** | EU personal data | Lawful basis, **data minimisation**, purpose limitation, retention limits, **DSAR/erasure within 30 days**, breach notification **within 72 hours**, DPIAs, cross-border transfer mechanisms, **privacy by design** |
| **DORA / NIS2** | EU financial / essential entities | ICT risk management, **incident reporting with tight deadlines**, resilience testing (incl. threat-led pen testing), third-party/ICT provider risk |

**Compliance-as-code — the practice that scores:**
> "The failure mode of compliance is a binder of policies and a two-week panic before the audit. The fix is to make controls **machine-verifiable and continuously evaluated**: encode each control as a policy (OPA/Conftest on Terraform plans, Kyverno on cluster objects, CSPM rules on cloud config, custom checks on cloud APIs), run it in CI and continuously, and produce the **evidence automatically** — a dashboard showing control status over time is a better audit artifact than a screenshot taken for the auditor. Then the audit becomes a review of a live system rather than a reconstruction. Tools: Cloud Custodian, Prowler, Steampipe, ScoutSuite, Checkov, Kyverno, Vanta/Drata/Secureframe for the workflow layer — but **the durable investment is your own policy-as-code, because a SaaS control that can't see your specifics gives you a false sense of coverage.**"

**The engineering implications people forget:**
- **Logging retention**: 12 months (PCI), 6 years (some regimes), immutable and off-account. Design storage tiers for it.
- **Data residency**: which regions can hold which data — a hard architectural constraint (and it interacts with multi-region DR).
- **Erasure/DSAR**: you must be able to find and delete a person's data **everywhere** — including backups, logs, analytics, and third parties. **Backups and immutable logs make erasure genuinely hard**; you need a documented, defensible approach (e.g. cryptographic erasure: delete the per-user key).
- **Change management evidence**: your GitOps history *is* your change-management record — approvals, diffs, deploy times. **A GitOps platform is a compliance asset**, which is a nice thing to say.
- **Segregation of duties**: the person who writes code shouldn't be the only person who can deploy it to prod; the person with prod access shouldn't be able to disable the audit log. Encode it in RBAC/IAM.
- **Access reviews**: quarterly recertification — automate it (report unused permissions from CloudTrail/Access Analyzer, auto-revoke on inactivity).

### 12. Runtime security and detection engineering
- **eBPF-based observability/enforcement** (Tetragon, Cilium, Tracee, Falco with the modern probe) gives kernel-level visibility without patching applications: process executions, network flows, file access, capability use, syscall patterns. **Low overhead, hard to evade from userspace, and it works on unmodified binaries** — which is why it displaced kernel-module-based agents.
- **Detection rules that actually fire** (Falco examples): a shell spawned inside a production container; a write to `/etc` or a binary in a writable path; an outbound connection to a non-allowlisted destination; `kubectl exec` into a production pod; a pod contacting the cloud metadata service unexpectedly; a new ClusterRoleBinding granting cluster-admin; a container image not from the approved registry starting.
- **Detection engineering discipline**: every rule has a hypothesis, a severity, an owner, a runbook, and a false-positive budget. **Track detection coverage against MITRE ATT&CK** (for Containers/Cloud) and **validate it with adversary emulation** — an untested detection rule is a hope.
- **EDR/XDR for hosts and endpoints**, SIEM/SOAR for correlation and response, and **threat hunting** as a scheduled activity rather than an incident response.
- **Honeytokens**: fake AWS keys in a repo, fake credentials in a config file, a fake database row — **when they're used, you know you're compromised, with near-zero false positives.** Cheap and highly effective; a nice specific thing to mention.

---

## 🔴 Scenario

### 13. "A penetration test found 47 issues. How do you run the remediation?"
**Don't start fixing. Start by triaging — a flat list of 47 is unactionable.**

**Step 1 — Validate.** Reproduce every finding. **Pen tests produce false positives** (a "SQL injection" that's actually a parameterised query returning an error message; an "IDOR" that's an object the tester was authorised to see). Also validate severity: the tester's rating reflects a generic context; yours reflects your architecture and compensating controls. **Disputing a finding with evidence is normal and improves the report** — and doing it before assigning work saves everyone time.

**Step 2 — Classify and rank.** For each validated finding, record:
- **Exploitability in your context**: internet-facing? authenticated-only? requires an insider? chained with something else? **Known-exploited (KEV)?**
- **Impact**: what does the attacker gain — data, credentials, code execution, availability, lateral movement?
- **Attack chain**: **which findings combine?** Three "mediums" that chain into unauthenticated RCE is a critical. **This is the analysis pen-test reports rarely do and the one that changes your priorities most.**
- **Compensating controls already present**: WAF, segmentation, MFA, monitoring/detection, rate limits.
- **Fix cost and risk**: a one-line change vs a six-month architecture project.

**Produce a ranked list**, typically:
| Tier | Definition | SLA |
|---|---|---|
| **P0** | Exploitable now from the internet, or chains to a critical impact, or involves credential/data exposure | Fix immediately (days), with interim mitigation *today* (WAF rule, network block, feature flag off, disable the endpoint) |
| **P1** | Authenticated-user escalation, sensitive data exposure, missing critical control | 2–4 weeks |
| **P2** | Defence-in-depth gaps, hardening recommendations | Next quarter, folded into the roadmap |
| **P3** | Informational / best practice | Backlog; some will be declined with justification |

**Step 3 — Interim mitigations for P0 while the real fix is built.** This is what separates a good response from a slow one: block the path at the edge, disable the vulnerable feature behind a flag, restrict the affected endpoint to internal networks, rotate exposed credentials, add a WAF rule. **You reduce risk in hours while the code fix takes weeks.**

**Step 4 — Assign with owners and dates, in the normal backlog.** Security work that lives in a separate tracker doesn't get done. Each item needs a named engineer, a sprint, and an acceptance criterion. **Treat P0/P1 like production bugs in the same queue with the same visibility.**

**Step 5 — Fix the class, not just the instance.** Every finding is a symptom of a missing guardrail:
| Finding | Instance fix | **Class fix (the one that matters)** |
|---|---|---|
| IDOR on `/api/orders/{id}` | Add an ownership check | A framework-level authorisation middleware + an authorisation test suite + a lint rule for direct object references |
| Missing security headers | Add them to this service | A platform default (ingress/CDN config, or a Helm chart default) applied to every service |
| Public S3 bucket | Fix the bucket | **Block Public Access at the account level**, an SCP/Org Policy deny, CSPM alerting, and a Terraform module that can't produce a public bucket |
| Hardcoded secret | Rotate + remove | Secrets scanning in pre-commit **and** CI, a secrets manager + External Secrets as the paved road, workload identity to eliminate keys |
| Outdated dependency with a CVE | Bump it | Automated dependency PRs, base-image rebuild cadence, and a policy gate on new exploitable criticals |
| Privileged container | Remove `privileged` | PSA `restricted` + a Kyverno policy rejecting it cluster-wide |
| SQL injection | Parameterise the query | An ORM/query-builder standard, a SAST rule that fails the build, and secure-coding training with *this* example |
**Say this explicitly:** "A pen test gives you 47 findings; the durable outcome is 10 guardrails that make those 47 classes of issue impossible. If I only fix the instances, next year's test finds 47 new ones."

**Step 6 — Verify and re-test.** Re-run the specific tests, ideally by the same tester (a **retest** is usually a scoped, cheaper engagement). Automated regression checks for the class fixes go into CI.

**Step 7 — Report and learn.** A written response to the report (accepted/fixed/risk-accepted with justification and owner) — most clients and auditors require it. Then a retro: why did these exist? Was it a knowledge gap, a missing guardrail, a deadline trade-off, or an unreviewed architecture? **Feed the answer into the platform roadmap and the SDLC**, and consider whether threat modelling would have caught the design-level findings (insecure design findings almost always would have been).

**Step 8 — Risk acceptance for what you won't fix.** Some findings are legitimate business trade-offs. Record: the risk, the justification, the compensating controls, the **owner**, and an **expiry/review date**. Unsigned, undated risk acceptances are how "we'll fix it later" becomes permanent.

### 14. "You suspect an active compromise of your Kubernetes cluster. Respond."
**Principle: contain first, preserve evidence, don't tip off the attacker, and assume they have more access than you can see.**

**Phase 1 — Confirm and scope (minutes, quietly)**
1. **Don't immediately kill everything.** A panicked `kubectl delete` destroys evidence and may trigger the attacker's persistence mechanism. **Confirm first.**
2. **Gather signals**: what tipped you off (a Falco alert, an anomalous API call, a crypto-mining CPU spike, an unexpected pod, a GuardDuty finding, an external report)? Collect the raw evidence: pod specs, SA tokens, RBAC bindings, audit logs, node processes, network flows, image digests, and the timeline.
3. **Determine the entry point and current scope.** Typical Kubernetes intrusion paths:
   - A **publicly exposed dashboard/apiserver/kubelet port** (10250 unauthenticated is a classic) or an exposed service with an RCE.
   - A **compromised CI pipeline** deploying a malicious image.
   - A **vulnerable application** → container escape or SA token theft.
   - A **leaked kubeconfig / SA token / cloud credential** (the most common: someone's laptop or a Git repo).
   - A **malicious or vulnerable Helm chart / operator** from a public registry.
   - A **supply-chain image** (compromised base image or dependency).
4. **Ask the scope questions:** which namespaces/nodes? Which identities? Does the attacker have cloud credentials (via IRSA/instance profile) — **because a Kubernetes compromise is usually a cloud-account compromise within minutes**? Is data leaving (egress flows, DNS queries to unusual domains)? Is there persistence (new RBAC bindings, new SA tokens, a webhook, a DaemonSet, a CronJob, a mutating admission controller)?

**Phase 2 — Contain (fast, reversible, evidence-preserving)**
5. **Cut the attacker's access, not the service:**
   - **Revoke credentials**: rotate/delete the compromised SA tokens (deleting the Secret or forcing token reissue), rotate cloud credentials the workloads could assume, revoke STS sessions (`aws:TokenIssueTime` deny), rotate kubeconfigs, and **invalidate the IdP sessions of any human accounts involved**.
   - **Network isolation**: apply a **deny-all NetworkPolicy** to the affected namespace (allowing only DNS and what's essential), block the attacker's IPs/domains at the egress proxy/firewall, and **block egress to the cloud metadata endpoint** if not already blocked.
   - **Freeze change**: pause CI/CD deployments and GitOps auto-sync to the affected clusters (so the attacker can't ride your pipeline back in, and so your changes are deliberate). Lock the image registry.
   - **Quarantine, don't destroy**: `kubectl cordon` the affected nodes (stop new scheduling), scale the malicious workload to zero *after* capturing its spec and image, and **keep one replica running in an isolated network segment for forensics** if it's safe to do so.
6. **Protect the data**: verify audit logging is still intact and shipping off-box (attackers disable logging early), snapshot the etcd/state for forensics, and preserve container images and logs. **Ship evidence to a location the attacker can't reach.**
7. **Escalate**: invoke the security incident process, notify the CISO/legal per policy, and **decide on external notification obligations early** (regulator deadlines like GDPR's 72 hours start when you become aware, not when you're certain).

**Phase 3 — Eradicate**
8. **Find and remove persistence**, in this order (the places attackers actually hide):
   - **RBAC**: new/modified ClusterRoleBindings, RoleBindings, ClusterRoles with `*` verbs, grants on `pods/exec` or `secrets`.
   - **Workloads**: unexpected Deployments/DaemonSets/CronJobs/Jobs (especially in `kube-system`), a workload running a public image with a shell, or a container mounting `hostPath: /`.
   - **Admission webhooks**: a mutating webhook the attacker installed is a superb persistence mechanism (it can modify every object created). **Check `MutatingWebhookConfiguration` / `ValidatingWebhookConfiguration`.**
   - **Nodes**: SSH keys in `authorized_keys`, new systemd units, cron jobs, kernel modules, modified kubelet config, a rogue container runtime shim.
   - **Images/registries**: a mutated tag (deployed digest vs expected digest — **this is why you deploy by digest**), an attacker-pushed image.
   - **Cloud layer**: new IAM users/roles/keys, new instances (mining), snapshot sharing, disabled CloudTrail/audit logs, new federation.
   - **GitOps repos**: a malicious commit in the config repo (check the history and the CODEOWNERS bypasses).
9. **Rebuild rather than clean.** **Do not try to clean a compromised node or cluster.** Nodes are cattle: drain, terminate, and rebuild from a known-good image. For the cluster: if the control plane or etcd is suspect, **rebuild the cluster from GitOps and restore workloads** — this is exactly the DR muscle you should already have. Cleaning in place leaves you uncertain, and uncertainty is worse than the rebuild cost.
10. **Rotate everything the attacker could have read**: all secrets in the affected namespaces, TLS certificates, signing keys, database passwords, API tokens, and any credential reachable from the compromised identities. **Assume read access = compromise.**

**Phase 4 — Recover and verify**
11. Restore services progressively, verifying integrity at each step (image digests match, configs match Git, RBAC matches policy, no unexpected workloads).
12. **Re-enable GitOps and CI/CD only after the pipeline and repo are verified clean** — otherwise you reintroduce the attacker.
13. **Heightened monitoring** for 2–4 weeks: the same TTPs often return. Watch for the specific IOCs you found.
14. **Confirm no data exfiltration** as best you can (egress volume analysis, DNS logs, cloud data-event logs) — and be honest about the limits of that determination.

**Phase 5 — Learn**
15. **Blameless post-incident review**: entry point, dwell time, detection gap (why didn't we see it sooner?), containment speed, what made it worse, and the systemic fixes.
16. **The systemic fixes are almost always the same list**: no static credentials (workload identity everywhere), `automountServiceAccountToken: false` by default, PSA `restricted`, admission policies enforcing signed images from approved registries, no privileged/hostPath/hostNetwork, user namespaces, default-deny NetworkPolicy with egress control, metadata endpoint blocked, runtime detection (Falco/Tetragon) with tested rules, audit logs shipped off-box and immutable, private apiserver endpoints, **and a tested cluster-rebuild-from-Git procedure**.
17. **Test the recovery path** — a game day for "compromised cluster" is the highest-value resilience exercise a platform team can run.

**The framing:** "The instinct is to delete the malicious pod. That's usually wrong twice: it destroys evidence and it doesn't touch the persistence or the credential the attacker still holds. The correct sequence is confirm → revoke credentials and isolate at the network layer → find persistence → rebuild rather than clean → rotate everything reachable → verify → rehearse it next quarter. And the single most important pre-condition is that you can rebuild a cluster from Git in an hour, because if you can't, eradication becomes an archaeological project with the attacker still inside."

### 15. "Design the security for a new multi-tenant SaaS platform."
**Threat model first:** the adversary set includes **malicious tenants** (the hardest — authenticated, authorised, and motivated), compromised dependencies, insiders, and internet-scale opportunists. **The dominant risk in multi-tenant SaaS is tenant isolation failure**, so that's what I'd design around.

**Layer 1 — Identity and authentication**
- Central IdP (or federate the tenant's own — enterprise customers demand SAML/OIDC SSO and SCIM provisioning).
- **Phishing-resistant MFA** (FIDO2/passkeys) for admins; enforce for tenant admins at minimum.
- **Short-lived tokens (JWT/OIDC) with `aud`, `iss`, `exp` strictly validated** — and **never accept `alg: none` or an unverified signature**; validate the JWKS and pin the issuer.
- **RBAC within the tenant** (owner/admin/member/viewer/billing) — authorisation is *two-dimensional*: "which tenant" and "which role in it". **Most multi-tenant bugs are the first dimension being checked in one place and not another.**

**Layer 2 — Tenant isolation (the core design decision)**
Choose per layer and state the trade-offs:
| Layer | Shared (pooled) | Siloed (per-tenant) | Hybrid |
|---|---|---|---|
| Compute | One service, tenant ID in the request context | One deployment per tenant | Pooled for small, dedicated for enterprise |
| Database | **Shared schema + `tenant_id` column** (cheap, dense, **riskiest: one missing WHERE clause leaks data**) | **Schema-per-tenant** (good isolation, migration complexity at scale) | **Database-per-tenant** (strongest, costliest, best for enterprise/compliance) |
| Storage | Shared bucket + tenant prefix (**risky: a presigned-URL bug leaks across tenants**) | Bucket per tenant | Prefix + strict policy + server-side enforcement |
| Kubernetes | Namespace per tenant + NetworkPolicy + RBAC | Node pool per tenant + RuntimeClass (gVisor) | Namespaces for soft, dedicated pools for hostile/enterprise |
| Secrets/keys | Shared KMS key | **Per-tenant KMS key** (enables cryptographic erasure and per-tenant audit) | |
**My position:** "Pooled by default for cost and operability, **siloed where the risk or the customer demands it** — dedicated database or node pool for enterprise/regulated tenants. And critically: **isolation must be enforced in one place, not sprinkled across every query.** Concretely: the tenant ID comes from the authenticated token (never from a request parameter), is injected into a request context, and the data layer **enforces it automatically** — Postgres **row-level security** with `SET app.tenant_id`, or an ORM/data-access layer that makes omitting the tenant filter impossible. If correctness depends on every developer remembering a `WHERE tenant_id = ?`, it will fail; **make the insecure query unrepresentable.**"

**Layer 3 — Authorisation**
- **Deny by default**; explicit permission checks per operation, per resource, per tenant.
- **Object-level authorisation** (IDOR prevention): every access to a resource verifies both tenant membership and the actor's role. **Automate the check in the data layer, and test it with a suite that attempts cross-tenant access for every endpoint** — this is the highest-value test suite in a SaaS platform.
- **Function-level authorisation**: admin endpoints checked server-side, not hidden in the UI.
- **Attribute/relationship-based authz** (or an engine like OPA/Cerbos/OpenFGA) once the model outgrows simple RBAC.

**Layer 4 — Data protection**
- **Classification** (public/internal/confidential/restricted) driving handling rules.
- Encryption in transit (TLS 1.2+/1.3, mTLS between services) and at rest (**per-tenant keys** where feasible → enables crypto-shredding for GDPR erasure and per-tenant key-use audit).
- **Tokenisation** for payment data to keep PCI scope minimal (never touch PANs; use a PSP's hosted fields or Elements).
- **Field-level encryption** for the most sensitive fields, with keys in a KMS/HSM.
- **Data minimisation and retention**: don't collect what you don't need; delete on a schedule; make erasure achievable including in backups (crypto-erase).
- **DLP + secrets scanning** on egress paths and repos.

**Layer 5 — Application security**
- Input validation/output encoding by framework default; parameterised queries everywhere; no dynamic template/expression evaluation on user input.
- **Rate limiting per tenant** (protects against one tenant DoSing the platform — a real multi-tenant availability issue) plus global limits; **abuse-case handling** (unlimited-resource endpoints, enumeration, scraping).
- **Idempotency keys** on mutations; CSRF protection for browser sessions; CORS allowlist (not `*` with credentials); security headers (CSP, HSTS, X-Content-Type-Options, Referrer-Policy, Permissions-Policy); **CSP as a real XSS mitigation, not a formality**.
- File uploads: type/size validation, **stored outside the web root with non-executable permissions, served from a separate domain**, virus-scanned, and never trusted for content type.
- Dependency and secret hygiene, SAST in CI, and **annual third-party pen test with a retest**.

**Layer 6 — Infrastructure and platform**
- Kubernetes hardened as in Q8 (PSA `restricted`, no privileged, user namespaces, default-deny NetworkPolicy, signed images verified at admission, no SA token automount by default, RBAC least privilege, audit logging).
- **Workload identity per service** (IRSA/Pod Identity), no static cloud keys; SCPs/Org Policy denying destructive and public-exposure actions.
- **Egress control with an allowlisting proxy** — blocks exfiltration *and* SSRF-to-metadata paths.
- **Private endpoints** for all cloud PaaS; no public management planes.
- Immutable infrastructure, GitOps for everything, environments separated by account/subscription/project.

**Layer 7 — Detection, audit and response**
- **Audit log per tenant** (who did what, when, from where) — **a product feature customers demand, not just a control**. Immutable, retained, queryable by tenant admins.
- Platform audit: K8s audit logs, cloud API logs (CloudTrail/Activity Log/Audit Logs), VPC flow logs, DB audit — all shipped to a **separate, immutable log account**.
- Runtime detection (Falco/Tetragon/EDR), anomaly detection on auth (impossible travel, credential stuffing, privilege escalation attempts), CSPM/KSPM continuously.
- **Tenant-level anomaly detection**: one tenant suddenly reading 100× more objects is often the isolation failure in progress.
- **Incident response runbooks including a "tenant data exposure" playbook** — with a decision tree for customer notification and regulator notification. **Practise it.**

**Layer 8 — Governance and assurance**
- Threat modelling per major feature (with tenant-isolation abuse cases as a standing item).
- **Compliance from day one**: SOC 2 Type II as an early target (it's a sales blocker), GDPR/CCPA processes (DSAR, erasure, DPA), and compliance-as-code for continuous evidence.
- **Security champions** in each product team, a security review gate for high-risk changes, and a documented risk-acceptance process.
- **Vendor/third-party risk management** — your subprocessors are your attack surface, and customers will ask.
- **Bug bounty / VDP** once the basics are solid.
- **Metrics**: MTTD, MTTR, % internet-facing criticals open past SLA, isolation-test suite pass rate, audit-log coverage, exception count with expiry.

**The closing statement:** "For multi-tenant SaaS I'd spend 60% of the security design effort on **tenant isolation**, because it's the failure mode that ends the company: an enforcement point in the data layer that makes cross-tenant queries structurally impossible, an automated cross-tenant access test suite that runs on every endpoint in CI, per-tenant keys and audit logs, and tiered siloing for the customers who need it. Everything else in the list is table stakes that any competent platform has; isolation is what a SaaS-specific design has to get right."

---

## Red flags

| Saying / doing this | Costs you |
|---|---|
| "We run Trivy in CI so we're secure" | Detection ≠ management; no prioritisation or fix path |
| Ranking vulnerabilities by CVSS alone | Ignores exploitation, reachability, exposure and context |
| 4,000-CVE report handed to a team with no triage | Guarantees it gets ignored |
| Threat modelling as a one-off document | Never re-read; not versioned with the architecture |
| Authorisation checked only in the UI | Broken access control, OWASP #1 |
| Tenant ID taken from a request parameter instead of the token | Cross-tenant data exposure |
| Isolation via "remember to add WHERE tenant_id" | Will fail; enforce it in the data layer |
| Long-lived static credentials anywhere | The universal breach vector |
| No purge protection / deletion waiting period on KMS keys | Irreversible data destruction |
| `privileged: true` or `hostPath: /` for convenience | Node → cluster compromise |
| Not blocking egress to the cloud metadata endpoint | SSRF → credential theft |
| Deploying by mutable tag | Can't prove what's running; enables image mutation attacks |
| Signing images but not verifying at admission | Signing theatre |
| No admission enforcement (only CI checks) | CI can be bypassed; the cluster can't |
| Deleting the malicious pod as the first response | Evidence gone, persistence and credentials untouched |
| "Cleaning" a compromised node instead of rebuilding | Uncertainty; the attacker may remain |
| Risk acceptances with no owner or expiry date | Permanent exceptions |
| Fixing pen-test instances but not the classes | 47 new findings next year |
| Zero trust as a product purchase | It's an architecture direction, incremental |
| Compliance evidence assembled two weeks before the audit | A reconstruction, not a control environment |
| Logs retained forever by default, or 7 days on audit logs | Cost blowout, or a compliance failure |
| No cross-tenant access test suite | The SaaS-specific control you're missing |

## Rapid recall

1. DevSecOps = security embedded at design/code/build/deploy/run, with **fast feedback, actionable findings, and platform-owned guardrails**. "Enable, don't gate."
2. **STRIDE**: Spoofing, Tampering, Repudiation, Information disclosure, DoS, Elevation of privilege — applied to each element and each **trust-boundary crossing** in a data-flow diagram. Add abuse cases and attack trees.
3. **OWASP Top 10 (2021)**: Broken Access Control (#1), Cryptographic Failures, Injection, **Insecure Design**, Security Misconfiguration, Vulnerable Components, Auth Failures, **Software & Data Integrity (supply chain)**, Logging/Monitoring Failures, **SSRF**.
4. CIA + AAA + non-repudiation; **defence in depth**; **least privilege**; **zero trust** = verify every request, no implicit network trust, short-lived scoped credentials, continuous evaluation; **assume breach**.
5. TLS 1.2+/1.3, AEAD ciphers, **ECDHE for forward secrecy** (never static RSA), **mTLS** for service-to-service, automate cert lifecycle and **monitor expiry including internal certs**.
6. **Envelope encryption**: data key encrypts data, KMS/HSM KEK encrypts the data key → HSM-grade root protection without HSM throughput limits. Rotate keys, scope them per tenant/env, log their use, protect them from deletion.
7. Secrets ladder: hardcoded → env → K8s Secret → cloud secret manager → **External Secrets/SOPS/Sealed** → **dynamic short-lived (Vault, workload identity)** → **no secret at all**. Rotate automatically; scan continuously; **rotate first, investigate second, delete third**.
8. Supply chain: pinned/hashed deps, private registry mirror, **hermetic ephemeral builds with OIDC (no ambient creds)**, reproducible builds, **provenance (SLSA L2–L3)**, **signed artifacts (cosign keyless)**, **SBOM (SPDX/CycloneDX)**, **verification at admission (Kyverno/policy-controller/Binary Authorization)**, immutable digests. **VEX turns 4,000 CVEs into 3 tasks.**
9. Kubernetes: managed control plane + current version (3-release window), private apiserver, etcd encryption, audit logs off-box, OIDC humans, projected SA tokens, **`automountServiceAccountToken: false`**, RBAC least privilege (`resourceNames`), **PSA `restricted`**, non-root/read-only/drop-ALL/seccomp/**user namespaces**, default-deny NetworkPolicy with metadata-endpoint egress block, **signed-image admission**, runtime detection (Falco/Tetragon). **`pods/exec`, `secrets` get/list, and `ClusterRoleBinding create` ≈ cluster-admin.**
10. Vulnerability management = inventory → detect → **prioritise (KEV/EPSS, reachability, exposure, impact, compensating controls — CVSS last)** → remediate (automated PRs, nightly base rebuilds, immutable-image patching) → verify → report **MTTR and backlog age**, not scan counts. Risk acceptances need owner + justification + expiry.
11. Zero trust order of work: **kill static creds → phishing-resistant MFA → workload mTLS → micro-segmentation → device posture → continuous verification**. The IdP becomes your crown jewel. Test it with: "could an attacker inside a pod reach the customer DB?"
12. Compliance as code: encode each control as a machine-verifiable policy (Conftest/Kyverno/CSPM), run continuously, **generate evidence automatically**. Remember retention, residency, **erasure including backups (crypto-shredding)**, segregation of duties, and that **GitOps history is your change-management record**.
13. Runtime: eBPF detection (process/file/network/capability anomalies), detection rules with owner+runbook+FP budget, coverage mapped to **ATT&CK for Containers/Cloud** and validated by emulation, **honeytokens** for near-zero-FP compromise detection.
14. Pen-test remediation: **validate → rank by exploitability/impact/attack chains → interim mitigation today → fix in the normal backlog with owners → fix the class with a guardrail → retest → report → risk-accept with expiry**.
15. Cluster compromise: **confirm quietly → revoke credentials + isolate network + freeze CI/GitOps → find persistence (RBAC, workloads, *webhooks*, nodes, images, cloud, repo) → rebuild don't clean → rotate everything reachable → verify → heightened monitoring → blameless review → rehearse the rebuild**.
16. Multi-tenant SaaS: **60% of the effort on tenant isolation** — tenant ID from the token, enforcement in the data layer (Postgres RLS / a data-access layer that can't omit it), **automated cross-tenant access tests on every endpoint**, per-tenant keys, per-tenant audit logs, tiered siloing for enterprise, per-tenant rate limits.

→ Next: [`15-Platform-Engineering`](../15-Platform-Engineering/README.md)
