# RTIQ — Microsoft Entra ID (Azure Active Directory) (Real-Time Interview Questions)

> **Cloud:** Azure · **Domain:** Entra ID (identity, auth, app registration, conditional access, PIM) · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~10 min

**How this file is used live:** identity is the new perimeter, so senior/DevSecOps rounds dig here. Expect "how does a workload get an Azure token without a secret", "walk me through an SSO failure", "how do you stop credential theft", and "how do you deprovision a leaver in under an hour".

**Legend:** ⚡ Rapid · 🔍 Deep dive + follow-ups · 🚨 War room · ⚖️ Trade-off debate · 🎯 Senior signal

---

**⚡ Rapid**
1. **Q:** What is Entra ID, one line, and what is it *not*?
**A.** A cloud identity provider (users, groups, apps, service principals, tokens, conditional access) — it is not a directory-services replacement for on-prem AD DS (no Group Policy, LDAP, Kerberos for domain-joined machines). Hybrid setups run both, synced via Entra Connect/Cloud Sync.
2. **Q:** User vs group vs service principal vs managed identity?
**A.** Users authenticate interactively; groups bundle users for access/PIM; service principals are the identity object representing an app in a tenant; managed identities are Azure-managed service principals with no credentials to handle. Apps should use managed identities; cross-cloud/on-prem apps use service principals with certificates or federated credentials.
3. **Q:** What is an app registration vs an enterprise application?
**A.** App registration = the application *definition* in your tenant (redirect URIs, API permissions, credentials, token config). Enterprise application = the service principal instance of an app in your tenant (used for assignment, SSO, provisioning). Registering in one tenant and consuming in many creates one registration + many service principals.
4. **Q:** What are the token types?
**A.** ID token (who the user is, for the client), access token (what the API can call, with scopes/roles claims), refresh token (get new tokens silently). App-only flows use client credentials (no user).
5. **Q:** Which OAuth flows do you use for which app?
**A.** Authorization Code + PKCE for web/mobile/SPA (never implicit), client credentials for daemons/services, device code for input-limited devices/CLI, on-behalf-of for API-to-API on behalf of a user. Implicit flow and ROPC are legacy/discouraged.
6. **Q:** What is Conditional Access?
**A.** Policy engine on sign-ins: conditions (user/group, app, device state/compliance, location, risk, client app) → controls (block, require MFA, require compliant device, require compliant app, session controls). "If/then" for identity.
7. **Q:** What is PIM?
**A.** Privileged Identity Management — make privileged roles *eligible* (not permanent), require activation with justification, MFA, approval, time limit, and alerting; includes access reviews. The single biggest win in Azure security hardening.
8. **Q:** What is Privileged Access / break-glass account practice?
**A.** Two or more cloud-only Global Admin accounts excluded from all Conditional Access (or with a distinct policy), with FIDO2 keys stored in a safe, monitored sign-ins with alerts, and no mailbox/daily use. Document and test them — being locked out of your tenant is total loss of control.
9. **Q:** What's the difference between delegated and application permissions?
**A.** Delegated = the app acts *as the signed-in user* (needs consent, limited to the user's rights). Application = the app acts *as itself* with its own rights (broader, admin consent required, must be scoped tightly). Most privilege escalations come from over-granted application permissions.
10. **Q:** How do you assign Azure resource access to users?
**A.** Entra groups → Azure RBAC role assignments (never per-user where avoidable), scoped to management groups/subscriptions/resource groups, with PIM for elevated roles. The group is the unit of lifecycle: remove from group = loss of access.

**🔍 Deep dive**
11. **Q:** How does a CI/CD pipeline authenticate to Azure without secrets?
**A.** Workload identity federation: a federated credential on an app registration (or user-assigned managed identity) trusted by GitHub Actions/GitLab/Kubernetes, with the subject claim pinned to a repo/environment/branch. The pipeline gets a short-lived token — no PATs, no client secrets, no key rotation tickets.
12. **Q:** Design access and identity for a 200-developer org using Azure.
**A.** Entra ID with Cloud Sync from on-prem AD only if needed, security groups per team/environment as the access unit, RBAC assignments on resource groups (Contributor for the team's RG, Reader org-wide, PIM for prod elevation), a platform team with PIM-activated Subscription Owner, workload identity federation for all pipelines, Conditional Access (MFA + compliant device for prod, block legacy auth, block risky sign-ins), no standing service principal secrets, and access reviews quarterly.
13. **Q:** Walk me through SSO debugging for a SaaS app (SAML or OIDC).
**A.** Which side fails? Check the Entra sign-in log (error code: `AADSTS*`) and the app's SAML/OIDC trace. Common causes: audience/identifier URI mismatch, reply URL (redirect URI) mismatch, certificate expiry/rollover (SAML), clock skew, claims missing/incorrect (group claims too large — 200 group limit requires app role assignment), Conditional Access blocking, or the user not assigned to the enterprise app. Then reproduce with a test user and the same client.
14. **Q:** How do you stop credential theft/phishing with identity controls?
**A.** Phishing-resistant MFA (FIDO2/passkeys/CBA), Conditional Access requiring compliant devices and blocking legacy protocols, Identity Protection risk-based policies (user risk/sign-in risk), passwordless rollout, disable basic auth tenants-wide, monitor `AADSTS50126`/password-spray patterns and risky sign-ins, and eliminate service account passwords via federation. Also monitor for OAuth consent-phishing (illicit consent grants).
15. **Q:** Someone got Global Admin for 30 minutes. What do you do?
**A.** Contain (revoke sessions/refresh tokens, reset credentials, disable the account), then investigate: audit logs for role activations, all actions in the window (which resources/apps, new app registrations, new credentials added to service principals — attackers love adding credentials to existing apps), any consent grants or federation config changes (a backdoor path). Then rotate anything the account could reach and add alerts on new credentials/federated identity changes.
16. **Q:** How does identity work in multi-tenant (B2B/B2C) scenarios?
**A.** B2B: external guest users in your tenant (to be replaced by cross-tenant access settings), governed by entitlement management/access reviews, least privilege, and Conditional Access for guests. B2C: a separate tenant for customer identities with custom user flows/policies, social IdPs, and its own scale/telemetry. Don't mix workforce and customer identity in one tenant.
17. **Q:** How do you manage secrets and certificates for app registrations?
**A.** Prefer federated credentials (no secrets), then certificates with short lifetimes and rotation automation (Key Vault + rotation runbook), and only then client secrets — with expiry monitoring and alerting on new credentials being added. Track and alert on credential additions: it's both hygiene and attack detection.
18. **Q:** How do you implement least privilege for an Azure platform team?
**A.** A custom/PIM-eligible role set rather than Owner: e.g. Subscription Contributor only on platform subscriptions, Resource Policy Contributor, Network Contributor scoped to the hub, Key Vault admin via PIM with approval, plus break-glass Owner. Use access reviews to prove it and Azure Activity logs to detect out-of-policy actions.

**🚨 War room**
19. **Q:** A developer's account is compromised and used to add a credential to a service principal. Walk through the response.
**A.** Revoke the user's sessions and disable the account; enumerate the app's credentials and remove the attacker's (record its ID first for forensics); audit what the service principal did while the attacker had it (Activity Logs/audit logs, resource changes, data access); rotate every secret that principal could read; check for other persistence (new app registrations, federated credentials, consent grants, role assignments); then force MFA/password reset org-wide if the compromise vector is broad.
20. **Q:** Nobody can log in after a Conditional Access change. First 5 minutes?
**A.** A Global Admin can be excluded/blocked — use the break-glass account (excluded from CA policies) to get in, then review the CA policy change, put it back to report-only, validate with the "What If" tool for a real user, and free it up for a group first. Change control on CA policies is where this class of incident comes from.
21. **Q:** Rate-limiting/lockout: a service account keeps getting locked, breaking an integration at 3 a.m.
**A.** Find the offending client (sign-in logs filtered by the account, look at IP/app), which is usually a legacy service still configured with the old password, or a cached credential retry loop. Fix the credential, migrate the integration to federated/managed identity so it can't lock, and alert on the account's failed sign-ins rather than discovering it from an outage.
22. **Q:** PIM activation works for users but the audit trail is missing justification for some. Fix.
**A.** PIM requires justification at the role-setting level (enforce on activation), plus approval for high-privilege roles and a note on what it's for; set maximum duration (e.g. 4 hours) with mandatory re-approval, and alert on activations of sensitive roles to a security channel. Verify by exporting the PIM audit log and checking for null justifications — then enforce.
23. **Q:** Your tenant is being password-sprayed from a botnet.
**A.** Confirm with sign-in logs/Identity Protection risk detections, then: block at the perimeter (CA location/risk policies, or a Named Location allow-list for corporate/admin access), enforce phishing-resistant MFA, disable legacy auth, and consider password-spray-specific protections (smart lockout thresholds, banned-password lists, no lockout-based enumeration). Report/measure — and don't just add a rule; verify your legitimate users can still get in.

**⚖️ Trade-off**
24. **Q:** Conditional Access: block-by-default vs allow-by-default?
**A.** Allow-by-default with targeted blocks is less disruptive but leaky; block-by-default with exceptions is stronger but demands mature device/identity hygiene and a break-glass plan. Most orgs get there in stages — the destination is "only compliant devices, phishing-resistant MFA for admins, no legacy auth".
25. **Q:** Managed identity vs service principal with a certificate vs federated credential?
**A.** Managed identity for Azure-hosted workloads (best, no credentials). Federated credentials for external clouds/CI (no secrets, scoped by subject claim). Service principal with certificate only where neither is possible, with rotation automation. Client secrets are the fallback you should be eliminating.
26. **Q:** Single tenant per organisation vs multiple tenants (business units/regions)?
**A.** One tenant simplifies governance, licensing, and cross-resource access; multiple tenants serve legal/regulatory separation (data residency, M&A). Multi-tenant Azure is significantly more expensive to run (cross-tenant Azure Lighthouse, duplicated policies, harder identity lifecycle) — justify it.
27. **Q:** Should developers get Contributor on production resource groups?
**A.** No — read-only plus PIM-elevated, ticket/approval-tracked access, and pipelines as the normal change path. Contributor on prod is effectively a standing production access grant, which is exactly what auditors will flag.
28. **Q:** Hybrid identity: Password Hash Sync vs Pass-through Authentication vs Federation?
**A.** PHS (simplest, resilient, enables leaked-credential detection via Entra ID Protection) is the modern default; PTA avoids password hashes in the cloud but needs on-prem agents and has more moving parts; ADFS federation gives control but is a legacy, high-maintenance pattern — Microsoft's own guidance is to migrate off ADFS. Say PHS + seamless SSO unless there's a specific driver.

**🎯 Senior**
29. **Q:** How would you design identity for a regulated workload with least privilege and full auditability?
**A.** Workloads use managed identities/federated credentials (no secrets anywhere), human access is group-based with PIM-eligible roles and approval for privileged tiers, Conditional Access requires phishing-resistant MFA + compliant device + no legacy auth, break-glass accounts are documented and tested, all sign-ins/audits flow to a central immutable workspace with alerts on new credentials/role activations/federated-config changes, access reviews run quarterly with automated revocation for leavers, and identity is provisioned from the HR source of truth so deprovisioning is automatic.

**🎯 Senior signal:** workload identity federation over secrets, blanket "audit code admin rights + PIM", "alert on new credentials added to app registrations", and break-glass discipline. Those answers mark someone who can be trusted with a tenant.
