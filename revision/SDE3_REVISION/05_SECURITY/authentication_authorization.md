# Authentication vs Authorization

## Authentication (AuthN) - Who are you?
- Verifies identity

### Methods
1. **Passwords**: bcrypt hashed + salt
2. **MFA**: Something you know (password) + have (OTP) + are (biometric)
3. **SSO**: Single Sign On (Okta, Azure AD)
4. **Passwordless**: Magic link, WebAuthn

### Tokens
- **Session ID**: Server stores session, client cookie. Stateful.
- **JWT**: Stateless, self-contained. Header.Payload.Signature
  - Access Token: 15 min expiry
  - Refresh Token: 7 days, stored HttpOnly secure cookie, rotated
  - Structure: `eyJhbG...` = base64(header).base64(payload).signature

```json
// JWT payload
{
  "sub": "123",
  "role": "admin",
  "iat": 1713000000,
  "exp": 1713000900
}
```

- **Opaque Token**: Random string, need introspection

### OAuth 2.0 (Authorization Framework, but used for Auth)
- Roles: Resource Owner (user), Client (app), Authorization Server, Resource Server
- Flows:
  - **Authorization Code + PKCE**: For web/mobile apps (MOST SECURE, recommended)
  - **Client Credentials**: Service to service
  - **Implicit**: Deprecated
  - **Password**: Deprecated

Flow (Auth Code):
1. User -> Client: Click login
2. Client -> Auth Server: /authorize?response_type=code&client_id=...&PKCE
3. Auth Server -> User: Login page
4. User logs in -> Auth Server -> Client: code
5. Client -> Auth Server: Exchange code + code_verifier for tokens
6. Client gets access_token + id_token

- **OpenID Connect (OIDC)**: Identity layer on OAuth2, gives id_token (JWT with user info)

## Authorization (AuthZ) - What can you do?

### Models
1. **RBAC**: Role Based Access Control. User -> Role -> Permissions. Simple. `admin can delete`, `user can read`.
2. **ABAC**: Attribute Based. Policy: `if user.dept == resource.dept and time < 5pm allow`. More granular (AWS IAM).
3. **ACL**: Access Control List per resource.
4. **ReBAC**: Relationship Based (Google Zanzibar)

### Implementation
```java
// RBAC check
@PreAuthorize("hasRole('ADMIN')")
@PreAuthorize("hasAuthority('user:write')")

// ABAC example
if (user.getId().equals(resource.getOwnerId()) || user.hasRole("ADMIN")) allow
```

### Best Practices SDE3
- Never trust client, always check server side
- Principle of least privilege
- Deny by default
- Audit logs: who accessed what
- Use centralized AuthZ service (OPA - Open Policy Agent)

## Session vs JWT

| | Session | JWT |
|-|---------|-----|
| Stateful | Yes server stores | No |
| Scale | Need sticky or Redis | Easy scale |
| Revoke | Easy delete session | Hard need blacklist/ short exp |
| Size | Small cookie | Large |
| Use | Monolith web | Microservices, mobile |

**Hybrid Approach (Recommended)**: JWT access token short lived in memory, refresh token in HttpOnly cookie + Redis store, revoke via Redis.

## Interview Q: How to logout with JWT?
- Short expiry + refresh token rotation + blacklist access token in Redis with TTL = remaining exp.
- Or store JWT jti in Redis whitelist.

## Password Storage
```java
// BCrypt
String hashed = BCrypt.hashpw(password, BCrypt.gensalt(12));
// Verify
BCrypt.checkpw(plain, hashed)
```

Never: MD5, SHA1, plain.
