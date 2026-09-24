# AS Watson / Marionnaud — Deep Dive Recon Report

**Date:** 2026-09-24
**Program:** AS Watson / Marionnaud on Intigriti
**Scope:** Marionnaud brand — 8 European countries (FR, AT, CH, IT, HU, CZ, RO, SK)
**Methods:** Passive DNS, OSINT, Certificate Transparency, HTTP probing, WAF fingerprinting, API enumeration
**Bounty Range:** $10–$8,500 (Tiers 1–5)

---

## TABLE OF CONTENTS

1. [Vulnerability Summary](#1-vulnerability-summary)
2. [Attack Surface Overview](#2-attack-surface-overview)
3. [Technology Stack](#3-technology-stack)
4. [Critical Findings](#4-critical-findings)
5. [High Findings](#5-high-findings)
6. [Medium Findings](#6-medium-findings)
7. [Low / Informational Findings](#7-low--informational-findings)
8. [WAF Analysis](#8-waf-analysis)
9. [OCC REST API v2 Mapping](#9-occ-rest-api-v2-mapping)
10. [Certificate Transparency — Novel Subdomains](#10-certificate-transparency--novel-subdomains)
11. [Infrastructure Groups](#11-infrastructure-groups)
12. [Email Security Posture](#12-email-security-posture)
13. [Third-Party Services Map](#13-third-party-services-map)
14. [Recommended Next Steps](#14-recommended-next-steps)

---

## 1. VULNERABILITY SUMMARY

### Triaged Findings (Ready to Submit)

| # | Severity | Domain | Finding | Reportable | Confidence |
|---|----------|--------|---------|------------|------------|
| C1 | **CRITICAL** | bdese.marionnaud.fr | Source maps publicly accessible — full React app source code exposed (48 original TypeScript files) | **YES** | 95% |
| C2 | **CRITICAL** | bdese.marionnaud.fr | Hardcoded AES-256-CBC encryption key+IV for decrypting employee PII including passwords | **YES** | 90% |
| C3 | **CRITICAL** | bdes-api.marionnaud.fr | Passwords stored with reversible encryption (not hashing) — decryptable with exposed key | **YES** | 90% |
| H1 | **HIGH** | bdes-api.marionnaud.fr | Production API running in development mode — verbose stack traces on all errors | **YES** | 85% |
| H2 | **HIGH** | bdes-api.marionnaud.fr | 12-character maximum password length enforced server-side | **YES** | 90% |
| M1 | **MEDIUM** | bdes-api.marionnaud.fr | Email enumeration via /login and /resetToken — no rate limiting, no CAPTCHA | **YES** | 80% |
| M2 | **MEDIUM** | marionnaud.fr | Missing DMARC on primary French domain (all other 7 TLDs have p=reject) | **YES** | 75% |
| M3 | **MEDIUM** | api/media.marionnaud.* (16 domains) | CORS wildcard subdomain reflection with credentials | **YES** | 60% |

### Findings NOT Submitted (Triager Would Reject)

| # | Domain | Finding | Rejection Reason |
|---|--------|---------|-----------------|
| R1 | api.marionnaud.fr | Adyen LIVE keys via Wayback cache | Client keys are public by design; endpoint remediated (WAF-blocked) |
| R2 | extranet.marionnaud.ch | Django superadmin login exposed | Login page visible ≠ vulnerability; no auth bypass demonstrated |
| R3 | api.marionnaud.* | Akamai WAF bypass via URL-encoding | Zero impact — backend returns 404 for encoded paths |
| R4 | ecom-data.marionnaud.fr | GCP service HTTP 400 | Not a vulnerability — API requires parameters |
| R5 | all marionnaud.* | No CAA records | Best practice, universally excluded from bounty |
| R6 | all www/api/app.* | Missing security headers | Best practice, universally excluded |
| R7 | fs.marionnaud.fr | ADFS server confirmed | Reconnaissance data, not a vulnerability |
| R8 | api.marionnaud.* | SAP authz server confirmed behind WAF | Reconnaissance data, not a vulnerability |

---

## 2. ATTACK SURFACE OVERVIEW

### Infrastructure Map

```
                         Internet
                            |
               +------------+------------+
               |                         |
      +--------v--------+     +---------v---------+
      |  Akamai CDN/WAF |     | Non-Akamai Infra  |
      |  23.195/217.x    |     | (dedicated IPs)   |
      +--------+--------+     +---------+---------+
               |                         |
    +----------+----------+    +---------+---------+-----------+
    |          |          |    |         |         |           |
  www.*    api.*    media.*  BDES      UAT      CRM       Legacy
  app.*  campaign.*  prod-cc  193.240  83.98.   83.98.   213.152.
         api-s1.*    www-s1   .185.11  213.204  213.201  23.72-78
```

### Domain Count by Tier

| Tier | Count | Type | Bounty Range |
|------|-------|------|-------------|
| Tier 1 | ~20 | Main e-commerce (FR/AT/CH/IT) | $100–$8,500 |
| Tier 2 | ~20 | E-commerce (HU/CZ/RO/SK) | $100–$5,500 |
| Tier 4 | ~17 | Marketing, supplier portals | $50–$2,000 |
| Tier 5 | 12+ | Wildcard domains | $10–$500 |

### Subdomain Reach Summary

| Subdomain Pattern | Akamai Blocked | Backend Reachable | Live Targets |
|---|---|---|---|
| www.marionnaud.* | YES (403 all paths) | NO | 0 |
| api.marionnaud.* | Partial (/api/v2/ only) | YES | 8 |
| media.marionnaud.* | Partial (/medias/ only) | YES | 8 |
| app.marionnaud.* | NO | YES (404 all paths) | 4 |
| bdes-api/bdese.marionnaud.fr | NO WAF | YES | 2 |
| extranet.marionnaud.ch | NO WAF | YES | 1 |
| prod-cc/api-s1/www-s1.* | Behind Akamai | Varies | 32 |
| paygtw/hipaygtw.* | NO WAF | Unknown | 9 |
| Internal tools (mobadm, filex, etc.) | NO WAF | Unknown | 5 |

---

## 3. TECHNOLOGY STACK (CONFIRMED)

| Component | Technology | Confidence |
|-----------|-----------|------------|
| E-commerce Platform | **SAP Commerce Cloud (Hybris)** | Confirmed |
| Frontend | **SAP Spartacus / Angular SPA** | Confirmed (April 2024 migration) |
| API Layer | **OCC REST API v2** at `/api/v2/` (non-standard path) | Confirmed (Wayback) |
| CDN/WAF | **Akamai** (AkamaiGHost, Kona/App & API Protector) | Confirmed |
| SSL | DigiCert OV certificates (CN: aswatson.eu) | Confirmed |
| Payment | **Adyen** (LIVE), **HiPay**, proprietary payment gateways | Confirmed |
| BDES Backend | **Node.js / Express.js** v1.5.0 | Confirmed |
| BDES Frontend | **React** (Create React App / Webpack), nginx/1.25.4 | Confirmed |
| Extranet | **Django CMS** (Python), nginx | Confirmed |
| ADFS | **Active Directory Federation Services** (fs.marionnaud.fr) | Confirmed |
| Email (FR) | On-premises (Alionis, 77.72.92.5) | Confirmed |
| Email (others) | Microsoft 365 | Confirmed |
| Email Marketing | Emarsys (SAP-owned) | Confirmed |
| CRM | SAP CRM (AWS eu-west-1) | Confirmed (CT logs) |
| Analytics | Google Tag Manager (GTM-TRJ6LQG), Contentsquare | Confirmed |
| Reviews | PowerReviews | Confirmed |
| Affiliate | Awin | Confirmed |
| Consent | OneTrust | Confirmed |
| Advertising | Criteo | Confirmed |
| O365 Tenant | `asweu.onmicrosoft.com` (AS Watson EU) | Confirmed |
| Security Training | KnowBe4 | Confirmed |
| GenAI | AI review summaries + product comparisons (CMS components) | Confirmed |
| Recruitment | Cornerstone OnDemand (CSOD) | Confirmed |

---

## 4. CRITICAL FINDINGS

### FINDING C1: Source Maps Publicly Accessible — Full Application Source Code Exposed

- **Severity:** CRITICAL
- **Domain:** bdese.marionnaud.fr (193.240.185.11)
- **Status:** LIVE — reproducible now

**Description:**
All JavaScript source maps for the BDES employee data platform are publicly accessible, exposing the complete original TypeScript/React source code (48 files):

```
GET https://bdese.marionnaud.fr/static/js/main.ff712824.chunk.js.map → HTTP 200 (215KB)
GET https://bdese.marionnaud.fr/static/js/2.320443c9.chunk.js.map → HTTP 200 (2.5MB+)
GET https://bdese.marionnaud.fr/static/js/runtime-main.c02469a1.js.map → HTTP 200
GET https://bdese.marionnaud.fr/asset-manifest.json → HTTP 200 (lists all files)
```

**Exposed source files include:**
- `utils/encryption.ts` — full encryption implementation with key derivation
- `store/api/_client.ts` — API client with hardcoded credentials
- `store/api/auth.ts` — authentication endpoints (login, logout, reset)
- `store/api/users.ts` — user CRUD operations (list, details, create, update, delete)
- `store/api/documents.ts` — document CRUD with file upload
- `store/api/apiTypes.ts` — complete data model (User, Document, Section, Roles enum)
- `pages/login/Login.tsx` — login form with password reset flow
- `pages/resetPassword/ResetPassword.tsx` — password reset consuming URL token
- `pages/users/UserDrawer.tsx` — user management form with password policy
- `components/ProtectedRoute.tsx` — authorization logic
- `routes.ts` — complete routing map
- `configureStore.ts`, `App.tsx` — application configuration

**Impact:**
- Complete application architecture disclosed to attackers
- Enables targeted attacks against known API endpoints and authorization logic
- Reveals encryption implementation, hardcoded secrets, and password policy (see C2, C3)

---

### FINDING C2: Hardcoded AES-256-CBC Encryption Secrets + Reversible Password Encryption

- **Severity:** CRITICAL
- **Domain:** bdese.marionnaud.fr + bdes-api.marionnaud.fr
- **Status:** LIVE — reproducible now

**Description:**
Source code recovered from source maps reveals that employee PII (including passwords) is encrypted with AES-256-CBC using a **static key and IV hardcoded in client-side JavaScript**. The encryption is **reversible** — passwords are NOT hashed.

From `utils/encryption.ts` (recovered via source map):
```typescript
class Encryption {
  constructor(config) {
    // Key derivation: SHA-512 of static secret, truncated to 32 hex chars
    this.KEY = crypto.createHash('sha512').update(config.secretKey).digest('hex').substring(0, 32);
    this.ENCRYPTION_IV = crypto.createHash('sha512').update(config.secretIv).digest('hex').substring(0, 16);
  }

  public decryptUser(user: User) {
    return {
      email: this.decryptData(user.email),
      firstName: this.decryptData(user.firstName),
      lastName: this.decryptData(user.lastName),
      password: this.decryptData(user.password),        // PASSWORDS!
      phone: this.decryptData(user.phone),
      position: this.decryptData(user.position),
      role: this.decryptData(user.role),
      oldPasswords: user.oldPasswords?.map(p => this.decryptData(p)),  // OLD PASSWORDS TOO
    };
  }
}
```

Hardcoded configuration from compiled bundle and `store/actions/auth.ts`:
```
REACT_APP_ENCRYPTION_SECRET_KEY: "[REDACTED - 20-char static key]"
REACT_APP_ENCRYPTION_SECRET_IV:  "[REDACTED - 20-char static IV]"
REACT_APP_ENCRYPTION_METHOD:     "aes-256-cbc"
```

Hardcoded API key from `store/api/_client.ts`:
```typescript
headers: { 'x-bdes-api-key': '[REDACTED - API key]' }
```

**Impact:**
- **Passwords stored reversibly encrypted, not hashed** — any database leak = immediate cleartext passwords
- **Static key/IV** — all users' data encrypted with the SAME key (no per-user salt or nonce)
- **Decryption key publicly accessible** in client-side JavaScript
- **Old password history** also stored and decryptable
- **12-character maximum password length** enforced server-side (confirmed: "Trop long, 12 caractères max.")
- BDES is a French legally-mandated employee database — GDPR implications
- User roles include: administrateur, gestionnaire, consultation, signup

### FINDING C2-REJECTED: Adyen LIVE Payment Keys (NOT SUBMITTED)

- **Previous Severity:** CRITICAL → **Revised: INFORMATIONAL (Not Submitted)**
- **Reason:** Adyen client-side keys are **designed for browser exposure** per Adyen documentation. The /configurations/group endpoint is now WAF-blocked (remediated). This is a common false positive in bug bounty.

---

## 5. HIGH FINDINGS

### FINDING H1: Production API Running in Development Mode with Stack Traces

- **Severity:** HIGH
- **Domain:** bdes-api.marionnaud.fr (193.240.185.11)
- **Status:** LIVE — reproducible now

**Root endpoint response (HTTP 200):**
```json
{
  "name": "bdes-api",
  "version": "1.5.0",
  "env": "development",
  "instance": "[REDACTED]",
  "request": "[REDACTED]"
}
```

**Stack trace on `GET /users` (HTTP 401):**
```json
{
  "error": "HttpError",
  "status": 401,
  "message": "No refresh token found",
  "data": {"env": "development"},
  "stack": [
    "HttpError: No refresh token found",
    "    at exports.checkAuth (/app/helpers/sessionManager.js:52:15)",
    "    at exports.isLogged (/app/controllers/middlewares.js:54:53)",
    "    at wrapper (/app/helpers/asyncExpress.js:34:36)"
  ]
}
```

**Leaked internal paths:** `/app/helpers/sessionManager.js`, `/app/controllers/middlewares.js`, `/app/helpers/asyncExpress.js`, `/app/controllers/auth.js`, `/app/helpers/errors.js`

**Impact:** Version disclosure, instance ID disclosure, development mode enables verbose errors and potentially relaxed security, full internal file structure revealed.

---

### FINDING H2: 12-Character Maximum Password Length

- **Severity:** HIGH
- **Domain:** bdes-api.marionnaud.fr
- **Status:** LIVE — reproducible now

**Reproduction:**
`POST /reset` with `{"token":"test","password":"1234567890123"}` returns:
```json
{
  "data": {
    "validation": {
      "password": {
        "message": "Trop long, 12 caractères max.",
        "field": "password"
      }
    }
  }
}
```

Source code confirms differential policy by role:
- `consultation` role: 8 characters max
- All other roles (administrateur, gestionnaire): 12 characters max

Combined with reversible encryption (not hashing) and exposed decryption key, this severely limits the password keyspace.

---

### FINDING H3 (DOWNGRADED): Email Enumeration on BDES Login and Password Reset

- **Previous Severity:** HIGH → **Revised: MEDIUM**
- **Domain:** bdes-api.marionnaud.fr
- **Status:** LIVE — reproducible now

Both `/login` and `/resetToken` endpoints differentiate between known and unknown emails:
- Login: "Adresse email inconnue" (Unknown email address) vs different error for wrong password
- Reset: "Utilisateur inconnu." (Unknown user) vs success
- No rate limiting or CAPTCHA on either endpoint

---

### FINDING H4-REJECTED: Django Superadmin Exposed (NOT SUBMITTED)

- **Previous Severity:** HIGH → **Revised: INFORMATIONAL (Not Submitted)**
- **Domain:** extranet.marionnaud.ch
- **Reason:** An accessible login page is not a vulnerability. No unauthorized access, auth bypass, default credentials, or exploitable CVE demonstrated. Password reset requires authentication first.

---

## 6. MEDIUM FINDINGS

### FINDING M1: CORS Wildcard Subdomain Reflection with Credentials

- **Severity:** MEDIUM
- **Affected:** All 8 api.marionnaud.* AND all 8 media.marionnaud.* (16 domains)
- **Status:** LIVE — reproducible now

The CORS configuration accepts any subdomain of `marionnaud.{tld}` as a valid origin AND allows credentials:

| Origin Tested | ACAO Response | Credentials |
|---|---|---|
| `https://evil.com` | Default self-origin (NOT reflected) | true |
| `https://attacker.marionnaud.fr` | **REFLECTED** | true |
| `https://www.marionnaud.fr` | **REFLECTED** | true |
| `null` | Default self-origin | true |
| `https://marionnaud.fr.evil.com` | Default (NOT reflected) | true |
| Cross-TLD (e.g., `.it` on `.fr` API) | Default (NOT reflected) | true |

**Impact:** If an attacker can take over ANY subdomain of `marionnaud.{tld}` (dangling DNS, subdomain takeover, XSS on any subdomain), they can make credentialed cross-origin requests to the API and steal user data/sessions.

**Reproduction:**
```bash
curl -sI -H "Origin: https://attacker.marionnaud.fr" \
  "https://api.marionnaud.fr/" | grep -i "access-control"
```

---

### FINDING M2: Missing DMARC on marionnaud.fr

- **Severity:** MEDIUM
- **Domain:** marionnaud.fr (primary French domain)

ALL other 7 TLDs have DMARC `p=reject` with OnDMARC (Red Sift) monitoring. France alone has NO DMARC record. SPF exists with `-all` hardfail, but without DMARC receivers won't enforce consistently. marionnaud.fr is also the only domain on on-premises email (Alionis, not M365) — suggests incomplete migration.

---

### FINDING M3: Akamai WAF Bypass via URL Encoding

- **Severity:** MEDIUM
- **Affected:** All api.marionnaud.* domains

The Akamai WAF rule blocking `/api/v2/` is a simple literal string match that can be bypassed:

```
/api/v2/mfr/languages     -> 403 (WAF blocked)
/%61pi/v2/mfr/languages   -> 404 (WAF bypassed, reached backend)
/a%70i/v2/mfr/languages   -> 404 (WAF bypassed, reached backend)
/api;/v2/mfr/languages    -> 404 (WAF bypassed via semicolon)
```

**Impact:** The backend doesn't normalize encoded paths (data isn't extractable this way currently), but this demonstrates a WAF configuration weakness that could become exploitable if backend routing changes.

---

### FINDING M4: ecom-data.marionnaud.fr Service Exposure

- **Severity:** MEDIUM
- **Host:** ecom-data.marionnaud.fr (Google Cloud Platform)

All paths return HTTP 400 with empty body (not 404), suggesting the service is active but requires specific request parameters. robots.txt is accessible with restrictive rules (allows only `*.js` and `*.html`, disallows everything else).

---

## 7. LOW / INFORMATIONAL FINDINGS

### FINDING L1: No CAA Records on Any Domain
Any Certificate Authority can issue certificates for all marionnaud.* domains. Should restrict to DigiCert.

### FINDING L2: marionnaud.it Wildcard SPF Softfail
ANY subdomain of marionnaud.it returns a wildcard TXT with SPF `~all` (softfail) authorizing Emarsys + Outlook. Undermines the parent domain's strict OnDMARC setup.

### FINDING L3: Session Cookies Missing Secure/SameSite (extranet.marionnaud.ch)
`csrftoken` and `sessionid` cookies lack `Secure` and `SameSite` attributes.

### FINDING L4: Missing Security Headers Across All Domains

| Header | www.* | api.* | app.* | media.* |
|--------|-------|-------|-------|---------|
| HSTS | MISSING | MISSING | MISSING | MISSING |
| CSP | frame-ancestors only | MISSING | MISSING | frame-ancestors |
| X-Frame-Options | MISSING | MISSING | MISSING | MISSING |
| X-Content-Type-Options | MISSING | MISSING | MISSING | MISSING |
| X-XSS-Protection | MISSING | MISSING | MISSING | MISSING |
| COOP | same-origin-allow-popups | MISSING | MISSING | MISSING |

### FINDING L5: SAP Commerce Authorization Server Confirmed
The OAuth authorization server endpoints exist behind Akamai (403 vs 404 for non-existent paths):
`/authorizationserver/oauth/token`, `/authorize`, `/check_token`, `/token_key`, `/revoke`

### FINDING L6: ADFS Server Confirmed (fs.marionnaud.fr)
HTTP port 80 redirects `/adfs/ls/` to HTTPS. HTTPS times out (likely IP-restricted). FederationMetadata.xml redirect also confirmed.

---

## 8. WAF ANALYSIS

### Akamai Configuration

| Component | Status |
|-----------|--------|
| CDN/WAF | Akamai (AkamaiGHost server header, edgesuite.net error URLs) |
| Bot Manager | NOT observed (no _abck, bm_sz, ak_bmsc cookies) |
| Kona Site Defender | Likely active (403 patterns) |
| Debug Mode | DISABLED (Pragma debug headers not honored) |
| Geo-blocking | Active on www.* (all requests blocked, even homepage) |

### Blocking Behavior by Subdomain

| Subdomain | Root Path | /api/v2/* | /medias/* | /_ui/* | /authorizationserver/* | Other |
|-----------|-----------|-----------|-----------|--------|----------------------|-------|
| www.* | 403 | 403 | 403 | 403 | 403 | 403 (all paths) |
| api.* | 404 | **403** | **403** | **403** | **403** | 404 |
| media.* | 404 | **403** | **403** | 404 | N/A | 404 |
| app.* | 404 | 404 | 404 | 404 | 404 | 404 |

**Key insight:** On api.* domains, 403 = path EXISTS behind Akamai; 404 = path does NOT exist. This differential allows path discovery.

### HTTP Method Restrictions (api.marionnaud.fr)

| Method | Response |
|--------|----------|
| GET / | 404 (backend) |
| POST / | 403 (Akamai block) |
| PUT / | 403 (Akamai block) |
| DELETE / | 404 (backend) |
| OPTIONS / | 404 (backend) |

### SAP Admin Paths (all properly blocked)
`/hac/`, `/backoffice/`, `/smartedit/`, `/solr/`, `/admin/` — all return 403 on www (Akamai) or 404 on api (not exposed).

---

## 9. OCC REST API v2 MAPPING

### API Path Discovery
The OCC API uses non-standard path `/api/v2/` (NOT the default SAP `/occ/v2/`). Discovered via Wayback Machine CDX data — all live `/api/v2/` requests are WAF-blocked.

### baseSiteIds

| Country | API Host | baseSiteId | Language | Currency |
|---------|----------|------------|----------|----------|
| France | api.marionnaud.fr | mfr | fr_FR | EUR |
| Austria | api.marionnaud.at | mat-spa | de_AT | EUR |
| Italy | api.marionnaud.it | mit-spa | it_IT | EUR |
| Romania | api.marionnaud.ro | mro-spa | ro_RO | RON |
| Slovakia | api.marionnaud.sk | msk-spa | sk_SK | EUR |

**Pattern:** France uses `mfr` (no suffix); others use `m{cc}-spa`.

### Confirmed OCC Endpoints (from Wayback CDX, historically HTTP 200)

```
GET /api/v2/mfr/basestores/mfr?fields=deliveryCountries
GET /api/v2/mfr/catalogs/brands?codes={brandIds}&fields=DEFAULT
GET /api/v2/mfr/categories/brandRoot/map?requestSource=TOP_NAVIGATION&fields=FULL
GET /api/v2/mfr/cms/components?fields=DEFAULT&componentIds={ids}
GET /api/v2/mfr/cms/pages?pageType=CategoryPage&code={code}
GET /api/v2/mfr/configurations/group                    <-- CRITICAL: leaks config
GET /api/v2/mfr/products/{productCode}?fields=FULL,couponCodeValue
GET /api/v2/mfr/products?fields=PLP,couponCodeValue,rrpPrice&codes={codes}
GET /api/v2/mro-spa/search/popularTerms?maxResults=50   (Romania only)
GET /api/v2/mro-spa/translations/auth?plain=false       (Romania only)
GET /api/v2/mro-spa/redirects/{path}                    (Romania only)
```

### CMS Components Discovered (GenAI integration)
- `GenAIReviewSummaryComponent` — AI-generated review summaries
- `GenAIProductComparisonCTAComponent` — AI product comparisons
- `PowerReviewsReviewsComponent`
- `PDPSponsoredProductCarouselComponent`

---

## 10. CERTIFICATE TRANSPARENCY — NOVEL SUBDOMAINS

**Source:** crt.sh | **12 TLDs queried** | **177 novel subdomains** discovered | **111 resolve to live IPs** (63%)

### High-Priority Discoveries (Dedicated IPs — Not Behind Akamai)

| Priority | Subdomain | IP | Purpose |
|----------|-----------|-----|---------|
| **P1** | mobadm.marionnaud.fr | 213.152.23.76 | Mobile admin panel |
| **P1** | mobconnect.marionnaud.fr | 213.152.23.78 | Mobile connection service |
| **P1** | filex.marionnaud.com | 213.152.23.75 | File exchange platform |
| **P1** | securees.marionnaud.com | 92.71.21.199 | Secure ES service (unknown) |
| **P1** | ntf.marionnaud.com | 52.51.205.105 | Notification service (AWS) |
| **P2** | hipaygtw.marionnaud.fr | 193.240.185.18 | HiPay payment gateway |
| **P2** | paygtw.marionnaud.{fr,it,es,ro,sk} | 207.218.29.230 | Payment gateway |
| **P2** | paygtw.marionnaud.at | 193.240.48.49 | Payment gateway (AT) |
| **P2** | paygtw.marionnaud.{cz,hu} | 193.240.185.26 | Payment gateway (CZ/HU) |
| **P3** | eshop.marionnaud.cz | 23.217.77.130 | E-shop (Akamai) |
| **P3** | www.eshop.marionnaud.cz | 193.240.185.11 | E-shop www (dedicated!) |
| **P3** | job.marionnaud.cz | 79.174.130.80 | Job portal (dedicated) |
| **P3** | careers.marionnaud.com | 104.18.14.179 | Careers (Cloudflare) |
| **P4** | mfr-sbc-01.marionnaud.com | 213.41.67.73 | SBC/telephony #1 |
| **P4** | mfr-sbc-02.marionnaud.com | 212.133.82.182 | SBC/telephony #2 |
| **P5** | enterpriseenrollment.marionnaud.{hu,cz,ro,sk} | 193.240.48.43 | MDM enrollment |

### Staging/Secondary Production Endpoints (All Behind Akamai)

Present on ALL 8 country TLDs:
- `prod-cc.marionnaud.*` — CC production environments
- `api-s1.marionnaud.*` — Secondary API endpoints
- `media-s1.marionnaud.*` — Secondary media endpoints
- `www-s1.marionnaud.*` — Secondary web frontends
- `app-cc.marionnaud.fr` — CC app environment (FR only)

### Non-Resolving but Historically Interesting (from CT logs)

`vpn.marionnaud.com`, `vpn1/vpn2.marionnaud.com`, `adm.marionnaud.com`, `owa/owa2.marionnaud.at`, `admin.marionnaud.cz`, `mdm.marionnaud.ch`, `cp-unifi.marionnaud.ch` (UniFi controller), `booking.marionnaud.ch`, `blog.marionnaud.ch`, `rpc.marionnaud.at`

### Emarsys Email Marketing Infrastructure

Discovered via CT logs — consistent pattern across all countries:
- `m{cc}.marionnaud.com` → Emarsys (192.243.228.1)
- `m.m{cc}.marionnaud.com` → Mobile tracking (AWS)
- `t.m{cc}.marionnaud.com` → Click/open tracking (AWS)
- `res.m{cc}.marionnaud.com` → Email resources (CloudFront)
- `mta-sts.sapcrmemaileuwest1.marionnaud.com` → SAP CRM email (AWS eu-west-1)

---

## 11. INFRASTRUCTURE GROUPS

| Group | IPs | Domains | Notes |
|-------|-----|---------|-------|
| **Akamai Main** | 23.195.81.x, 23.217.77.x | www/api/app/media + prod-cc/api-s1/www-s1 (60+ domains) | Primary e-commerce |
| **Akamai Campaign** | 23.217.76.206 | 7x campaign.*, jeux-concours.fr | Marketing |
| **Google Cloud** | 216.239.{32,34,36,38}.21 | 8x ecom-data.* | Analytics/data |
| **BDES Dedicated** | 193.240.185.11 | bdes-api/bdese.marionnaud.fr, www.eshop.cz | Employee data |
| **CRM** | 83.98.213.201 | crm.marionnaud.fr/it/at | Customer data (firewalled) |
| **UAT** | 83.98.213.204 | uat.marionnaud.fr/at | Pre-production (firewalled) |
| **Legacy (Zayo)** | 213.152.23.72–78 | fs/filex/mobadm/mobconnect.fr | Internal tools |
| **Payment (shared)** | 207.218.29.230 | paygtw.{fr,it,es,ro,sk} | Payment processing |
| **Payment (AS Watson)** | 193.240.48.49, .185.18/.26 | paygtw.at, hipaygtw.fr, paygtw.{cz,hu} | Payment processing |
| **MDM** | 193.240.48.43 | enterpriseenrollment.{hu,cz,ro,sk} | Device management |
| **OVH** | 137.74.20.55 | extranet.marionnaud.ch | Django MDT |
| **Alionis** | 77.72.92.x | static.fr, MX gateway | French hosting |
| **AWS** | 52.51.205.105 | ntf.marionnaud.com | Notifications |
| **Emarsys** | 192.243.228.1 | m{cc}.marionnaud.com (7 countries) | Email marketing |
| **Cloudflare** | 104.18.14.179 | careers.marionnaud.com | Careers portal |

---

## 12. EMAIL SECURITY POSTURE

| Domain | MX | SPF | DMARC | Rating |
|--------|-----|-----|-------|--------|
| marionnaud.fr | On-prem (Alionis) | `-all` (hard) | **MISSING** | **WEAK** |
| marionnaud.at | M365 | OnDMARC | `p=reject` | STRONG |
| marionnaud.ch | M365 | OnDMARC | `p=reject` | STRONG |
| marionnaud.it | M365 | OnDMARC | `p=reject` | STRONG |
| marionnaud.hu | M365 | OnDMARC | `p=reject` | STRONG |
| marionnaud.cz | M365 | OnDMARC | `p=reject` | STRONG |
| marionnaud.ro | M365 | OnDMARC | `p=reject` | STRONG |
| marionnaud.sk | M365 | OnDMARC | `p=reject` | STRONG |

---

## 13. THIRD-PARTY SERVICES MAP

| Service | Purpose | Evidence |
|---------|---------|---------|
| Akamai | CDN + WAF + DNS | AkamaiGHost headers, edgesuite.net |
| SAP Commerce Cloud | E-commerce platform | OCC CORS headers |
| Adyen | Payment processing (LIVE) | /configurations/group |
| HiPay | Payment processing | hipaygtw subdomain |
| Microsoft 365 | Email + productivity | MX records (7 countries) |
| Emarsys (SAP) | Email marketing | SPF + CT log subdomains |
| SAP CRM | Customer relationship | mta-sts.sapcrmemaileuwest1 |
| Contentsquare | Digital analytics | Tech profiles |
| Google Analytics/GTM | Web analytics | GTM-TRJ6LQG |
| PowerReviews | Product reviews | API key in config |
| Criteo | Advertising | Partner ID in config |
| OneTrust | Consent management | Script ID in config |
| Awin | Affiliate network | robots.txt |
| KnowBe4 | Security awareness training | TXT record (.it) |
| DocuSign | Document signing | TXT record (.it) |
| OnDMARC (Red Sift) | Email auth monitoring | DMARC rua records |
| Cornerstone OnDemand | Recruitment ATS | recrutement.fr redirect |
| Amazon SES | Transactional email | SPF records |

---

## 14. BUG BOUNTY SUBMISSION STRATEGY

### Report 1: CRITICAL — BDES Employee Data Platform Chain (Submit NOW)

**Bundle findings:** C1 + C2 + H1 + H2 + H3 as one comprehensive report titled "BDES Employee Data Platform — Source Code Exposure + Reversible Password Encryption + Hardcoded Secrets"

**The chain:**
1. Source maps expose full application source code (C1)
2. Source code reveals encryption implementation with hardcoded key/IV (C2)
3. Employee passwords stored with reversible encryption, not hashing (C2)
4. 12-character max password + old password history stored (H2)
5. API running in dev mode with full stack traces (H1)
6. Email enumeration on login and password reset (H3)

**Scope:** Tier 5 (*.marionnaud.fr, $10-$500)
**Expected bounty:** $200-$500
**Confidence:** 90% accepted at HIGH-CRITICAL

### Report 2: MEDIUM — Missing DMARC on marionnaud.fr (Submit NOW)

**Simple standalone report.** All 7 other TLDs have p=reject; .fr alone has no DMARC.
**Scope:** Tier 1 ($100-$8,500)
**Expected bounty:** $100-$500
**Confidence:** 75% accepted

### Report 3: MEDIUM — CORS Wildcard Subdomain Reflection (Submit NOW, lower priority)

**16 api/media domains reflect any *.marionnaud.{tld} origin with credentials.**
**Scope:** Tier 1 ($100-$8,500)
**Expected bounty:** $100-$500
**Confidence:** 60% accepted (theoretical without subdomain takeover chain)

### Findings Rejected After Triage (Do NOT Submit)

| Finding | Reason |
|---------|--------|
| Adyen client keys | Public by design per Adyen docs; endpoint remediated |
| Django admin login | Login page ≠ vulnerability; no auth bypass |
| WAF bypass via URL encoding | Zero impact — backend 404s on encoded paths |
| Missing security headers | Universally excluded from bounty programs |
| No CAA records | Best practice, not vulnerability |
| SAP/ADFS confirmed | Reconnaissance data, not vulnerabilities |

### BDES API Complete Route Map (From Source Code + Testing)

**Unauthenticated endpoints:**
- `GET /` — API info (name, version, env, instance)
- `POST /login` — email + password auth (cookie-based sessions)
- `POST /resetToken` — password reset token request
- `POST /reset` — password reset (token + password)

**Authenticated (isLogged middleware):**
- `GET /me` — current user info
- `GET /users` — user listing with pagination
- `GET /user/:id` — user details
- `GET /documents` — document listing
- `GET /document/:id` — document details
- `GET /document/:id/content` — document content
- `DELETE /document/:id` — delete document
- `POST /logout` — logout
- `GET /structure` — BDES organizational structure
- `GET /sections` — section listing
- `GET /section/:id` — section details

**Admin (isAdmin middleware):**
- `POST /user` — create user
- `PUT /user/:id` — update user
- `DELETE /user/:id` — delete user

**Manager (canManage middleware):**
- `POST /document` — create document (FormData upload)
- `PUT /document/:id` — update document
- `POST /section` — create section
- `PUT /section/:id` — update section
- `DELETE /section/:id` — delete section

**Static:**
- `GET /files/` — static file serving (empty directory)

### Further Investigation (Higher ROI Targets)

1. **BDES account takeover via password reset**: Test if reset tokens are predictable, sequential, or enumerable
2. **BDES IDOR**: If any auth is obtained, test horizontal access on `/user/:id` and `/document/:id`
3. **GenAI prompt injection**: Test AI review/comparison features on main e-commerce (requires browser-based testing to bypass Akamai WAF)
4. **SAP OCC API**: All endpoints blocked by Akamai; requires browser session cookies
5. **CZ e-shop** (193.240.185.11): Same IP as BDES — may share infrastructure vulnerabilities

### Robots.txt Paths to Test (from browser with valid cookies)

- `/crm/` and `/bcm/` on FR — internal system paths
- `/test` on FR — test environment
- `/c//p/*` double-slash — URL normalization issue
- `/a/` on CH only — unknown purpose
- `?lgw_code=` vs `?LGWCODE=` on CH — case inconsistency
