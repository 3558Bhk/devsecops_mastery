# 13 — Docker, K8s & CI/CD (🟢 4 · 🟡 6 · 🔴 6)

> Course ref: [13-docker-k8s-cicd.md](../ansible-mastery/13-docker-k8s-cicd.md)

## 🟢 Basic

**Q1. Which collections provide Docker and Kubernetes support?**
> A: `community.docker` (docker_image, docker_container, docker_compose_v2, docker_login) and `kubernetes.core` (k8s, helm, k8s_info…).

**Q2. What does `docker_compose_v2` do that `docker_container` doesn't?**
> A: Manages a whole compose project/stack lifecycle (multi-service, `project_src`, build/pull policies) vs per-container desired state. Single services → container module; multi-service stacks → compose; orchestrated fleets → K8s.

**Q3. What is the k8s module's core idea?**
> A: `kubernetes.core.k8s` applies desired-state manifests (inline `definition:` or `src:`) to a cluster — same declarative diff idea as Ansible, against the K8s API.

**Q4. Where does Ansible sit in a CI/CD pipeline?**
> A: As the deploy/infrastructure stage: lint + `--check --diff` gates, then apply to staging → approval → prod. CI provides identity/secrets; Ansible does the mutation; AAP can replace CI as the executor with RBAC/approvals.

## 🟡 Intermediate

**Q5. How do you gate a K8s deploy on actual readiness?**
> A: `k8s_info` loop: `until: resources[0].status.readyReplicas == spec.replicas` with retries — deployment "accepted" ≠ pods ready; the gate is what makes the pipeline meaningful.

**Q6. Ansible vs GitOps (Argo/Flux) for K8s — the positioning answer.**
> A: GitOps for K8s-native continuous reconciliation (drift self-heal, desired state in git); Ansible for cluster bootstrap before GitOps exists, platform add-ons with vault lookups, migrations/runbooks, and pipeline gates. Around the cluster, not a rival inside it.

**Q7. How do you keep runner→fleet credentials safe in CI?**
> A: Per-env deploy keys/scoped identities injected by the CI secret store as ephemeral files (600); pinned `known_hosts` (`ssh-keyscan` at setup); vault passwords per env; OIDC federation for cloud APIs — the runner holds nothing long-lived.

**Q8. What's an Execution Environment and why does it fix "works on the control node"?**
> A: OCI image bundling ansible-core + collections + Python/system deps (built with `ansible-builder`), run via `ansible-navigator`/AAP — the control node becomes a versioned, scanned, promotable artifact instead of a snowflake.

**Q9. `docker_container` recreate semantics — what's the trap?**
> A: Module diffs the spec, not the registry: a re-pushed `:latest` tag doesn't recreate anything unless you force `recreate: true`/pull. Pin digests/versions, and treat unconditional `recreate` as restart-noise.

**Q10. Show the pipeline stages you'd standardize for an Ansible repo.**
> A: yamllint + ansible-lint + `--syntax-check` → `--check --diff` artifact against staging → apply staging → manual approval → apply prod (environment-scoped secrets) → post-deploy verify + notifications. Artifacts kept for audit.

## 🔴 Advanced

**Q11. Your pipeline deploys "successfully" but users see the old version. Debug.**
> A: Chain: artifact actually new? (checksum) → container/K8s rollout completed? (readyReplicas gate) → service endpoints refreshed? → LB still pointing at old pool/color? → CDN/browser cache? Each hop gets a verification task — a pipeline without post-cutover user-visible checks isn't verifying a deploy.

**Q12. Where does container-internal configuration belong — Ansible or image? Defend.**
> A: In the image/Dockerfile (or K8s config) — containers are immutable artifacts; Ansible shouldn't exec into running containers to mutate them (non-reproducible). Ansible manages the *host* (daemon, kernels, registries) and the *delivery* (build/ship/run), not the container's insides.

**Q13. Design multi-env pipeline credentials so prod secrets never touch staging jobs.**
> A: Environment-scoped secret sets (GitHub Environments/GitLab protected variables) with per-env vault passwords, deploy keys, and cloud roles; prod environment requires manual approval + restricted to protected branches; runners get OIDC-scoped short-lived cloud creds; audit = pipeline logs + vault/provider audit logs.

**Q14. Helm via Ansible — when does `kubernetes.core.helm` beat plain manifests, and what's the risk?**
> A: Beats plain manifests for third-party charts (values-driven installs, upgrades, rollbacks) and org-standard chart reuse. Risk: two templating layers (Helm + Ansible vars) — keep values in Ansible vars only at the boundary, pin chart versions, and let GitOps own continuous state if present.

**Q15. How do you handle idempotency reporting in a pipeline where every run shows changed=15?**
> A: Diff two runs (`--diff` artifacts), classify: nondeterministic templates (timestamps/random), shell-without-creates, `latest` package drift, or genuinely new inputs. Fix sources of nondeterminism — perma-changed pipelines destroy signal and mask real regressions.

**Q16. When would you choose AAP over CI (Jenkins/GitHub) as the executor — and when both?**
> A: AAP when operations (not just deployments) need self-service: standing RBAC, inventories, schedules, approvals, audit, human-triggered runs. Both: CI for change-driven deploys, AAP for operational automation; pipelines call AAP's API so fleet credentials never live in CI at all.
