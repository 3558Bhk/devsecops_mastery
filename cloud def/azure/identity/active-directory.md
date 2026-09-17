# Microsoft Entra ID (Azure Active Directory) — Interview Questions

> **Cloud:** Azure · **Category:** Identity · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Entra ID (Azure AD) objects are JSON via **Microsoft Graph** (users, groups, apps) and app registration manifests.

```json
{
  "displayName": "Jane Doe",
  "userPrincipalName": "jane.doe@corp.com",
  "mail": "jane.doe@corp.com",
  "accountEnabled": true,
  "usageLocation": "IN",
  "extension_abc123_Department": "Engineering"
}
```

**Key fields:** `displayName`, `userPrincipalName`, `accountEnabled`, `extension_*` (directory extensions), `identities`. **App registrations** JSON: `displayName`, `signInAudience`, `requiredResourceAccess` (delegated/app permissions), `web.redirectUris`, `keyCredentials`/`passwordCredentials`. Conditional Access policies are also JSON documents.


## Case A — Basic

**A1. What is Microsoft Entra ID (formerly Azure Active Directory)?**
**Answer:** Microsoft's cloud-based **identity and access management** service — it authenticates users, manages identities (users/groups/apps), and provides SSO, MFA, and conditional access for Azure and Microsoft 365 apps.

**A2. What is the difference between Entra ID and on-premises Active Directory (AD DS)?**
**Answer:** **AD DS** = on-prem directory (Kerberos, GPOs, OU hierarchy, domain-joined machines). **Entra ID** = cloud identity (OAuth/OIDC/SAML, groups, RBAC, no GPOs/OUs). They're different technologies, often synchronized (Entra Connect).

**A3. What is a tenant?**
**Answer:** An instance of Entra ID dedicated to an organization — containing its users, groups, and apps, with a unique identity boundary.

**A4. What is a user, group, and application (service principal)?**
**Answer:** A **user** = a person/identity. A **group** = collection of users for permission assignment. A **service principal** = the identity of an application/service for authentication/authorization (opposite of an app registration).

**A5. What is the difference between an app registration and a service principal?**
**Answer:** **App registration** = the global definition of an app (client ID, redirect URIs, permissions). **Service principal** = the app's **instance in a tenant** that can be assigned roles/access. Registration is global; the service principal is per-tenant.

**A6. What is Single Sign-On (SSO)?**
**Answer:** One set of credentials grants access to multiple applications — users authenticate once with Entra ID and access many SaaS/enterprise apps.

**A7. What is Multi-Factor Authentication (MFA)?**
**Answer:** Requiring a second factor (phone, authenticator app, FIDO2 key) in addition to the password — dramatically reducing account-compromise risk.

**A8. What is Conditional Access?**
**Answer:** Policy-based access control: "if [user/device/location/risk] then [require MFA / block / grant]" — the engine that enforces Zero-Trust access.

**A9. What is Azure RBAC vs Entra ID roles?**
**Answer:** **Azure RBAC** = permissions on **Azure resources** (VMs, storage). **Entra ID roles** = directory admin roles (Global Admin, User Admin). Different scopes — managing the directory vs managing resources.

**A10. What is Entra Connect (sync)?**
**Answer:** The tool that **synchronizes on-prem AD identities to Entra ID** (hash sync, pass-through auth, or federation) for hybrid identity.

**A11. What is a managed identity (again, in Entra context)?**
**Answer:** An identity automatically managed by Azure for a resource (VM/App Service) so it can authenticate to Azure services **without credentials**.

**A12. What is B2B vs B2C?**
**Answer:** **B2B** = external collaboration (invite partner users into your tenant, cross-tenant). **B2C** = customer identity for **your apps** (millions of external consumers, branded sign-in).

**A13. What is the difference between authentication and authorization?**
**Answer:** **Authentication** = proving who you are (password/MFA). **Authorization** = what you're allowed to do (roles/policies). Entra ID does both (authN via tokens, authZ via roles/claims).

**A14. What is an OAuth token / ID token?**
**Answer:** **Access token** (OAuth) = grants access to a resource/API. **ID token** (OIDC) = asserts the user's identity (claims). Apps use them for delegated access.

**A15. What is Privileged Identity Management (PIM)?**
**Answer:** Just-in-time, time-bound elevation of **Entra ID / Azure roles** with approval + audit — reducing standing privileged access.

---

## Case B — Advanced (Senior)

**B1. Explain the authentication flow for a web app using OIDC/OAuth (authorization code flow).**
**Answer:** Browser → Entra ID `/authorize` (user logs in, consents) → **authorization code** → app exchanges the code (+ client secret) for an **access token** + **ID token** at `/token` → app validates the token (signature, issuer, audience, expiry) and uses claims. This is the standard secure flow for confidential clients; implicit flow is legacy/discouraged.

**B2. How does Conditional Access enforce Zero Trust (signals → decision → enforcement)?**
**Answer:** It evaluates **signals** (user, group, device compliance, location/IP, sign-in risk, app) against policies: **block**, **grant with controls** (require MFA, compliant device, hybrid-joined), or **session controls** (limited access). This "verify explicitly, least privilege, assume breach" model is the core of Entra ID Zero Trust.

**B3. What are the hybrid identity options (PHS vs PTA vs Federation) and how do you choose?**
**Answer:** **Password Hash Sync** = hashes synced to cloud (simplest, cloud auth, works if on-prem down). **Pass-Through Auth** = cloud validates against on-prem DC (enforces on-prem password policy/lockout, needs an agent). **Federation (ADFS)** = on-prem STS issues tokens (complex, for specific claims/legacy). Most orgs use PHS (+ seamless SSO); choose PTA for strict on-prem policy enforcement; federation only if required.

**B4. How do app registrations, permissions (delegated vs application), and consent work?**
**Answer:** **Delegated permissions** = app acts **on behalf of a user** (scope-limited, user consent/admin consent). **Application permissions** = app acts **as itself** (no user, admin consent required). **Consent** = admin or user grants these permissions; use **admin consent workflow** to control third-party app permissions. Grant least privilege scopes.

**B5. How does Entra ID integrate with Azure RBAC and managed identities for workload access?**
**Answer:** A VM's **managed identity** is a service principal in Entra ID; you assign it **Azure RBAC roles** on resources (e.g., Storage Blob Data Contributor). The workload gets tokens from the IMDS endpoint — no secrets. This replaces service-principal client secrets for Azure-hosted workloads and is the recommended pattern.

**B6. What is Workload Identity Federation, and why is it better than client secrets for CI/CD?**
**Answer:** It lets an **external IdP** (GitHub Actions, Azure DevOps, GCP, K8s OIDC) obtain Entra ID tokens **without a client secret** — trust is established via the IdP's OIDC issuer + subject claim. Benefits: no secret rotation, no leaked secrets in CI, stronger posture. The modern standard for pipeline authentication.

**B7. How do you govern privileged access (PIM, emergency access accounts, break-glass)?**
**Answer:** Use **PIM** for just-in-time elevation of Global Admin/resource roles (with approval, MFA, time-bound, audit). Maintain **2+ break-glass accounts** (cloud-only, excluded from Conditional Access, with alerts on use). Remove **standing admin**, enforce **MFA** for all admins, and review **Access Reviews** periodically.

**B8. What is the difference between a security group and a Microsoft 365 group (and dynamic groups)?**
**Answer:** **Security groups** = permission/access control (Azure RBAC, app access). **Microsoft 365 groups** = collaboration (mailbox, Teams, SharePoint) + access. **Dynamic groups** auto-manage membership by **rules** (e.g., all users in a department) — reducing manual membership drift.

**B9. How does Entra ID handle external identities (B2B collaboration vs B2C) and cross-tenant access?**
**Answer:** **B2B** invites external users as **guest users** (they authenticate with their own IdP; you control their access via roles/Conditional Access). **B2C** is a separate **customer IAM** directory for consumer sign-in to your apps. **Cross-tenant access settings** govern inbound/outbound trust and Conditional Access between tenants.

**B10. How do you secure service principals and prevent credential leakage (rotating secrets, certs, managed identities)?**
**Answer:** Prefer **managed identities** (no secrets) and **Workload Identity Federation** (no secrets); for client secrets, **rotate on schedule** and **alert on expiry** (Microsoft Graph/App registrations); use **certificates** (longer, revocable) over secrets; monitor with **Identity Protection / Sentinel** for anomalous SP usage; restrict SP permissions to least privilege.

**B11. What is Identity Protection (risk detection, risky users/sign-ins) and how does it integrate with Conditional Access?**
**Answer:** Identity Protection uses ML to detect **risky sign-ins** (impossible travel, leaked credentials, unfamiliar location) and **risky users**. Conditional Access policies can then **require MFA / force password change / block** based on risk levels — automated, risk-based protection.

**B12. How do you audit and monitor Entra ID (sign-in logs, audit logs, Sentinel)?**
**Answer:** **Sign-in logs** (who signed in, from where, risk, Conditional Access outcome) and **audit logs** (directory changes) stream to Log Analytics/**Sentinel** for correlation and alerting. Alert on: Global Admin changes, new service principals, anomalous sign-ins, break-glass account use, and risky sign-ins. Retention per compliance.

---

## Case C — Scenario

**C1. Scenario:** A SaaS app must let employees sign in with their corporate accounts (SSO) instead of separate passwords.
**Question:** How do you enable it?
**Answer:** Register the app in **Entra ID** (or configure the SaaS gallery app), set up **SAML/OIDC SSO**, map claims (UPN, groups), assign users/groups, and enforce **MFA + Conditional Access**. Users sign in with corporate credentials; the app receives tokens/claims. Optionally enable **SCIM provisioning** to sync users.

**C2. Scenario:** A developer committed a client secret to a public repo; the app's service principal is now compromised.
**Question:** Respond and prevent recurrence.
**Answer:** Immediately **rotate/delete the client secret**, revoke tokens, review **sign-in logs** for the SP's misuse, and scope down its permissions. Prevent: switch to **Workload Identity Federation** (or managed identity) so there's no secret to leak; add **secret scanning** (Defender for DevOps/GitHub secret scanning) and Conditional Access/PIM for admin workflows.

**C3. Scenario:** Only users on compliant, corporate-managed devices may access a sensitive app; everyone else must use MFA.
**Question:** Configure with Conditional Access.
**Answer:** Create a **Conditional Access policy**: target the app + users, grant control = **require compliant device** (via Intune compliance) **or** **require MFA**; block non-compliant personal devices. Add a second policy requiring **MFA for all admins**. Test in report-only mode, then enforce.

**C4. Scenario:** A user's account was compromised via a leaked password; the attacker signed in from another country.
**Question:** How would Entra ID detect and stop this?
**Answer:** **Identity Protection** flags the sign-in as **risky** (impossible travel / leaked credentials). A **Conditional Access risk policy** then **requires MFA or blocks** the sign-in, and a **user-risk policy** can force a **password reset**. Combined with **MFA**, the leaked password alone is insufficient.

**C5. Scenario:** You must sync on-prem AD users to Azure with password hash sync and keep sign-in working if the on-prem DC is offline.
**Question:** Which hybrid identity method and why?
**Answer:** **Password Hash Sync (PHS)** — hashes are synced to Entra ID, so **cloud authentication** works even when on-prem is down (resilient). PHS also powers **Identity Protection leaked-credential detection**. Pair with **seamless SSO** for a smooth experience. (PTA would fail when on-prem is offline; federation is more complex.)

**C6. Scenario:** An auditor asks for a report of all users with Global Administrator rights, including any recent role changes.
**Question:** How do you produce it and improve the posture?
**Answer:** Query **Entra ID roles** (Global Administrator members via portal/Graph), pull **audit logs** for role assignments in the period, and export for the auditor. Improve: remove standing Global Admins, enforce **PIM** (just-in-time + approval), keep **break-glass** accounts excluded with alerts, and enable **Access Reviews** for admin roles.
