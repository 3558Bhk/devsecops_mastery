# OWASP Top 10 (2021/2023) + JWT Best Practices

## OWASP Top 10 2021 (Must Memorize)

### A01: Broken Access Control
- IDOR: /users/123 -> change to 124 get other user
- Fix: Check owner, RBAC

### A02: Cryptographic Failures
- Plain HTTP, weak encryption
- Fix: TLS, AES-256, bcrypt

### A03: Injection
- SQL, NoSQL, LDAP, OS command
- Fix: Prepared statements, ORM, input validation
```java
// Bad
query = "SELECT * FROM users WHERE id = " + userInput
// Good
PreparedStatement ps = conn.prepareStatement("SELECT * FROM users WHERE id = ?");
ps.setString(1, userInput);
```

### A04: Insecure Design
- No threat modeling
- Fix: Security by design, secure design patterns

### A05: Security Misconfiguration
- Default creds, verbose errors, open S3 bucket
- Fix: Hardening, minimal config, automated scanning

### A06: Vulnerable Components
- Log4Shell, old libs
- Fix: SCA tools (Snyk, Dependabot), update

### A07: Identification & Auth Failures
- Weak passwords, no MFA, session fixation
- Fix: MFA, strong password policy, secure session

### A08: Software & Data Integrity Failures
- Deserialization insecure, no CI/CD integrity
- Fix: Sign artifacts, verify

### A09: Logging & Monitoring Failures
- No logs for breach, no alerting
- Fix: Central logging (ELK), SIEM, alert on anomaly

### A10: SSRF (Server Side Request Forgery)
- Server fetches attacker URL, access internal metadata (169.254.169.254)
- Fix: Whitelist URLs, disable internal access, no redirect

## JWT Best Practices (Interview Favorite)

### Do
- Short expiry: access 15 min, refresh 7 days rotation
- Use RS256 (asymmetric) for microservices (public key verify)
- Validate signature, exp, iss, aud
- Store access token in memory (JS variable), refresh in HttpOnly Secure SameSite=Strict cookie
- Use jti (JWT ID) for revocation tracking
- Rotate refresh tokens

### Don't
- Don't store sensitive data in payload (it's base64 not encrypted)
- Don't use none algorithm
- Don't store JWT in localStorage (XSS steals) - if must, ensure CSP strict
- Don't use long expiry

### JWT Structure Validation
```js
// Pseudocode
try {
  decoded = verify(token, publicKey, {algorithms: ['RS256'], issuer: 'auth.example.com', audience: 'api.example.com'})
  if (decoded.exp < now) throw expired
} catch(e) { return 401 }
```

## OAuth2 Security
- Always PKCE for public clients (mobile/SPA)
- State parameter to prevent CSRF
- No tokens in URL fragment
- Validate redirect_uri exact match (no open redirect)

## CORS
```js
// Bad
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true

// Good
Access-Control-Allow-Origin: https://app.example.com
Access-Control-Allow-Credentials: true
Vary: Origin
```

## Rate Limiting
- Implement at API Gateway
- Algorithms: Token Bucket, Leaky Bucket, Fixed Window, Sliding Window
- Return 429 + Retry-After
