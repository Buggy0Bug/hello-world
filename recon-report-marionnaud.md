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

| # | Severity | Domain | Finding | Reportable |
|---|----------|--------|---------|------------|
| 1 | **CRITICAL** | bdese.marionnaud.fr | Hardcoded AES-256-CBC encryption key+IV in client-side JavaScript | YES |
| 2 | **CRITICAL** | api.marionnaud.fr | Adyen LIVE payment keys + 10+ API keys exposed via /configurations/group (Wayback cache) | YES |
| 3 | **HIGH** | bdes-api.marionnaud.fr | Production API running in development mode with full stack traces | YES |
| 4 | **HIGH** | bdes-api.marionnaud.fr | Email enumeration via /login endpoint — no rate limiting, no CAPTCHA | YES |
| 5 | **HIGH** | extranet.marionnaud.ch | Django superadmin login exposed to internet with password reset + filebrowser | YES |
| 6 | **MEDIUM** | api/media.marionnaud.* (all 16) | CORS wildcard subdomain reflection with credentials on all api/media subdomains | YES |
| 7 | **MEDIUM** | marionnaud.fr | Missing DMARC on primary French domain (all other 7 TLDs have p=reject) | YES |
| 8 | **MEDIUM** | api.marionnaud.* (all 8) | Akamai WAF bypass via URL-encoding (/api/v2/ → /%61pi/v2/) | YES |
| 9 | **MEDIUM** | ecom-data.marionnaud.fr | Active GCP service responding HTTP 400 — requires specific parameters | MAYBE |
| 10 | **LOW-MED** | all marionnaud.* | No CAA records on any domain — any CA can issue certificates | YES |
| 11 | **LOW-MED** | marionnaud.it | Wildcard SPF softfail — any subdomain authorizes Emarsys+Outlook | YES |
| 12 | **LOW** | extranet.marionnaud.ch | Session cookies missing Secure and SameSite flags | YES |
| 13 | **LOW** | all www/api/app.* | Missing HSTS, X-Frame-Options, X-Content-Type-Options across all domains | YES |
| 14 | **INFO** | fs.marionnaud.fr | ADFS server confirmed (HTTP redirect to /adfs/ls/) | NO |
| 15 | **INFO** | api.marionnaud.* | SAP Commerce authorization server endpoints confirmed behind WAF | NO |

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

### FINDING C1: Hardcoded AES-256-CBC Encryption Secrets in Client-Side JavaScript

- **Severity:** CRITICAL
- **Domain:** bdese.marionnaud.fr (193.240.185.11)
- **Status:** LIVE — reproducible now

**Description:**
The BDES employee data platform frontend (React SPA) contains hardcoded encryption credentials in the compiled JavaScript bundle at `/static/js/2.320443c9.chunk.js`:

```
REACT_APP_API_BASE_URL: "https://bdes-api.marionnaud.fr"
REACT_APP_ENCRYPTION_SECRET_KEY: "[REDACTED - 20-char key found in JS bundle]"
REACT_APP_ENCRYPTION_SECRET_IV: "[REDACTED - 20-char IV found in JS bundle]"
REACT_APP_ENCRYPTION_METHOD: "aes-256-cbc"
```

**Impact:**
- Anyone can decrypt data encrypted with these credentials
- BDES (Base de Données Économiques, Sociales et Environnementales) is a French legally-mandated employee database containing sensitive HR data: headcount, wages, working conditions, gender equality metrics
- The key is only 20 characters (not the required 32 bytes for AES-256), suggesting implementation weakness
- The IV is static (should be random per encryption), completely breaking CBC mode security

**Additional Context:**
- Server: nginx/1.25.4
- manifest.json reveals: `"short_name": "Back office"`, `"name": "Back office boilerplate"`
- All routes serve SPA index.html (client-side routing)

---

### FINDING C2: Adyen LIVE Payment Keys + API Keys Exposed via /configurations/group

- **Severity:** CRITICAL
- **Domain:** api.marionnaud.fr
- **Status:** Confirmed via Wayback Machine cache (June 2024). Currently WAF-blocked but endpoint likely still exists.

**Description:**
The OCC API endpoint `GET /api/v2/mfr/configurations/group?lang=fr_FR&curr=EUR` previously returned HTTP 200 with extensive configuration data including LIVE payment credentials and third-party API keys.

**Exposed Payment Gateway Credentials (Adyen - LIVE):**
```
adyen.client.key: [REDACTED - live_* key found]
adyen.environment: LIVE
adyen.client.side.encryption.key: [REDACTED - RSA public key found]
worldpay.apple.merchantIdentifier: [REDACTED - merchant ID found]
```

**Exposed Third-Party API Keys:**
```
googleApiKey: [REDACTED - Google API key found]
powerreviews.apikey.mfr: [REDACTED - UUID API key found]
criteo.partner.id: [REDACTED]
gtm.container.id: [REDACTED - GTM container ID found]
onetrust.script.id: [REDACTED - UUID found]
```

**Exposed Internal Configuration:**
```
loyalty.cheque.points.threshold: [REDACTED]
loyalty.cheque.value: [REDACTED]
loyalty.vouchers.pattern: [REDACTED - regex pattern found]
loyalty.invalid.card.statuses: [REDACTED - status list found]
```

**Impact:**
- Adyen client keys are designed for client-side use, but the volume of internal configuration (loyalty rules, feature flags, payment methods, Apple Pay merchant IDs) provides significant reconnaissance value
- This endpoint should be tested on all country sites for differential exposure

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

### FINDING H2: Email Enumeration + No Rate Limiting on BDES Login

- **Severity:** HIGH
- **Domain:** bdes-api.marionnaud.fr
- **Status:** LIVE — reproducible now

**Reproduction:**
`POST /login` with `{"email":"test@test.com","password":"test"}` returns:
```json
{
  "error": "HttpError",
  "status": 401,
  "message": "Adresse email inconnue"
}
```

- "Adresse email inconnue" = "Unknown email address" — different error for unknown email vs wrong password
- No rate limiting observed
- No CAPTCHA protection
- Joi validation errors on malformed input reveal field requirements
- Combined with employee database context (BDES), enables targeted email enumeration of corporate users

---

### FINDING H3: Django Superadmin Exposed to Internet

- **Severity:** HIGH
- **Domain:** extranet.marionnaud.ch (137.74.20.55, OVH)
- **Status:** LIVE — reproducible now

**Application:** "Marionnaud Master Data Tool" (MDT) — Django CMS

**Exposed login endpoints:**
- `/de/superadmin/` — Django superadmin login
- `/de/superadmin/login/` — Same
- `/de/admin/` — Admin login
- `/fr/` — French admin ("MDT admin")
- `/de/superadmin/password_reset/` — Password reset
- `/de/superadmin/filebrowser/` — File browser (requires auth)
- `/de/superadmin/doc/` — Documentation (requires auth)

**Login form reveals:** CSRF token, username max_length=30, hidden field `this_is_the_login_form=1`

**Additional issues:** Old Django version indicators (IE7 CSS conditionals suggest Django 1.x era), no rate limiting on login.

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

## 14. RECOMMENDED NEXT STEPS

### Immediate Reports (Submit to Intigriti Now)

1. **CRITICAL — BDES Encryption Secrets** (Finding C1)
   - Hardcoded AES key/IV in client JS — immediate, verifiable, high impact
   - Tier 5 wildcard (*.marionnaud.fr) — up to $500

2. **HIGH — BDES API Dev Mode + Stack Traces** (Finding H1)
   - Production API in development mode — immediate, verifiable
   - Can be combined with C1 in same report

3. **HIGH — BDES Email Enumeration** (Finding H2)
   - No rate limiting on login endpoint
   - Can be combined with H1

4. **HIGH — Django Superadmin Exposed** (Finding H3)
   - Internet-exposed admin with password reset + filebrowser
   - Tier 5 wildcard (*.marionnaud.ch) — up to $500

5. **MEDIUM — CORS Wildcard with Credentials** (Finding M1)
   - Affects all 16 api/media domains across all countries
   - Tier 1 scope (api.marionnaud.{fr,at,ch,it}) — up to $3,500

6. **MEDIUM — Missing DMARC on .fr** (Finding M2)
   - Tier 1 scope — up to $3,500

### Further Investigation Required

7. **HTTP probe CT log discoveries** — mobadm, mobconnect, filex, securees, ntf (all on dedicated IPs, not behind Akamai WAF)
8. **Payment gateway probing** — hipaygtw, paygtw across all TLDs (financial transaction handling)
9. **Test /configurations/group on all countries** via browser (to get past Akamai with valid session cookies)
10. **Test prod-cc/api-s1/www-s1 endpoints** — may have different WAF rules or debug features
11. **BDES API deep dive** — fuzz API routes, test IDOR on `/user/{id}`, test encryption implementation
12. **GenAI prompt injection** — test AI review summaries and product comparisons
13. **Django CVE testing** on extranet.marionnaud.ch — old version indicators
14. **Password reset flow** — `/api/v2/{site}/forgottenpasswordtokens`
15. **Anonymous cart manipulation** — `/api/v2/{site}/users/anonymous/carts`
16. **www.eshop.marionnaud.cz** (193.240.185.11) — same IP as BDES, separate e-shop on dedicated infra
17. **SBC/telephony endpoints** — mfr-sbc-01/02 VoIP misconfigurations

### Robots.txt Paths to Test (from browser with valid cookies)

- `/crm/` and `/bcm/` on FR — internal system paths
- `/test` on FR — test environment
- `/c//p/*` double-slash — URL normalization issue
- `/a/` on CH only — unknown purpose
- `?lgw_code=` vs `?LGWCODE=` on CH — case inconsistency
