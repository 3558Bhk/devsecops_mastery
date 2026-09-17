# Security - Basics for SDE3

## CIA Triad
- **Confidentiality**: Data only to authorized (encryption)
- **Integrity**: Data not tampered (hashing, signatures)
- **Availability**: System up (DDoS protection, HA)

## Encryption

### Symmetric vs Asymmetric
- **Symmetric**: Same key encrypt/decrypt. AES-256. Fast. For data at rest, large data.
- **Asymmetric**: Public/Private key. RSA 2048, ECC. Slow. For key exchange, signatures.
- **Hybrid**: Use asymmetric to exchange symmetric key (TLS does this)

### Hashing
- One-way, irreversible. SHA-256, bcrypt, Argon2
- Use for passwords: NEVER store plain, use bcrypt with salt (cost factor 12)
- SHA-256 for integrity, not passwords (too fast)

## TLS / HTTPS
- TLS 1.2, 1.3 (1.0,1.1 deprecated)
- Handshake: ClientHello -> ServerHello + cert -> Key exchange -> Encrypted
- Certificate: X.509, issued by CA, contains public key
- Let's Encrypt free

## Common Attacks & Mitigations
| Attack | Mitigation |
|--------|------------|
| SQL Injection | Prepared statements, ORM |
| XSS | Escape output, CSP header, HttpOnly cookies |
| CSRF | CSRF token, SameSite cookie |
| DDoS | Rate limit, CDN Cloudflare, WAF |
| Man in Middle | HTTPS, HSTS, cert pinning |
| Brute Force | Rate limit, CAPTCHA, account lock |
| Replay | Nonce, timestamp, JWT exp short |

## Security Headers (Must Mention)
```
Strict-Transport-Security: max-age=31536000; includeSubDomains
Content-Security-Policy: default-src 'self'
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 0 (deprecated, use CSP)
Referrer-Policy: strict-origin-when-cross-origin
```

## Data Protection
- **At Rest**: AES-256 encryption (DB, S3 SSE)
- **In Transit**: TLS
- **In Use**: Confidential computing (advanced)
- **Secrets**: Vault, AWS Secrets Manager, not in code/env file git

## Key Management
- AWS KMS, HashiCorp Vault
- Rotate keys regularly
- Principle of least privilege

## Interview Scenario: Secure API Design
1. HTTPS only
2. Auth: OAuth2 + JWT short lived (15min) + refresh token rotation
3. Rate limiting per IP/user
4. Input validation (whitelist)
5. Output encoding
6. Logging without sensitive data
7. WAF
